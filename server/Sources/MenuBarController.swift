// server/Sources/MenuBarController.swift
import Cocoa
import MaverickProtocol

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let broadcaster = AgentEventBroadcaster()
    private lazy var sessionManager = SessionManager(broadcaster: broadcaster)
    private var server: WebSocketServer?
    private var hookServer: HookServer?

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Maverick")
        statusItem?.button?.action = #selector(showMenu)
        statusItem?.button?.target = self

        server = WebSocketServer(sessionManager: sessionManager, port: 8765)
        do {
            try server?.start()
        } catch {
            statusItem?.button?.title = "⚠ \(error.localizedDescription)"
        }

        hookServer = HookServer()
        do {
            try hookServer?.start()
        } catch {
            NSLog("[Maverick] HookServer failed to start: %@", error.localizedDescription)
        }

        // Wire broadcaster → WebSocket broadcast to all connected clients
        let weakServer = server
        broadcaster.onEvent = { sessionId, event in
            weakServer?.broadcastAgentEvent(sessionId: sessionId, event: event)
        }

        // Wire hook events: look up Maverick UUID from Claude session ID, then broadcast
        let weakBroadcaster = broadcaster
        hookServer?.onEvent = { [weak self] event, claudeSessionId in
            guard let self else { return }
            Task {
                guard let maverickId = await self.sessionManager.resolveSessionId(forClaudeId: claudeSessionId) else {
                    NSLog("[MenuBarController] Hook event for unknown Claude session: %@", claudeSessionId)
                    return
                }
                weakBroadcaster.receive(event: event, for: maverickId)
            }
        }

        // Register HookServer with the WebSocket server so it can be forwarded to ClientHandlers
        if let hookServer {
            server?.setHookServer(hookServer)
        }
    }

    func stop() {
        server?.stop()
        hookServer?.stop()
    }

    @objc private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Maverick Agent — running on :8765", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // reset so next click rebuilds
    }
}
