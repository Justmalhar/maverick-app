// client/Sources/App/MaverickRemoteApp.swift
import SwiftUI
import UIKit

@main
struct MaverickRemoteApp: App {
    @State private var connection = ConnectionManager()
    @State private var store = SessionStore()
    @State private var connectionHistory = ConnectionHistory()
    @State private var sessionHistory = SessionHistory()
    @State private var settings = AppSettings()
    @State private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connection)
                .environment(store)
                .environment(connectionHistory)
                .environment(sessionHistory)
                .environment(settings)
                .environment(themeStore)
                .task {
                    // Wire output routing after @State is initialized by SwiftUI.
                    // Fan out each server message to both the live store and
                    // the persistent session history.
                    connection.onMessage = { [weak store, weak sessionHistory] msg in
                        store?.handle(msg)
                        sessionHistory?.handle(msg)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    let host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
                    let port = UserDefaults.standard.integer(forKey: "lastPort")
                    if connection.state == .disconnected, !host.isEmpty {
                        connection.connect(host: host, port: port == 0 ? 8765 : port)
                    }
                }
        }
    }
}
