import Foundation
import CryptoKit

enum HKDFNoise {
    /// Noise HKDF: PRK = HMAC(salt=chainingKey, msg=ikm); then
    /// out_i = HMAC(PRK, out_{i-1} || byte(i)), i = 1..count. Each out_i is 32 bytes.
    static func derive(chainingKey: Data, ikm: Data, count: Int) -> [Data] {
        guard count > 0 else { return [] }
        let prkKey = SymmetricKey(data: chainingKey)
        let prk = HMAC<SHA256>.authenticationCode(for: ikm, using: prkKey)
        let prkKey2 = SymmetricKey(data: Data(prk))
        var outputs: [Data] = []
        var prev = Data()
        for i in 1...count {
            var msg = prev
            msg.append(UInt8(i))
            let mac = HMAC<SHA256>.authenticationCode(for: msg, using: prkKey2)
            let out = Data(mac)
            outputs.append(out)
            prev = out
        }
        return outputs
    }
}
