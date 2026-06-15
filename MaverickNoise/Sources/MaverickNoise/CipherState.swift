import Foundation
import CryptoKit

struct CipherState {
    private let key: SymmetricKey
    private var counter: UInt64 = 0

    init(key: Data) { self.key = SymmetricKey(data: key) }

    /// 12-byte nonce: 4 zero bytes followed by the 8-byte little-endian counter.
    static func nonce(counter: UInt64) -> Data {
        var d = Data([0, 0, 0, 0])
        var le = counter.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
        return d
    }

    mutating func encrypt(plaintext: Data, aad: Data) throws -> Data {
        guard counter != UInt64.max else { throw NoiseError.nonceExhausted }
        let n = try ChaChaPoly.Nonce(data: CipherState.nonce(counter: counter))
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: n, authenticating: aad)
        counter += 1
        return box.ciphertext + box.tag   // wire = ciphertext || 16-byte tag
    }

    mutating func decrypt(ciphertext: Data, aad: Data) throws -> Data {
        guard ciphertext.count >= 16 else { throw NoiseError.messageTooShort }
        guard counter != UInt64.max else { throw NoiseError.nonceExhausted }
        let n = try ChaChaPoly.Nonce(data: CipherState.nonce(counter: counter))
        let ct = ciphertext.prefix(ciphertext.count - 16)
        let tag = ciphertext.suffix(16)
        let box = try ChaChaPoly.SealedBox(nonce: n, ciphertext: ct, tag: tag)
        do {
            let pt = try ChaChaPoly.open(box, using: key, authenticating: aad)
            counter += 1
            return pt
        } catch { throw NoiseError.decryptFailed }
    }
}
