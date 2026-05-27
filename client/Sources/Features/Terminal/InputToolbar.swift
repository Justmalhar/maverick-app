// client/Sources/Features/Terminal/InputToolbar.swift
import SwiftUI

struct InputToolbar: View {
    let terminalVC: TerminalViewController
    @State private var ctrlLatched = false

    var body: some View {
        HStack(spacing: 4) {
            Button("Ctrl") {
                ctrlLatched.toggle()
            }
            .foregroundStyle(ctrlLatched ? .yellow : .primary)
            .buttonStyle(.bordered)

            Button("Esc")  { terminalVC.sendEsc();  ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("Tab")  { terminalVC.sendTab();  ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("↑")  { terminalVC.sendArrow("[A"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("↓")  { terminalVC.sendArrow("[B"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("←")  { terminalVC.sendArrow("[D"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("→")  { terminalVC.sendArrow("[C"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("^C") { terminalVC.sendCtrlC(); ctrlLatched = false }
                .foregroundStyle(.red)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
