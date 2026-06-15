// client/Sources/Features/Pairing/PairingController.swift
import Foundation
import CryptoKit
import MaverickNoise

/// Drives the QR-pairing flow as an explicit state machine:
///
///   idle → scanning → handshaking → confirm(safetyNumber:pending:) → connected
///                                          │
///                                          └─(parse/handshake/pin error)→ failed
///
/// **Dependency injection for testability.** The two side-effecting collaborators
/// are injected so a unit test can drive the machine with NO real network and an
/// isolated, unique-service Keychain:
///   - `pairFn`: the `PairingClient.pair`-shaped closure (stubbed in tests to
///     return a canned `PairingResult`).
///   - `keychain`: a `KeychainStore` (tests pass one on a unique service).
///   - `connectFn`: invoked on confirm to adopt the paired socket (tests pass a
///     no-op / recording closure so they never touch `ConnectionManager`).
@Observable
@MainActor
final class PairingController {
    enum State: Equatable {
        case idle
        case scanning
        case handshaking
        case confirm(safetyNumber: String, pending: PairingResult)
        case connected
        case failed(String)

        // PairingResult is not Equatable (it carries a live socket/transport),
        // so compare the user-visible discriminant + safety number only.
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.scanning, .scanning),
                 (.handshaking, .handshaking), (.connected, .connected):
                return true
            case let (.confirm(a, _), .confirm(b, _)):
                return a == b
            case let (.failed(a), .failed(b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var state: State = .idle

    // MARK: - Injected collaborators

    typealias PairFn = (QRPayload, Curve25519.KeyAgreement.PrivateKey) async throws -> PairingResult
    typealias ConnectFn = (PairingResult) -> Void

    private let pairFn: PairFn
    private let keychain: KeychainStore
    private let connectFn: ConnectFn

    /// Production initializer wiring the real `PairingClient`, `KeychainStore`,
    /// and `ConnectionManager.connectPaired`.
    convenience init(connection: ConnectionManager,
                     keychain: KeychainStore = KeychainStore()) {
        let client = PairingClient()
        self.init(
            pairFn: { try await client.pair(payload: $0, clientStatic: $1) },
            keychain: keychain,
            connectFn: { connection.connectPaired($0) }
        )
    }

    /// Designated initializer — all collaborators injectable for tests.
    init(pairFn: @escaping PairFn,
         keychain: KeychainStore,
         connectFn: @escaping ConnectFn) {
        self.pairFn = pairFn
        self.keychain = keychain
        self.connectFn = connectFn
    }

    // MARK: - Flow

    /// Move to the scanning state (presenting the camera / manual-entry sheet).
    func beginScanning() {
        state = .scanning
    }

    /// Reset to idle (e.g. on cancel from the confirmation step / try-again).
    func reset() {
        // If we're abandoning a confirm step WITHOUT handing the socket to the
        // ConnectionManager, the still-open handshake socket would otherwise leak.
        // (The .confirm → .connected handoff path in confirm() must NOT cancel.)
        if case let .confirm(_, result) = state {
            result.webSocketTask.cancel(with: .normalClosure, reason: nil)
        }
        state = .idle
    }

    /// Handle a decoded/pasted QR string from either the camera or manual entry.
    /// Parses → loads the client identity → runs the Noise handshake → presents
    /// the safety number for out-of-band confirmation.
    func handleScanned(_ raw: String) async {
        let payload: QRPayload
        do {
            payload = try QRPayload.parse(raw)
        } catch {
            state = .failed(Self.describeParseError(error))
            return
        }

        state = .handshaking

        let clientStatic: Curve25519.KeyAgreement.PrivateKey
        do {
            clientStatic = try keychain.loadOrCreateStaticIdentity()
        } catch {
            state = .failed("could not load device identity: \(error.localizedDescription)")
            return
        }

        do {
            let result = try await pairFn(payload, clientStatic)
            // Stash the host on the result via the payload for the pin step.
            state = .confirm(safetyNumber: result.safetyNumber, pending: result)
            pendingHost = payload.host
        } catch {
            state = .failed(Self.describeHandshakeError(error))
        }
    }

    /// The host whose key we'll TOFU-pin on confirm (captured during handshaking).
    private var pendingHost: String = ""

    /// User confirmed the safety number out-of-band. TOFU-pin the daemon key
    /// (rejecting a changed key as a possible MITM) and adopt the encrypted
    /// socket as the live session transport.
    func confirm() {
        guard case let .confirm(_, result) = state else { return }

        do {
            let outcome = try keychain.pin(host: pendingHost, key: result.daemonStaticKey)
            if outcome == .mismatch {
                state = .failed("device key changed — possible MITM")
                return
            }
        } catch {
            state = .failed("could not pin device key: \(error.localizedDescription)")
            return
        }

        connectFn(result)
        state = .connected
    }

    /// User rejected the safety number — abandon the pairing.
    func cancel() {
        // Tear down the still-open handshake socket before leaving .confirm.
        // (Only the .confirm → .connected path in confirm() hands the socket off;
        // every other exit from .confirm must cancel it to avoid a WS leak.)
        if case let .confirm(_, result) = state {
            result.webSocketTask.cancel(with: .normalClosure, reason: nil)
        }
        state = .idle
    }

    // MARK: - Error messaging

    private static func describeParseError(_ error: Error) -> String {
        switch error {
        case QRPayloadError.wrongScheme:
            return "not a Maverick pairing code"
        case QRPayloadError.wrongPath:
            return "unsupported pairing code version"
        case QRPayloadError.missingRequiredField(let f):
            return "pairing code is missing field \"\(f)\""
        case QRPayloadError.badBase64URL(let f):
            return "pairing code field \"\(f)\" is malformed"
        case QRPayloadError.wrongKeyLength(let f, let exp, let act):
            return "pairing code field \"\(f)\" has wrong length (\(act), expected \(exp))"
        case QRPayloadError.fingerprintMismatch:
            return "pairing code fingerprint does not match its key"
        default:
            return "invalid pairing code"
        }
    }

    private static func describeHandshakeError(_ error: Error) -> String {
        switch error {
        case NoiseError.responderKeyMismatch:
            return "device key did not match the pairing code — possible MITM"
        case let PairingClientError.closed(code, reason):
            if code == 4401 {
                return "pairing rejected by the Mac (expired token or key mismatch)"
            }
            return "connection closed (\(code))\(reason.map { ": \($0)" } ?? "")"
        case PairingClientError.unexpectedFrame:
            return "unexpected response from the Mac"
        case let PairingClientError.transportFailure(msg):
            return "could not reach the Mac: \(msg)"
        case is NoiseError:
            return "secure handshake failed"
        default:
            return "pairing failed: \(error.localizedDescription)"
        }
    }
}
