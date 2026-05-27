// client/Sources/App/MaverickRemoteApp.swift
import SwiftUI
import UIKit

@main
struct MaverickRemoteApp: App {
    @State private var connection = ConnectionManager()
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connection)
                .environment(store)
                .task {
                    // Wire output routing after @State is initialized by SwiftUI
                    connection.onMessage = { [weak store] msg in
                        store?.handle(msg)
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
