import XCTest
import CryptoKit
@testable import MaverickNoise

/// Phase E: live interop proof that the `MaverickNoise` XX **initiator** is
/// byte-compatible with the maverick daemon's `snow`-based XX **responder**.
///
/// Phase A's KATs only cover the deterministic primitives (HKDF, cipher,
/// fingerprints). This test exercises the FULL transcript against the real
/// `snow` crate — the exact same crate + cipher-suite features the daemon's
/// `NoiseResponder` uses — by spawning a tiny stdio responder harness and
/// driving the complete `XX` handshake plus an encrypted transport round-trip.
///
/// ## Why stdio (not a socket / the real daemon)
///
/// The daemon's `accept_loop` routes loopback peers to the PLAINTEXT path and
/// only non-loopback peers to the Noise `/pair` path, and `BindPolicy` won't
/// bind LAN until a device is already paired. So a fresh `maverick-hostd` on
/// `127.0.0.1` never exercises Noise. The stdio harness cleanly isolates and
/// proves the crypto interop (the real risk) with no sockets or bind policy.
///
/// ## Running
///
/// 1. Build the harness:
///      `cargo build --release \
///         --manifest-path MaverickNoise/Tests/Fixtures/noise-harness/Cargo.toml`
/// 2. Point the test at the binary and run:
///      `NOISE_HARNESS=MaverickNoise/Tests/Fixtures/noise-harness/target/release/noise-harness \
///         swift test --package-path MaverickNoise`
///
/// When `NOISE_HARNESS` is unset (or the binary is missing) the test
/// `XCTSkip`s, so the normal `swift test` stays green without the harness.
final class InteropTests: XCTestCase {

    private static let listSessions = Data(#"{"type":"list_sessions"}"#.utf8)
    private static let sessionList = Data(#"{"type":"session_list","sessions":[]}"#.utf8)

    func testFullHandshakeAndTransportAgainstSnowResponder() throws {
        let env = ProcessInfo.processInfo.environment
        guard let harnessPath = env["NOISE_HARNESS"], !harnessPath.isEmpty else {
            throw XCTSkip("set NOISE_HARNESS to the built noise-harness binary to run the live snow interop proof")
        }
        guard FileManager.default.isExecutableFile(atPath: harnessPath) else {
            throw XCTSkip("NOISE_HARNESS=\(harnessPath) is not an executable file (build the harness first)")
        }

        // --- spawn the snow responder harness over stdio ---
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: harnessPath)
        let toHarness = Pipe()    // our stdout -> harness stdin
        let fromHarness = Pipe()  // harness stdout -> our stdin
        let errPipe = Pipe()
        proc.standardInput = toHarness
        proc.standardOutput = fromHarness
        proc.standardError = errPipe

        let outReader = LineReader(handle: fromHarness.fileHandleForReading)
        try proc.run()

        defer {
            if proc.isRunning { proc.terminate() }
        }

        func send(_ line: String) throws {
            try toHarness.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        }
        func harnessStderr() -> String {
            let d = errPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: d, encoding: .utf8) ?? ""
        }

        // --- read the "QR" line: responder static pub + token (base64url) ---
        guard let qrLine = outReader.next() else {
            XCTFail("harness produced no QR line. stderr: \(harnessStderr())")
            return
        }
        let qrParts = qrLine.split(separator: " ").map(String.init)
        XCTAssertEqual(qrParts.count, 2, "QR line should be '<staticPub> <token>', got: \(qrLine)")
        let harnessStaticKey = try Base64URL.decode(qrParts[0])
        let token = try Base64URL.decode(qrParts[1])
        XCTAssertEqual(harnessStaticKey.count, 32, "responder static key must be 32 bytes")
        XCTAssertEqual(token.count, 16, "pairing token must be 16 bytes")

        // --- run the MaverickNoise initiator against it ---
        let clientStatic = Curve25519.KeyAgreement.PrivateKey()
        var initiator = HandshakeStateInitiator(staticKey: clientStatic)

        // msg1: -> e, payload = token
        let msg1 = try initiator.writeMsg1(token: token)
        try send(Base64URL.encode(msg1))

        // msg2: <- e, ee, s, es  (learns responder static)
        guard let msg2Line = outReader.next() else {
            XCTFail("no msg2 from harness. stderr: \(harnessStderr())")
            return
        }
        let responderStatic = try initiator.readMsg2(try Base64URL.decode(msg2Line))

        // THE crypto interop assertion: the initiator learned the SAME static
        // key the snow responder presented (== the "QR k").
        XCTAssertEqual(
            responderStatic, harnessStaticKey,
            "initiator-learned responder static must equal the harness's snow static key"
        )
        XCTAssertEqual(initiator.responderStatic, harnessStaticKey)

        // msg3: -> s, se
        let msg3 = try initiator.writeMsg3()
        try send(Base64URL.encode(msg3))

        // --- transport: initiator send=k1, recv=k2 ---
        let (send: sendKey, recv: recvKey) = try initiator.split()
        var transport = NoiseTransport(send: sendKey, recv: recvKey)

        // encrypt an app frame and ship it to the snow responder
        let appFrame = try transport.encryptFrame(InteropTests.listSessions)
        try send(appFrame)

        // read the snow responder's encrypted reply and decrypt it
        guard let replyLine = outReader.next() else {
            XCTFail("no transport reply from harness. stderr: \(harnessStderr())")
            return
        }
        let reply = try transport.decryptFrame(replyLine)
        XCTAssertEqual(
            reply, InteropTests.sessionList,
            "decrypted snow transport reply must equal the session_list JSON"
        )

        // clean shutdown — harness exits 0 after the round-trip
        toHarness.fileHandleForWriting.closeFile()
        proc.waitUntilExit()
        XCTAssertEqual(
            proc.terminationStatus, 0,
            "harness should exit 0 after a successful round-trip. stderr: \(harnessStderr())"
        )
    }
}

/// Minimal blocking line reader over a `FileHandle`, reading byte-by-byte up to
/// a newline. Frames are small (handshake messages + one JSON), so this is
/// simple and avoids buffering past a frame boundary.
private final class LineReader {
    private let handle: FileHandle
    init(handle: FileHandle) { self.handle = handle }

    func next() -> String? {
        var buf = Data()
        while true {
            let chunk = handle.readData(ofLength: 1)
            if chunk.isEmpty {
                // EOF: return whatever we have if non-empty, else nil.
                if buf.isEmpty { return nil }
                return String(data: buf, encoding: .utf8)
            }
            if chunk[chunk.startIndex] == 0x0A { // '\n'
                return String(data: buf, encoding: .utf8)
            }
            buf.append(chunk)
        }
    }
}
