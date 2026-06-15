import XCTest
import CryptoKit
import MaverickNoise
@testable import MaverickRemote

@MainActor
final class PairingControllerTests: XCTestCase {

    // A valid maverick://pair/v1 URL built from a known daemon static key so the
    // stub's PairingResult and the parsed payload agree.
    private struct Fixture {
        let url: String
        let daemonStaticKey: Data
        let host: String
        let result: PairingResult
    }

    private func makeFixture(host: String = "10.0.0.7", port: Int = 8765) -> Fixture {
        // Deterministic daemon static key + matching fingerprint so QRPayload.parse
        // accepts the `f` field.
        let daemonKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let token = Data((0..<16).map { UInt8($0) })
        let k = Base64URL.encode(daemonKey)
        let t = Base64URL.encode(token)
        let f = Fingerprint.short(daemonKey)
        let r = "\(host)%3A\(port)"
        let url = "maverick://pair/v1?k=\(k)&t=\(t)&r=\(r)&n=Mac&f=\(f)"

        // A canned PairingResult — NO real network. The webSocketTask is created
        // but never resumed (the stub connectFn ignores it).
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://\(host):\(port)/pair")!)
        let result = PairingResult(
            transport: NoiseTransport(send: Data(repeating: 1, count: 32),
                                      recv: Data(repeating: 2, count: 32)),
            daemonStaticKey: daemonKey,
            safetyNumber: Fingerprint.safetyNumber(daemonKey),
            deviceId: Fingerprint.deviceId(Data(repeating: 9, count: 32)),
            webSocketTask: task
        )
        return Fixture(url: url, daemonStaticKey: daemonKey, host: host, result: result)
    }

    private func makeKeychain() -> KeychainStore {
        let store = KeychainStore(service: "test.maverick.pairctl.\(UUID().uuidString)")
        try? store.deleteAll()
        return store
    }

    // MARK: - Parse failure

    func testParseFailureGoesToFailed() async {
        let keychain = makeKeychain()
        defer { try? keychain.deleteAll() }

        var pairCalled = false
        let controller = PairingController(
            pairFn: { _, _ in pairCalled = true; throw NoiseError.decryptFailed },
            keychain: keychain,
            connectFn: { _ in }
        )

        await controller.handleScanned("https://example.com/not-a-pairing-code")

        guard case let .failed(msg) = controller.state else {
            return XCTFail("expected .failed, got \(controller.state)")
        }
        XCTAssertFalse(pairCalled, "pair should not run when parsing fails")
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - Happy path

    func testHappyPathReachesConfirmWithExpectedSafetyNumber() async {
        let fx = makeFixture()
        let keychain = makeKeychain()
        defer { try? keychain.deleteAll() }

        let controller = PairingController(
            pairFn: { payload, _ in
                // The parsed payload must carry the daemon key from the URL.
                XCTAssertEqual(payload.staticKey, fx.daemonStaticKey)
                return fx.result
            },
            keychain: keychain,
            connectFn: { _ in }
        )

        await controller.handleScanned(fx.url)

        guard case let .confirm(safetyNumber, _) = controller.state else {
            return XCTFail("expected .confirm, got \(controller.state)")
        }
        XCTAssertEqual(safetyNumber, Fingerprint.safetyNumber(fx.daemonStaticKey))
    }

    func testHandshakingStateIsObservableMidFlight() async {
        let fx = makeFixture()
        let keychain = makeKeychain()
        defer { try? keychain.deleteAll() }

        // Gate the stub so we can observe `.handshaking` before it returns.
        let gate = AsyncGate()
        let controller = PairingController(
            pairFn: { _, _ in
                await gate.wait()
                return fx.result
            },
            keychain: keychain,
            connectFn: { _ in }
        )

        let task = Task { await controller.handleScanned(fx.url) }
        // Spin until the controller enters .handshaking (parse + identity load done).
        for _ in 0..<200 {
            if controller.state == .handshaking { break }
            await Task.yield()
        }
        XCTAssertEqual(controller.state, .handshaking)
        gate.open()
        await task.value
        guard case .confirm = controller.state else {
            return XCTFail("expected .confirm after gate, got \(controller.state)")
        }
    }

    func testConfirmPinsAndConnects() async {
        let fx = makeFixture()
        let keychain = makeKeychain()
        defer { try? keychain.deleteAll() }

        var connected: PairingResult?
        let controller = PairingController(
            pairFn: { _, _ in fx.result },
            keychain: keychain,
            connectFn: { connected = $0 }
        )

        await controller.handleScanned(fx.url)
        controller.confirm()

        XCTAssertEqual(controller.state, .connected)
        XCTAssertNotNil(connected, "connectFn must be invoked on confirm")
        XCTAssertEqual(connected?.daemonStaticKey, fx.daemonStaticKey)
        // The daemon key must now be pinned for the host.
        XCTAssertEqual(try keychain.pinnedKey(host: fx.host), fx.daemonStaticKey)
    }

    // MARK: - Cancel / reset from confirm

    // cancel() must abandon the confirm step (and, in production, cancel the live
    // handshake socket so it doesn't leak). With a stub task we can't assert the
    // socket cancellation directly, but we assert the state transition and that
    // connectFn was never invoked.
    func testCancelFromConfirmReturnsToIdle() async {
        let fx = makeFixture()
        let keychain = makeKeychain()
        defer { try? keychain.deleteAll() }

        var connected = false
        let controller = PairingController(
            pairFn: { _, _ in fx.result },
            keychain: keychain,
            connectFn: { _ in connected = true }
        )

        await controller.handleScanned(fx.url)
        guard case .confirm = controller.state else {
            return XCTFail("expected .confirm before cancel, got \(controller.state)")
        }

        controller.cancel()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(connected, "cancel must not hand the socket to the connection manager")
    }

    func testResetFromConfirmReturnsToIdle() async {
        let fx = makeFixture()
        let keychain = makeKeychain()
        defer { try? keychain.deleteAll() }

        let controller = PairingController(
            pairFn: { _, _ in fx.result },
            keychain: keychain,
            connectFn: { _ in }
        )

        await controller.handleScanned(fx.url)
        guard case .confirm = controller.state else {
            return XCTFail("expected .confirm before reset, got \(controller.state)")
        }

        controller.reset()

        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: - TOFU mismatch

    func testTofuMismatchGoesToFailed() async {
        let fx = makeFixture()
        let keychain = makeKeychain()
        defer { try? keychain.deleteAll() }

        // Pre-pin a DIFFERENT key for the same host so confirm() sees a mismatch.
        let otherKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        XCTAssertEqual(try keychain.pin(host: fx.host, key: otherKey), .firstUse)

        var connected = false
        let controller = PairingController(
            pairFn: { _, _ in fx.result },
            keychain: keychain,
            connectFn: { _ in connected = true }
        )

        await controller.handleScanned(fx.url)
        controller.confirm()

        guard case let .failed(msg) = controller.state else {
            return XCTFail("expected .failed on mismatch, got \(controller.state)")
        }
        XCTAssertTrue(msg.contains("MITM"), "mismatch message should flag MITM, got: \(msg)")
        XCTAssertFalse(connected, "must not connect when the key changed")
    }
}

/// Minimal async gate: `wait()` suspends until `open()` is called.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false

    func open() {
        lock.lock(); opened = true; lock.unlock()
    }

    func wait() async {
        while true {
            lock.lock(); let o = opened; lock.unlock()
            if o { return }
            await Task.yield()
        }
    }
}
