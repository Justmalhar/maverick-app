// client/Sources/Features/Agent/AgentChatView.swift
import SwiftUI
import MaverickProtocol

struct AgentChatView: View {
    let sessionId: UUID

    @Environment(AgentSessionStore.self) var agentStore
    @Environment(ConnectionManager.self) var connection

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    private static let bottomAnchor = "agentChatBottom"

    private var session: AgentSessionModel? {
        agentStore.session(for: sessionId)
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .overlay {
            if let perm = session?.pendingPermission {
                PermissionDialogView(event: perm, sessionId: sessionId)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: session?.pendingPermission?.requestId)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session?.items ?? []) { item in
                        AgentMessageView(item: item, sessionId: sessionId)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 1)
                    }

                    if session?.isThinking == true {
                        ThinkingIndicator()
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Color.clear.frame(height: 8).id(Self.bottomAnchor)
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session?.items.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: session?.isThinking) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .lineLimit(1...8)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 0.5)
                )
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Theme.textPrimary : Theme.textTertiary)
                    .animation(.easeOut(duration: 0.12), value: canSend)
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 0.5), alignment: .top)
    }

    // MARK: - Private

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        connection.send(.agentInput(sessionId: sessionId, text: text))
        inputText = ""
    }
}
