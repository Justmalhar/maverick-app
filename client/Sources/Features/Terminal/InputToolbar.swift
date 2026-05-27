// client/Sources/Features/Terminal/InputToolbar.swift
import SwiftUI

struct InputToolbar: View {
    let terminalVC: TerminalViewController
    @State private var ctrlLatched = false
    @State private var showSymbols = false

    var body: some View {
        VStack(spacing: 6) {
            // Primary row: modifiers + arrows + most-used controls
            HStack(spacing: 5) {
                KeyCap(label: "esc", action: { terminalVC.sendEsc(); ctrlLatched = false })
                KeyCap(label: "tab", action: { terminalVC.sendTab(); ctrlLatched = false })
                KeyCap(
                    label: "ctrl",
                    style: ctrlLatched ? .latched : .neutral,
                    action: { ctrlLatched.toggle() }
                )
                Spacer(minLength: 4)
                KeyCap(label: "↑", minWidth: 34, action: { sendArrowOrCtrl("[A", ctrlByte: 0x10) })
                KeyCap(label: "↓", minWidth: 34, action: { sendArrowOrCtrl("[B", ctrlByte: 0x0E) })
                KeyCap(label: "←", minWidth: 34, action: { sendArrowOrCtrl("[D", ctrlByte: 0x02) })
                KeyCap(label: "→", minWidth: 34, action: { sendArrowOrCtrl("[C", ctrlByte: 0x06) })
                Spacer(minLength: 4)
                KeyCap(label: "^C", style: .danger, action: { terminalVC.sendCtrlC(); ctrlLatched = false })
            }

            // Secondary row: common control sequences + toggle for symbols
            HStack(spacing: 5) {
                KeyCap(label: "^D", action: { sendCtrl(0x04) })
                KeyCap(label: "^Z", action: { sendCtrl(0x1A) })
                KeyCap(label: "^L", action: { sendCtrl(0x0C) })
                KeyCap(label: "^R", action: { sendCtrl(0x12) })
                KeyCap(label: "^A", action: { sendCtrl(0x01) })
                KeyCap(label: "^E", action: { sendCtrl(0x05) })
                Spacer(minLength: 4)
                KeyCap(
                    label: showSymbols ? "abc" : "{ }",
                    style: showSymbols ? .latched : .primary,
                    action: { withAnimation(.snappy(duration: 0.15)) { showSymbols.toggle() } }
                )
            }

            // Optional symbol row
            if showSymbols {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(symbols, id: \.self) { sym in
                            KeyCap(label: sym, minWidth: 32) {
                                if let d = sym.data(using: .utf8) { terminalVC.onInput?(d) }
                                ctrlLatched = false
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(
            Rectangle().fill(Theme.stroke).frame(height: 0.5),
            alignment: .top
        )
    }

    private let symbols: [String] = [
        "|", "~", "/", "\\", "-", "_", "=", "+",
        "(", ")", "[", "]", "{", "}", "<", ">",
        "!", "@", "#", "$", "%", "^", "&", "*",
        ":", ";", "\"", "'", "`", "?", ".", ","
    ]

    // Routes an arrow tap as Ctrl+<letter> if Ctrl is latched, otherwise emits the
    // standard arrow escape sequence. Ctrl+arrows have no universal standard so we
    // map them to common readline shortcuts.
    private func sendArrowOrCtrl(_ csi: String, ctrlByte: UInt8) {
        if ctrlLatched {
            terminalVC.onInput?(Data([ctrlByte]))
            ctrlLatched = false
        } else {
            terminalVC.sendArrow(csi)
        }
    }

    private func sendCtrl(_ byte: UInt8) {
        terminalVC.onInput?(Data([byte]))
        ctrlLatched = false
    }
}
