import Foundation
import MaverickNoise

/// Parsed `maverick://pair/v1?k=&e=&t=&r=&n=&f=` QR payload.
///
/// The daemon (`maverick-hostd`) is the wire authority for this format; see
/// `maverick/src-tauri/core/src/remote/pairing.rs::qr_payload`. `k`/`e`/`t` are
/// base64url (URL-safe, no padding); `r`/`n` are percent-encoded.
public struct QRPayload: Equatable {
    /// Daemon static public key (`k`), exactly 32 bytes. Asserted against the
    /// Noise responder static during the handshake.
    public let staticKey: Data
    /// Advertised ephemeral public key hint (`e`), exactly 32 bytes.
    public let ephemeralHint: Data
    /// Single-use pairing token (`t`), exactly 16 bytes. Echoed as the msg1 payload.
    public let token: Data
    /// Rendezvous host, resolved from `r` (else `pair.local`).
    public let host: String
    /// Rendezvous port, resolved from `r` (else `8765`).
    public let port: Int
    /// Optional human-readable device name (`n`).
    public let name: String?
    /// Optional short fingerprint (`f`); when present it is verified against `k`.
    public let fingerprint: String?

    public init(
        staticKey: Data,
        ephemeralHint: Data,
        token: Data,
        host: String,
        port: Int,
        name: String?,
        fingerprint: String?
    ) {
        self.staticKey = staticKey
        self.ephemeralHint = ephemeralHint
        self.token = token
        self.host = host
        self.port = port
        self.name = name
        self.fingerprint = fingerprint
    }
}

public enum QRPayloadError: Error, Equatable {
    case wrongScheme
    case wrongPath
    case missingRequiredField(String)
    case badBase64URL(String)
    case wrongKeyLength(field: String, expected: Int, actual: Int)
    case fingerprintMismatch(expected: String, actual: String)
    case malformed
}

extension QRPayload {
    /// Default rendezvous when `r` is absent or empty.
    static let defaultHost = "pair.local"
    static let defaultPort = 8765

    /// Parse a `maverick://pair/v1?…` string.
    ///
    /// Rules (verified against the daemon QR spec):
    /// - Scheme must be `maverick://`; path must be `pair/v1`.
    /// - `k` and `t` are required; `k`/`e` must base64url-decode to 32 bytes;
    ///   `t` to 16 bytes.
    /// - `r`/`n` are percent-decoded. Rendezvous `r` resolution: strip
    ///   `scheme://` and any `/path`, split host:port on the LAST `:` (guarding
    ///   IPv6 `]`), port 1…65535 else default; host kept verbatim. Fallback
    ///   when `r` absent/empty: `pair.local:8765`.
    /// - When `f` is present, `Fingerprint.short(k)` must match it (uppercase).
    public static func parse(_ string: String) throws -> QRPayload {
        // Manual prefix check rather than URLComponents, which would mangle the
        // host-less custom-scheme path and percent semantics.
        let schemePrefix = "maverick://"
        guard string.hasPrefix(schemePrefix) else { throw QRPayloadError.wrongScheme }
        let afterScheme = String(string.dropFirst(schemePrefix.count))

        // Split path from query on the first '?'.
        let path: Substring
        let query: Substring
        if let qIndex = afterScheme.firstIndex(of: "?") {
            path = afterScheme[afterScheme.startIndex..<qIndex]
            query = afterScheme[afterScheme.index(after: qIndex)...]
        } else {
            path = Substring(afterScheme)
            query = ""
        }
        guard path == "pair/v1" else { throw QRPayloadError.wrongPath }

        let params = parseQuery(String(query))

        guard let kRaw = params["k"], !kRaw.isEmpty else {
            throw QRPayloadError.missingRequiredField("k")
        }
        guard let tRaw = params["t"], !tRaw.isEmpty else {
            throw QRPayloadError.missingRequiredField("t")
        }

        let staticKey = try decodeKey(kRaw, field: "k", expected: 32)
        let ephemeralHint: Data
        if let eRaw = params["e"], !eRaw.isEmpty {
            ephemeralHint = try decodeKey(eRaw, field: "e", expected: 32)
        } else {
            ephemeralHint = Data()
        }
        let token = try decodeKey(tRaw, field: "t", expected: 16)

        let name = params["n"].flatMap { percentDecode($0) }
        let fingerprint = params["f"].flatMap { $0.isEmpty ? nil : $0 }

        let (host, port) = resolveRendezvous(params["r"])

        if let f = fingerprint {
            let actual = Fingerprint.short(staticKey)
            guard actual.uppercased() == f.uppercased() else {
                throw QRPayloadError.fingerprintMismatch(expected: f, actual: actual)
            }
        }

        return QRPayload(
            staticKey: staticKey,
            ephemeralHint: ephemeralHint,
            token: token,
            host: host,
            port: port,
            name: name,
            fingerprint: fingerprint
        )
    }

