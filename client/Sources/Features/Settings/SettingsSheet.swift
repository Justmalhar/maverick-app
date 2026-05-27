// client/Sources/Features/Settings/SettingsSheet.swift
import SwiftUI

struct SettingsSheet: View {
    @Environment(AppSettings.self) var settings
    @Environment(\.dismiss) var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        section(
                            title: "Voice Input",
                            subtitle: "Maverick uses Deepgram to transcribe what you say into terminal input. Get a free API key at deepgram.com."
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Deepgram API Key")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                SecureField("dg_xxx…", text: $draftKey)
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
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
                                HStack {
                                    Button("Save") {
                                        settings.deepgramAPIKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                        dismiss()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.accent)
                                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    if settings.hasDeepgramKey {
                                        Button(role: .destructive) {
                                            settings.deepgramAPIKey = ""
                                            draftKey = ""
                                        } label: {
                                            Text("Clear")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    Spacer()
                                }
                            }
                        }

                        section(title: "About") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Maverick is a mobile companion for your Mac terminal.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("All connections go through Tailscale; no data passes through our servers.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(Theme.accent)
                }
            }
            .onAppear { draftKey = settings.deepgramAPIKey }
        }
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
            content()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
    }
}
