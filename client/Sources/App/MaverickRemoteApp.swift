// client/Sources/App/MaverickRemoteApp.swift
import SwiftUI
import UIKit

@main
struct MaverickRemoteApp: App {
    @State private var connection = ConnectionManager()
    @State private var store = SessionStore()
    @State private var connectionHistory = ConnectionHistory()
    @State private var sessionHistory = SessionHistory()
    @State private var taskLauncher = TaskLauncher()
    @State private var settings = AppSettings()
    @State private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connection)
                .environment(store)
                .environment(connectionHistory)
                .environment(sessionHistory)
                .environment(taskLauncher)
                .environment(settings)
                .environment(themeStore)
                .task {
                    // Wire output routing after @State is initialized by SwiftUI.
                    // Fan out each server message to live store, session history,
                    // and the task launcher (which sends initial agent commands).
                    let connRef = connection
                    connection.onMessage = { [weak store, weak sessionHistory, weak taskLauncher] msg in
                        store?.handle(msg)
                        sessionHistory?.handle(msg)
                        taskLauncher?.handle(msg, connection: connRef)
                    }
                    // Auto-connect on cold launch if a saved host exists.
                    autoConnectIfPossible()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    autoConnectIfPossible()
                }
        }
    }

    private func autoConnectIfPossible() {
        let host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
        let port = UserDefaults.standard.integer(forKey: "lastPort")
        if connection.state == .disconnected, !host.isEmpty {
            connection.connect(host: host, port: port == 0 ? 8765 : port)
        }
    }
}
