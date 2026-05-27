// client/Sources/Features/Terminal/InputToolbar.swift
import SwiftUI

struct InputToolbar: View {
    let terminalVC: TerminalViewController
    @State private var ctrlLatched = false
    @State private var showSymbols = false

    var body: some View {
        HStack(spacing: 10) {
            // Key columns
            VStack(spacing: 6) {
                // Primary row: modifiers + most-used controls
                HStack(spacing: 5) {
                    KeyCap(label: "esc", action: { terminalVC.sendEsc(); ctrlLatched = false })
                    KeyCap(label: "tab", action: { terminalVC.sendTab(); ctrlLatched = false })
                    KeyCap(
                        label: "ctrl",
                        style: ctrlLatched ? .latched : .neutral,
                        action: { ctrlLatched.toggle() }
                    )
                    KeyCap(label: "^C", style: .danger, action: { terminalVC.sendCtrlC(); ctrlLatched = false })
                    KeyCap(label: "^D", action: { sendCtrl(0x04) })
                    KeyCap(label: "^Z", action: { sendCtrl(0x1A) })
                    KeyCap(label: "^L", action: { sendCtrl(0x0C) })
                    Spacer(minLength: 0)
                }

                // Secondary row: readline + symbol toggle
                HStack(spacing: 5) {
                    KeyCap(label: "^A", action: { sendCtrl(0x01) })
                    KeyCap(label: "^E", action: { sendCtrl(0x05) })
                    KeyCap(label: "^R", action: { sendCtrl(0x12) })
                    KeyCap(label: "^W", action: { sendCtrl(0x17) })
                    KeyCap(label: "^U", action: { sendCtrl(0x15) })
                    KeyCap(label: "^K", action: { sendCtrl(0x0B) })
                    KeyCap(
                        label: showSymbols ? "abc" : "{ }",
                        style: showSymbols ? .latched : .primary,
                        action: { withAnimation(.snappy(duration: 0.15)) { showSymbols.toggle() } }
                    )
                    Spacer(minLength: 0)
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

            // Right column: mic + cursor pad
            VStack(spacing: 8) {
                MicButton(terminalVC: terminalVC)
                CursorPad(terminalVC: terminalVC)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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

    private func sendCtrl(_ byte: UInt8) {
        terminalVC.onInput?(Data([byte]))
        ctrlLatched = false
    }
}
