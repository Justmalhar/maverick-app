import Foundation

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        let s = data.base64EncodedString()
        return s.replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
    }
    public static func decode(_ s: String) throws -> Data {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        let rem = t.count % 4
        if rem != 0 { t += String(repeating: "=", count: 4 - rem) }
        guard let d = Data(base64Encoded: t) else { throw NoiseError.badBase64URL }
        return d
    }
}
