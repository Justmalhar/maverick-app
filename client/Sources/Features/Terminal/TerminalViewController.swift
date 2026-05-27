// client/Sources/Features/Terminal/TerminalViewController.swift
import UIKit
import SwiftTerm

final class TerminalViewController: UIViewController {
    private(set) var terminal: TerminalView!
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    private var lastCols = 0
    private var lastRows = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        terminal = TerminalView(frame: view.bounds)
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        terminal.terminalDelegate = self
        terminal.backgroundColor = .black

        // Nerd Font with Powerline glyphs — bundled in the app.
        // PostScript name (the family name minus spaces) is what UIFont needs.
        if let font = UIFont(name: "MesloLGSNF-Regular", size: 12)
            ?? UIFont(name: "MesloLGS NF", size: 12) {
            terminal.font = font
        } else {
            terminal.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }

        view.addSubview(terminal)
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
