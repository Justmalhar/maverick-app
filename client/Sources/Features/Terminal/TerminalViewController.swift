// client/Sources/Features/Terminal/TerminalViewController.swift
import UIKit
import SwiftTerm

final class TerminalViewController: UIViewController {
    private(set) var terminal: TerminalView!
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    private var lastCols = 0
    private var lastRows = 0
    private var pendingTheme: AppTheme?

    private static let terminalInset = UIEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let inset = Self.terminalInset
        let rect = view.bounds.inset(by: inset)
        terminal = TerminalView(frame: rect)
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        terminal.terminalDelegate = self
        terminal.backgroundColor = .black

        // SwiftTerm ships its own input accessory bar (esc/ctrl/tab/F1/arrows/etc).
        // We render our own InputToolbar in SwiftUI, so suppress theirs to
        // avoid stacking two accessory bars above the keyboard.
        terminal.inputAccessoryView = nil

        // Nerd Font with Powerline glyphs — bundled in the app.
        // PostScript name (the family name minus spaces) is what UIFont needs.
        if let font = UIFont(name: "MesloLGSNF-Regular", size: 12)
            ?? UIFont(name: "MesloLGS NF", size: 12) {
            terminal.font = font
        } else {
            terminal.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }

        view.addSubview(terminal)

        // Apply any theme set before the view was loaded.
        if let pendingTheme {
            apply(theme: pendingTheme)
            self.pendingTheme = nil
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        terminal.frame = view.bounds.inset(by: Self.terminalInset)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Defer to the next runloop AND give layout a beat — SwiftUI's
        // navigation push hasn't fully settled at viewDidAppear, so calling
        // becomeFirstResponder right here is often a no-op.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            _ = self?.terminal.becomeFirstResponder()
        }
    }

    func focusInput() {
        _ = terminal.becomeFirstResponder()
    }

    func injectText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        onInput?(data)
    }

    /// Applies the active app theme to the SwiftTerm view (background, foreground,
    /// cursor, and the 16-color ANSI palette). Safe to call before the view is
    /// loaded — the theme is then applied during viewDidLoad.
    func applyTheme(_ theme: AppTheme) {
        guard isViewLoaded, terminal != nil else {
            pendingTheme = theme
            return
        }
        apply(theme: theme)
    }

    private func apply(theme: AppTheme) {
        let bg = UIColor(hex: theme.terminal.background)
        let fg = UIColor(hex: theme.terminal.foreground)
        let cursor = UIColor(hex: theme.terminal.cursor ?? theme.terminal.foreground)

        terminal.backgroundColor = bg
        view.backgroundColor = bg
        terminal.nativeBackgroundColor = bg
        terminal.nativeForegroundColor = fg
        terminal.caretColor = cursor

        let ansi = theme.terminal.ansi16.map { hex -> SwiftTerm.Color in
            let c = UIColor(hex: hex)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            // SwiftTerm.Color uses 0...65535 16-bit components.
            return SwiftTerm.Color(red: UInt16(r * 65535), green: UInt16(g * 65535), blue: UInt16(b * 65535))
        }
        terminal.installColors(ansi)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let cols = terminal.getTerminal().cols
        let rows = terminal.getTerminal().rows
        if cols != lastCols || rows != lastRows {
            lastCols = cols
            lastRows = rows
            onResize?(cols, rows)
        }
    }

    func feed(data: Data) {
        DispatchQueue.main.async { [weak self] in
            self?.terminal.feed(byteArray: Array(data)[...])
        }
    }

    func sendCtrlC() {
        onInput?(Data([0x03]))
    }

    func sendEsc() {
        onInput?(Data([0x1B]))
    }

    func sendTab() {
        onInput?(Data([0x09]))
    }

    func sendArrow(_ code: String) {
        if let d = "\u{1B}\(code)".data(using: .utf8) { onInput?(d) }
    }
}

extension TerminalViewController: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        if newCols != lastCols || newRows != lastRows {
            lastCols = newCols
            lastRows = newRows
            onResize?(newCols, newRows)
        }
    }
    func bell(source: TerminalView) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}