    // MARK: - Query parsing (first occurrence wins)

    private static func parseQuery(_ query: String) -> [String: String] {
        var out: [String: String] = [:]
        guard !query.isEmpty else { return out }
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(kv[0])
            if key.isEmpty { continue }
            let value = kv.count > 1 ? String(kv[1]) : ""
            // First occurrence wins.
            if out[key] == nil { out[key] = value }
        }
        return out
    }

    private static func decodeKey(_ raw: String, field: String, expected: Int) throws -> Data {
        let data: Data
        do {
            data = try Base64URL.decode(raw)
        } catch {
            throw QRPayloadError.badBase64URL(field)
        }
        guard data.count == expected else {
            throw QRPayloadError.wrongKeyLength(field: field, expected: expected, actual: data.count)
        }
        return data
    }

    // MARK: - Rendezvous resolution

    /// Resolve a `host:port` from the (possibly percent-encoded) `r` field.
    static func resolveRendezvous(_ rRaw: String?) -> (host: String, port: Int) {
        guard let rRaw, !rRaw.isEmpty, var r = percentDecode(rRaw), !r.isEmpty else {
            return (defaultHost, defaultPort)
        }

        // Strip a leading `scheme://` if present (e.g. ws://host:port/path).
        if let schemeRange = r.range(of: "://") {
            r = String(r[schemeRange.upperBound...])
        }

        // Strip a trailing `/path` (everything from the first '/').
        if let slash = r.firstIndex(of: "/") {
            r = String(r[r.startIndex..<slash])
        }

        if r.isEmpty { return (defaultHost, defaultPort) }

        // Split host:port on the LAST ':' but only if it is outside any IPv6
        // bracket (i.e. after a closing ']' or when there is no ']').
        let lastColon = r.lastIndex(of: ":")
        let lastBracket = r.lastIndex(of: "]")

        let colonIsPortDelimiter: Bool
        if let lastColon {
            if let lastBracket {
                // Port colon must come after the closing bracket: `[::1]:8765`.
                colonIsPortDelimiter = lastColon > lastBracket
            } else {
                colonIsPortDelimiter = true
            }
        } else {
            colonIsPortDelimiter = false
        }

        if colonIsPortDelimiter, let lastColon {
            let host = String(r[r.startIndex..<lastColon])
            let portStr = String(r[r.index(after: lastColon)...])
            if let p = Int(portStr), (1...65535).contains(p), !host.isEmpty {
                return (host, p)
            }
            // Invalid/out-of-range port → keep host, default port.
            if !host.isEmpty {
                return (host, defaultPort)
            }
            return (defaultHost, defaultPort)
        }

        // No port delimiter → bare host (incl. `[::1]`), default port.
        return (r, defaultPort)
    }

    // MARK: - Percent decoding

    /// Percent-decode the `r`/`n` fields. Mirrors the daemon's RFC-3986 encoder
    /// (`decodeURIComponent`-compatible). Returns nil only on malformed input.
    static func percentDecode(_ s: String) -> String? {
        return s.removingPercentEncoding
    }
}
