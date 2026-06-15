import Foundation
import CryptoKit

public struct HandshakeStateInitiator {
    private var sym = SymmetricState()
    private let s: Curve25519.KeyAgreement.PrivateKey
    private var e: Curve25519.KeyAgreement.PrivateKey?
    private var rs: Data?   // responder static, learned in msg2
    private var re: Data?   // responder ephemeral, learned in msg2 (used by `se` in msg3)
    private var handshakeComplete = false

    public init(staticKey: Curve25519.KeyAgreement.PrivateKey) { self.s = staticKey }

    /// Responder static learned during msg2 (caller asserts == QR `k`).
    public var responderStatic: Data? { rs }

    private static func dh(_ priv: Curve25519.KeyAgreement.PrivateKey, _ pubRaw: Data) throws -> Data {
        let pub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubRaw)
        let ss = try priv.sharedSecretFromKeyAgreement(with: pub)
        return ss.withUnsafeBytes { Data($0) }   // 32 raw bytes
    }

    /// `-> e`, payload = token (unkeyed → plaintext on the wire).
    public mutating func writeMsg1(token: Data) throws -> Data {
        let e = Curve25519.KeyAgreement.PrivateKey()
        self.e = e
        let ePub = e.publicKey.rawRepresentation
        sym.mixHash(ePub)
        let payload = try sym.encryptAndHash(token)  // unkeyed -> passthrough
        return ePub + payload
    }

    /// `<- e, ee, s, es`. Learns + returns responder static `rs`.
    public mutating func readMsg2(_ msg: Data) throws -> Data {
        guard let e else { throw NoiseError.handshakeOutOfOrder }
        guard msg.count >= 32 + 48 + 16 else { throw NoiseError.messageTooShort }
        let reBytes = Data(msg.prefix(32))
        sym.mixHash(reBytes)
        self.re = reBytes                                                // capture responder ephemeral
        try sym.mixKey(HandshakeStateInitiator.dh(e, reBytes))           // ee
        let encStatic = msg.dropFirst(32).prefix(48)
        let rsData = try sym.decryptAndHash(Data(encStatic))             // s
        try sym.mixKey(HandshakeStateInitiator.dh(e, rsData))            // es
        let encPayload = msg.dropFirst(32 + 48)
        _ = try sym.decryptAndHash(Data(encPayload))                     // empty payload
        rs = rsData
        return rsData
    }

    /// `-> s, se`. Empty payload.
    public mutating func writeMsg3() throws -> Data {
        guard let reBytes = re else { throw NoiseError.handshakeOutOfOrder }
        let sPub = s.publicKey.rawRepresentation
        let encStatic = try sym.encryptAndHash(sPub)                     // s
        // XX `se`: initiator-static × RESPONDER-ephemeral (re from msg2), NOT rs.
        try sym.mixKey(HandshakeStateInitiator.dh(s, reBytes))           // se
        let encPayload = try sym.encryptAndHash(Data())
        handshakeComplete = true
        return encStatic + encPayload
    }

    /// Per Noise spec §5.2, the initiator's transport keys are: send=k1, recv=k2.
    public func split() throws -> (send: Data, recv: Data) {
        guard handshakeComplete else { throw NoiseError.handshakeOutOfOrder }
        let (k1, k2) = sym.split()
        return (k1, k2)   // initiator: send=k1, recv=k2
    }
}
