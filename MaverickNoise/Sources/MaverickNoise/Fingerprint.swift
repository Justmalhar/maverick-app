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
            let v = UInt32(bigEndian: d.subdata(in: (i*4)..<(i*4+4)).withUnsafeBytes { $0.load(as: UInt32.self) })
            return String(format: "%06d", v % 1_000_000)
        }.joined(separator: " ")
    }
    public static func deviceId(_ staticKey: Data) -> String {
        Base64URL.encode(Data(SHA256.hash(data: staticKey)))
    }
}
