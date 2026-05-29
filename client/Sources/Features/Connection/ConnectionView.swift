// client/Sources/Features/Connection/ConnectionView.swift
import SwiftUI

struct ConnectionView: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(ConnectionHistory.self) var history
    @State private var host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
    @State private var port: String = {
        let p = UserDefaults.standard.integer(forKey: "lastPort")
        return p == 0 ? "8765" : String(p)
    }()
    @State private var token = ""
    @FocusState private var focused: Field?

    private enum Field { case host, port, token }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            // Subtle radial glow in the top-left
            RadialGradient(
                colors: [Theme.accent.opacity(0.18), .clear],
                center: .topLeading, startRadius: 20, endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 24) {
                    hero
                    if !history.hosts.isEmpty {
                        historySection
                    }
                    formCard
                    connectButton
                    if let err = connection.lastError, connection.state != .connecting {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 22)
                .padding(.top, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(spacing: 12) {
            Image("MaverickLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )
            Text("Maverick")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Your Mac's terminal, in your pocket.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var formCard: some View {
        VStack(spacing: 14) {
            LabeledField(
                icon: "network",
                label: "Mac Address",
                placeholder: "100.x.x.x or hostname.ts.net",
                text: $host,
                keyboardType: .URL
            )
            .focused($focused, equals: .host)
            .submitLabel(.next)
            .onSubmit { focused = .port }

            LabeledField(
                icon: "number",
                label: "Port",
                placeholder: "8765",
                text: $port,
                keyboardType: .numberPad
            )
            .focused($focused, equals: .port)

            LabeledField(
                icon: "key.fill",
                label: "Token (optional)",
                placeholder: "shared secret if configured",
                text: $token,
                secure: true
            )
            .focused($focused, equals: .token)
        }
        .padding(18)
        .liquidGlassSurface(cornerRadius: 18, elevation: 0.8)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 11, weight: .semibold))
                Text("Saved Servers")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(history.sortedByRecency) { entry in
                        Button {
                            host = entry.host
                            port = String(entry.port)
                            if let t = entry.token { token = t }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                    .font(.system(size: 13, weight: .semibold, design: entry.name.isEmpty ? .monospaced : .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("\(entry.host):\(entry.port)  •  \(entry.lastConnected, format: .relative(presentation: .named))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .liquidGlassSurface(cornerRadius: 12, elevation: 0.5)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                history.remove(entry)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var connectButton: some View {
        Button {
            focused = nil
            let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let intPort = Int(port) ?? 8765
            history.record(host: cleanHost, port: intPort, token: token.isEmpty ? nil : token)
            connection.connect(
                host: cleanHost,
                port: intPort,
                token: token
            )
        } label: {
            HStack(spacing: 8) {
                if connection.state == .connecting {
                    ProgressView()
                }
                Text(connection.state == .connecting ? "Connecting…" : "Connect")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            // iOS 26: glassProminent gives the opaque primary-action Liquid Glass button.
            // iOS <26: keep the existing white gradient capsule.
            .ifNot26 {
                $0.foregroundStyle(.black)
                    .background(Capsule().fill(Theme.accentGradient))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 14, x: 0, y: 6)
            }
        }
        .connectButtonStyle()
        .disabled(host.isEmpty || connection.state == .connecting)
        .opacity((host.isEmpty || connection.state == .connecting) ? 0.6 : 1)
    }
}

private struct LabeledField: View {
    let icon: String
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)

            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
        }
    }
}
