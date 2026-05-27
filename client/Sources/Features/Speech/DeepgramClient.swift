// client/Sources/Features/Speech/DeepgramClient.swift
import Foundation

struct DeepgramClient {
    let apiKey: String

    enum DGError: Error, LocalizedError {
        case missingKey
        case http(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Set your Deepgram API key in Settings."
            case .http(let code, let body): return "Deepgram HTTP \(code): \(body)"
            case .decode(let msg): return "Deepgram decode: \(msg)"
            }
        }
    }

    /// Uploads an audio file (m4a/AAC) to Deepgram and returns the transcript.
    func transcribe(audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw DGError.missingKey }

        // Use nova-3 (fast, accurate) with smart_format for nicer punctuation/casing.
        // The "filler_words=false" param strips ums/uhs which is nice for terminal input.
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "filler_words", value: "false"),
        ]

        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let (data, response) = try await URLSession.shared.upload(for: req, from: audioData)

        guard let http = response as? HTTPURLResponse else {
            throw DGError.decode("no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DGError.http(http.statusCode, String(body.prefix(200)))
        }

        struct Resp: Decodable {
            struct Results: Decodable {
                struct Channel: Decodable {
                    struct Alternative: Decodable { let transcript: String }
                    let alternatives: [Alternative]
                }
                let channels: [Channel]
            }
            let results: Results
        }
        do {
            let parsed = try JSONDecoder().decode(Resp.self, from: data)
            return parsed.results.channels.first?.alternatives.first?.transcript ?? ""
        } catch {
            throw DGError.decode(error.localizedDescription)
        }
    }
}
