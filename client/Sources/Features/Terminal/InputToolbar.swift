// client/Sources/Features/Terminal/InputToolbar.swift
import SwiftUI

struct InputToolbar: View {
    let terminalVC: TerminalViewController

    @State private var expanded = false
    @State private var ctrlLatched = false
    @State private var showSymbols = false

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible primary bar
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        KeyCap(label: "esc",  action: { terminalVC.sendEsc(); ctrlLatched = false })
                        KeyCap(label: "tab",  action: { terminalVC.sendTab(); ctrlLatched = false })
                        KeyCap(
                            label: "ctrl",
                            style: ctrlLatched ? .latched : .neutral,
                            action: { ctrlLatched.toggle() }
                        )
                        KeyCap(label: "↩",    action: { send(0x0D) })
                        KeyCap(label: "|",    minWidth: 30, action: { sendChar("|") })
                        KeyCap(label: "~",    minWidth: 30, action: { sendChar("~") })
                        KeyCap(label: "/",    minWidth: 30, action: { sendChar("/") })
                        KeyCap(label: "-",    minWidth: 30, action: { sendChar("-") })
                        KeyCap(label: "↑",    minWidth: 30, action: { terminalVC.sendArrow("[A") })
                        KeyCap(label: "↓",    minWidth: 30, action: { terminalVC.sendArrow("[B") })
                        KeyCap(label: "←",    minWidth: 30, action: { terminalVC.sendArrow("[D") })
                        KeyCap(label: "→",    minWidth: 30, action: { terminalVC.sendArrow("[C") })
                    }
                    .padding(.horizontal, 2)
                }

                // Expand toggle
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        expanded.toggle()
                        if !expanded { showSymbols = false }
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.surface))
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Expanded panel
            if expanded {
                VStack(spacing: 6) {
                    Divider().background(Theme.stroke)

                    // Control sequences row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            KeyCap(label: "^C", style: .danger,  action: { send(0x03) })
                            KeyCap(label: "^D",                    action: { send(0x04) })
                            KeyCap(label: "^Z",                    action: { send(0x1A) })
                            KeyCap(label: "^L",                    action: { send(0x0C) })
                            KeyCap(label: "^A",                    action: { send(0x01) })
                            KeyCap(label: "^E",                    action: { send(0x05) })
                            KeyCap(label: "^R",                    action: { send(0x12) })
                            KeyCap(label: "^W",                    action: { send(0x17) })
                            KeyCap(label: "^U",                    action: { send(0x15) })
                            KeyCap(label: "^K",                    action: { send(0x0B) })
                        }
                        .padding(.horizontal, 8)
                    }

                    // Mic + cursor pad + symbol toggle row
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.snappy(duration: 0.15)) { showSymbols.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "textformat")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(showSymbols ? "Hide symbols" : "Show symbols")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(showSymbols ? Theme.onAccent : Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(showSymbols ? Color.white.opacity(0.95) : Color.white.opacity(0.06))
                            )
                            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        MicButton(terminalVC: terminalVC)
                        CursorPad(terminalVC: terminalVC)
                    }
                    .padding(.horizontal, 10)

                    if showSymbols {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(symbols, id: \.self) { sym in
                                    KeyCap(label: sym, minWidth: 30) { sendChar(sym); ctrlLatched = false }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.thinMaterial)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 0.5), alignment: .top)
    }

    private let symbols: [String] = [
        "(", ")", "[", "]", "{", "}", "<", ">",
        "!", "@", "#", "$", "%", "^", "&", "*",
        ":", ";", "\"", "'", "`", "\\", "?", ".",
        ",", "_", "=", "+"
    ]

    // MARK: - helpers

    private func send(_ byte: UInt8) {
        terminalVC.onInput?(Data([byte]))
        ctrlLatched = false
    }

    private func sendChar(_ s: String) {
        if ctrlLatched, let scalar = s.unicodeScalars.first {
            // Ctrl+<letter> = letter & 0x1F. Works for a-z and a few symbols.
            let byte = UInt8(scalar.value) & 0x1F
            terminalVC.onInput?(Data([byte]))
            ctrlLatched = false
            return
        }
        if let d = s.data(using: .utf8) {
            terminalVC.onInput?(d)
        }
    }
}
