import Foundation
import CryptoKit

public enum Fingerprint {
    public static func short(_ staticKey: Data) -> String {
        let d = Data(SHA256.hash(data: staticKey)).prefix(4)
        return d.map { String(format: "%02X", $0) }.joined()
    }
    public static func safetyNumber(_ staticKey: Data) -> String {
        let d = Data(SHA256.hash(data: staticKey))
        return (0..<5).map { i -> String in
            let base = i * 4
            let v: UInt32 = (UInt32(d[base]) << 24)
                          | (UInt32(d[base + 1]) << 16)
                          | (UInt32(d[base + 2]) << 8)
                          |  UInt32(d[base + 3])
            return String(format: "%06d", v % 1_000_000)
        }.joined(separator: " ")
    }
    public static func deviceId(_ staticKey: Data) -> String {
        Base64URL.encode(Data(SHA256.hash(data: staticKey)))
    }
}
