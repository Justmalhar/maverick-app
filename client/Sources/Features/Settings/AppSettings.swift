// client/Sources/Features/Settings/AppSettings.swift
import Foundation
import Observation

@Observable
final class AppSettings {
    private let dgKeyKey = "deepgramAPIKey.v1"

    var deepgramAPIKey: String {
        didSet { UserDefaults.standard.set(deepgramAPIKey, forKey: dgKeyKey) }
    }

    init() {
        self.deepgramAPIKey = UserDefaults.standard.string(forKey: dgKeyKey) ?? ""
    }

    var hasDeepgramKey: Bool { !deepgramAPIKey.isEmpty }
}
