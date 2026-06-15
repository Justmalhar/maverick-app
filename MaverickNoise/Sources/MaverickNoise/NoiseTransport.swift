import Foundation

public struct NoiseTransport {
    private var send: CipherState
    private var recv: CipherState
    public init(send: Data, recv: Data) {
        self.send = CipherState(key: send)
        self.recv = CipherState(key: recv)
    }
    /// Encrypt one app frame -> base64url text (AAD empty).
    public mutating func encryptFrame(_ plaintext: Data) throws -> String {
        Base64URL.encode(try send.encrypt(plaintext: plaintext, aad: Data()))
    }
    public mutating func decryptFrame(_ b64: String) throws -> Data {
        try recv.decrypt(ciphertext: try Base64URL.decode(b64), aad: Data())
    }
}
