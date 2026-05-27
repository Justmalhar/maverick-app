// server/Sources/main.swift
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        menuBar?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.stop()
    }
}

// Explicit main entry. `@main` on an NSApplicationDelegate did not reliably
// bootstrap NSApplicationMain in this configuration; hand-rolling it here
// is the simplest fix and matches the pre-Swift-5.3 `@NSApplicationMain` pattern.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
