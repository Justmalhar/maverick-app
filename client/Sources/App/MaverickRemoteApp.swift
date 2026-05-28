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
    @State private var attachmentManager = AttachmentManager()
    @State private var directoryBrowser = DirectoryBrowserModel()
    @State private var projectIndex = ProjectIndexModel()
    @State private var gitStatus = GitStatusModel()
    @State private var settings = AppSettings()
    @State private var themeStore = ThemeStore()
    @State private var chatStore = ChatStore()
    @State private var agentSessionStore = AgentSessionStore()

    @State private var showSplash = true
    @State private var isInBackground = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(connection)
                    .environment(store)
                    .environment(connectionHistory)
                    .environment(sessionHistory)
                    .environment(taskLauncher)
                    .environment(attachmentManager)
                    .environment(directoryBrowser)
                    .environment(projectIndex)
                    .environment(gitStatus)
                    .environment(settings)
                    .environment(themeStore)
                    .environment(chatStore)
                    .environment(agentSessionStore)
                    .task {
                        let connRef = connection
                        connection.onMessage = { [weak store, weak sessionHistory, weak taskLauncher, weak attachmentManager, weak directoryBrowser, weak projectIndex, weak gitStatus, weak agentSessionStore] msg in
                            store?.handle(msg)
                            sessionHistory?.handle(msg)
                            taskLauncher?.handle(msg, connection: connRef)
                            attachmentManager?.handle(msg)
                            directoryBrowser?.handle(msg)
                            projectIndex?.handle(msg)
                            gitStatus?.handle(msg)
                            agentSessionStore?.handle(msg)
                        }
                        taskLauncher.onLaunched = { [weak sessionHistory] sid, agent, cwd in
                            sessionHistory?.recordLaunchContext(sessionId: sid, agent: agent, cwd: cwd)
                        }
                        autoConnectIfPossible()
                        // Dismiss launch splash after a short delay.
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(.easeOut(duration: 0.4)) {
                            showSplash = false
                        }
                    }
                    .onChange(of: connection.state) { _, new in
                        // Pre-warm the folder picker cache the moment we're online so
                        // the very first tap on the folder chip is instant.
                        if new == .connected {
                            directoryBrowser.preflight(connection: connection)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        isInBackground = false
                        autoConnectIfPossible()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        // Cover content before iOS takes the app-switcher snapshot.
                        isInBackground = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        isInBackground = false
                    }

                if showSplash || isInBackground {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
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
