import Foundation
import CryptoKit

struct SymmetricState {
    private(set) var ck: Data
    private(set) var h: Data
    private var cipher: CipherState?   // nil until first mixKey

    static let protocolName = "Noise_XX_25519_ChaChaPoly_SHA256" // 32 ASCII bytes

    init() {
        let name = Data(SymmetricState.protocolName.utf8)
        // name is exactly 32 bytes -> h = name; (if it weren't, h = SHA256(name)).
        h = name.count <= 32 ? name + Data(repeating: 0, count: 32 - name.count)
                             : Data(SHA256.hash(data: name))
        ck = h
        // mixHash(prologue) with empty prologue:
        mixHash(Data())
    }

    var handshakeHash: Data { h }

    mutating func mixHash(_ data: Data) {
        var hasher = SHA256()
        hasher.update(data: h)
        hasher.update(data: data)
        h = Data(hasher.finalize())
    }

    mutating func mixKey(_ ikm: Data) {
        let out = HKDFNoise.derive(chainingKey: ck, ikm: ikm, count: 2)
        ck = out[0]
        cipher = CipherState(key: out[1])
    }

    mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        if cipher != nil {
            let ct = try cipher!.encrypt(plaintext: plaintext, aad: h)
            mixHash(ct)
            return ct
        } else {
            mixHash(plaintext)
            return plaintext
        }
    }

    mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        if cipher != nil {
            let pt = try cipher!.decrypt(ciphertext: ciphertext, aad: h)
            mixHash(ciphertext)
            return pt
        } else {
            mixHash(ciphertext)
            return ciphertext
        }
    }

    /// Final split: two 32-byte keys (initiator: send=first, recv=second).
    func split() -> (Data, Data) {
        let out = HKDFNoise.derive(chainingKey: ck, ikm: Data(), count: 2)
        return (out[0], out[1])
    }
}
