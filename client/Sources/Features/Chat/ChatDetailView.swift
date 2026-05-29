// client/Sources/Features/Chat/ChatDetailView.swift
import SwiftUI

struct ChatDetailView: View {
    let conversationId: UUID
    let initialModel: String

    @Environment(ChatStore.self) var chatStore
    @Environment(AppSettings.self) var settings
    @Environment(\.dismiss) var dismiss

    @State private var inputText = ""
    @State private var showModelPicker = false
    @FocusState private var inputFocused: Bool

    private var conversation: ChatConversation? {
        chatStore.conversations.first(where: { $0.id == conversationId })
    }

    private var isStreaming: Bool {
        chatStore.streamingConversationId == conversationId
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .background(Theme.bg)
        .navigationTitle(conversation?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        // Transparent nav bar — matches the pure-black app background
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Model picker
                    Section("Model") {
                        ForEach(knownModels, id: \.self) { model in
                            Button {
                                chatStore.updateModel(model, for: conversationId)
                            } label: {
                                if model == (conversation?.modelId ?? initialModel) {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    }
                    // Persona / system prompt picker
                    Section("Persona") {
                        Button {
                            chatStore.updateSystemPrompt(nil, assistantName: nil, for: conversationId)
                        } label: {
                            if conversation?.systemPrompt == nil || conversation?.systemPrompt?.isEmpty == true {
                                Label("Default (no persona)", systemImage: "checkmark")
                            } else {
                                Text("Default (no persona)")
                            }
                        }
                        ForEach(settings.chatAssistants) { assistant in
                            Button {
                                chatStore.updateSystemPrompt(
                                    assistant.systemPrompt,
                                    assistantName: "\(assistant.emoji) \(assistant.name)",
                                    for: conversationId
                                )
                            } label: {
                                let active = conversation?.assistantName == "\(assistant.emoji) \(assistant.name)"
                                if active {
                                    Label("\(assistant.emoji) \(assistant.name)", systemImage: "checkmark")
                                } else {
                                    Text("\(assistant.emoji) \(assistant.name)")
                                }
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        chatStore.delete(id: conversationId)
                        dismiss()
                    } label: {
                        Label("Delete Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onTapGesture { inputFocused = false }
        .preferredColorScheme(.dark)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Active model + persona chip
                    Text(activeSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
                        .padding(.bottom, 8)

                    if let conv = conversation {
                        // Exclude the empty assistant placeholder while streaming — TypingBubble covers it
                        ForEach(conv.messages.filter { msg in
                            msg.role != .system &&
                            !(isStreaming && msg.role == .assistant && msg.content.isEmpty)
                        }) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        }
                    }
                    if isStreaming, let last = conversation?.messages.last, last.content.isEmpty {
                        TypingBubble()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.top, 12)
            }
            .onChange(of: conversation?.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: conversation?.messages.last?.content) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.stroke).frame(height: 0.5)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(inputFocused ? Theme.stroke.opacity(0.5) : Theme.stroke, lineWidth: 0.8)
                    )

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(canSend ? Theme.accent : Theme.textTertiary.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.snappy(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming && !settings.chatAPIKey.isEmpty
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await chatStore.send(text, to: conversationId, settings: settings)
        }
    }

    private var activeSubtitle: String {
        let model = conversation?.modelId ?? initialModel
        if let persona = conversation?.assistantName, !persona.isEmpty {
            return "\(model) · \(persona)"
        }
        return model
    }

    private var knownModels: [String] {
        ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo",
         "claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001",
         "meta-llama/llama-3.3-70b-instruct", "google/gemini-pro-1.5"]
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.onAccent)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.accent)
                        )
                    // Timestamp + copy row
                    HStack(spacing: 6) {
                        copyButton
                        Text(message.timestamp, format: .dateTime.hour().minute())
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        } else {
            // Full-width markdown — avatar left, content expands right
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.07)).frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownContentView(text: message.content)
                        .textSelection(.enabled)
                    // Timestamp + copy row
                    HStack(spacing: 6) {
                        Text(message.timestamp, format: .dateTime.hour().minute())
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                        copyButton
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.content
            withAnimation(.snappy(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.snappy(duration: 0.15)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copied ? Theme.success : Theme.textTertiary)
                .animation(.snappy(duration: 0.15), value: copied)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Typing bubble (while streaming starts)

private struct TypingBubble: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().fill(Color.white.opacity(0.07)).frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.textTertiary).frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.12),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke.opacity(0.5), lineWidth: 0.5))
            Spacer(minLength: 50)
        }
        .onAppear { animating = true }
    }
}
