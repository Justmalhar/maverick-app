// client/Sources/Features/Settings/SettingsSheet.swift
import SwiftUI

struct SettingsSheet: View {
    @Environment(AppSettings.self) var settings
    @Environment(ThemeStore.self) var themeStore
    @Environment(\.dismiss) var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        themeSection
                        voiceSection
                        aboutSection
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

    // MARK: - Sections

    private var themeSection: some View {
        sectionContainer(title: "Terminal Theme", subtitle: "Affects only the terminal colors. UI chrome stays monochrome.") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(themeStore.themes) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: theme.id == themeStore.current.id,
                        onSelect: { themeStore.select(theme) }
                    )
                }
            }
        }
    }

    private var voiceSection: some View {
        @Bindable var settings = settings
        return sectionContainer(
            title: "Voice Input",
            subtitle: "Maverick uses Deepgram to transcribe speech into terminal input. Get an API key at deepgram.com."
        ) {
            VStack(alignment: .leading, spacing: 10) {
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
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.onAccent)
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
                    if settings.hasDeepgramKey {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.success)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        sectionContainer(title: "About") {
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

    private func sectionContainer<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
    }
}

private struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Mini terminal preview
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: theme.terminal.background))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("$")
                                .foregroundStyle(Color(hex: theme.terminal.green))
                            Text("ls -la")
                                .foregroundStyle(Color(hex: theme.terminal.foreground))
                        }
                        HStack(spacing: 0) {
                            Text("drwxr-xr-x ")
                                .foregroundStyle(Color(hex: theme.terminal.blue))
                            Text("project")
                                .foregroundStyle(Color(hex: theme.terminal.cyan))
                        }
                        Text("README.md")
                            .foregroundStyle(Color(hex: theme.terminal.yellow))
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .padding(8)
                }
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 2 : 0.5)
                )

                HStack {
                    Text(theme.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.system(size: 13))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
