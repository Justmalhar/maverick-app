// client/Sources/Features/Speech/MicButton.swift
import SwiftUI

struct MicButton: View {
    let terminalVC: TerminalViewController
    @Environment(AppSettings.self) var settings
    @State private var recorder = SpeechRecorder()
    @State private var lastError: String?
    @State private var showKeyPrompt = false

    var body: some View {
        Button(action: tap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1)

                switch recorder.state {
                case .idle, .error:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(settings.hasDeepgramKey ? Theme.textPrimary : Theme.textTertiary)
                case .recording:
                    // Pulsing red circle scaled by audio level
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 22 + CGFloat(recorder.level) * 18,
                               height: 22 + CGFloat(recorder.level) * 18)
                        .animation(.spring(duration: 0.08), value: recorder.level)
                case .transcribing:
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
            .frame(width: 50, height: 50)
            .shadow(color: shadowColor, radius: 10)
        }
        .buttonStyle(.plain)
        .alert("Deepgram API Key Required", isPresented: $showKeyPrompt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add your Deepgram API key in Settings (gear icon) to enable voice input.")
        }
        .alert("Voice input failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) { lastError = nil }
        } message: {
            Text(lastError ?? "")
        }
    }

    private var borderColor: Color {
        switch recorder.state {
        case .recording:    return Theme.danger.opacity(0.7)
        case .transcribing: return Theme.accent.opacity(0.7)
        default:            return Theme.stroke
        }
    }
    private var shadowColor: Color {
        switch recorder.state {
        case .recording:    return Theme.danger.opacity(0.5)
        case .transcribing: return Theme.accent.opacity(0.3)
        default:            return .clear
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { lastError != nil }, set: { if !$0 { lastError = nil } })
    }

    private func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch recorder.state {
        case .idle, .error:
            guard settings.hasDeepgramKey else {
                showKeyPrompt = true
                return
            }
            Task { await recorder.start() }
        case .recording:
            Task { await stopAndTranscribe() }
        case .transcribing:
            break  // ignore taps while uploading
        }
    }

    @MainActor
    private func stopAndTranscribe() async {
        guard let url = recorder.stop() else { recorder.state = .idle; return }
        recorder.state = .transcribing
        let client = DeepgramClient(apiKey: settings.deepgramAPIKey)
        do {
            let transcript = try await client.transcribe(audioURL: url)
            try? FileManager.default.removeItem(at: url)
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                terminalVC.injectText(trimmed)
            }
            recorder.state = .idle
        } catch {
            try? FileManager.default.removeItem(at: url)
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            recorder.state = .idle
        }
    }
}
