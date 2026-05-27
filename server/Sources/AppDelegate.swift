// server/Sources/AppDelegate.swift
import Cocoa

@main
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
