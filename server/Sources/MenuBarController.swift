// server/Sources/MenuBarController.swift
import Cocoa
import MaverickProtocol

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var sessionManager = SessionManager()
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
