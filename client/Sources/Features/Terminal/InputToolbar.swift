// client/Sources/Features/Terminal/InputToolbar.swift
import SwiftUI

struct InputToolbar: View {
    let terminalVC: TerminalViewController

    @State private var expanded = false
    @State private var ctrlLatched = false
    @State private var showSymbols = false

    var body: some View {
        VStack(spacing: 0) {
            // Expanded panels live ABOVE the primary row so the joystick + mic
            // remain anchored at the bottom — closer to the user's thumb.
            if expanded {
                expandedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            primaryRow
        }
        .background(.thinMaterial)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 0.5), alignment: .top)
    }

    // MARK: - Primary always-visible row
    // Three equal-width logical columns so the joystick is geometrically centered:
    //   [ scrolling quick keys ]   [ joystick ]   [ mic + expand chevron ]

    private var primaryRow: some View {
        HStack(spacing: 8) {
            quickKeys
                .frame(maxWidth: .infinity, alignment: .leading)

            CursorPad(terminalVC: terminalVC)

            HStack(spacing: 6) {
                MicButton(terminalVC: terminalVC)
                expandChevron
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var quickKeys: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                KeyCap(label: "esc", action: { terminalVC.sendEsc(); ctrlLatched = false })
                KeyCap(label: "tab", action: { terminalVC.sendTab(); ctrlLatched = false })
                KeyCap(
                    label: "ctrl",
                    style: ctrlLatched ? .latched : .neutral,
                    action: { ctrlLatched.toggle() }
                )
                KeyCap(label: "↩", action: { send(0x0D) })
                KeyCap(label: "|", minWidth: 30, action: { sendChar("|") })
                KeyCap(label: "~", minWidth: 30, action: { sendChar("~") })
                KeyCap(label: "/", minWidth: 30, action: { sendChar("/") })
                KeyCap(label: "-", minWidth: 30, action: { sendChar("-") })
            }
            .padding(.horizontal, 2)
        }
    }

    private var expandChevron: some View {
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

    // MARK: - Expanded panel: arrows row + control sequences + optional symbols

    private var expandedPanel: some View {
        VStack(spacing: 6) {
            // Arrows + return + symbol toggle on one row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    KeyCap(label: "↑", action: { terminalVC.sendArrow("[A"); ctrlLatched = false })
                    KeyCap(label: "↓", action: { terminalVC.sendArrow("[B"); ctrlLatched = false })
                    KeyCap(label: "←", action: { terminalVC.sendArrow("[D"); ctrlLatched = false })
                    KeyCap(label: "→", action: { terminalVC.sendArrow("[C"); ctrlLatched = false })
                    KeyCap(label: "home", action: { sendEscSeq("[H") })
                    KeyCap(label: "end",  action: { sendEscSeq("[F") })
                    KeyCap(label: "pgUp", action: { sendEscSeq("[5~") })
                    KeyCap(label: "pgDn", action: { sendEscSeq("[6~") })
                }
                .padding(.horizontal, 8)
            }

            // Common readline / process-control sequences.
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

                    Button {
                        withAnimation(.snappy(duration: 0.15)) { showSymbols.toggle() }
                    } label: {
                        Text(showSymbols ? "abc" : "{ }")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(showSymbols ? Theme.onAccent : Theme.accent)
                            .frame(minWidth: 40, minHeight: 34)
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(showSymbols ? Color.white.opacity(0.95) : Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }

            // Optional symbol drawer.
            if showSymbols {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(symbols, id: \.self) { sym in
                            KeyCap(label: sym, minWidth: 30) { sendChar(sym); ctrlLatched = false }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 0.5), alignment: .bottom)
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

    private func sendEscSeq(_ tail: String) {
        terminalVC.sendArrow(tail)
        ctrlLatched = false
    }

    private func sendChar(_ s: String) {
        if ctrlLatched, let scalar = s.unicodeScalars.first {
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
