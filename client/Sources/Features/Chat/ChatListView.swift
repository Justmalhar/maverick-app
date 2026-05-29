// client/Sources/Features/Chat/ChatListView.swift
import SwiftUI

struct ChatListView: View {
    @Binding var path: NavigationPath

    @Environment(ChatStore.self) var chatStore
    @Environment(AppSettings.self) var settings

    @State private var isEditing = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navigationHeader
                if !settings.chatAssistants.isEmpty && !isEditing {
                    assistantRow
                }
                conversationList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    // MARK: - Assistant quick-launch row

    private var assistantRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(settings.chatAssistants) { assistant in
                    Button {
                        let model = assistant.modelOverride ?? settings.chatModel
                        let convId = chatStore.newConversation(
                            model: model,
                            systemPrompt: assistant.systemPrompt,
                            assistantName: "\(assistant.emoji) \(assistant.name)"
                        )
                        path.append(convId)
                    } label: {
                        VStack(spacing: 6) {
                            Text(assistant.emoji)
                                .font(.system(size: 26))
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(Color.white.opacity(0.07)))
                                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.5))
                            Text(assistant.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 68)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 0.5)
        }
    }

    // MARK: - Nav header

    private var navigationHeader: some View {
        HStack(spacing: 8) {
            if isEditing {
                // Edit mode — glass Cancel + glass Delete (matches Agents screen pattern)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isEditing = false
                        selectedIds = []
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule()
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Select Chats")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()

                Button {
                    withAnimation { chatStore.deleteAll(ids: selectedIds) }
                    isEditing = false
                    selectedIds = []
                } label: {
                    Text(selectedIds.isEmpty ? "Delete" : "Delete (\(selectedIds.count))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedIds.isEmpty ? Theme.textTertiary : Theme.danger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule()
                }
                .buttonStyle(.plain)
                .disabled(selectedIds.isEmpty)
            } else {
                // Normal mode — glass Edit pill, no compose icon (FAB at bottom handles it)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isEditing = true }
                } label: {
                    Text("Edit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule()
                }
                .buttonStyle(.plain)
                .opacity(chatStore.conversations.isEmpty ? 0 : 1)
                .allowsHitTesting(!chatStore.conversations.isEmpty)

                Spacer()
                Text("Chats")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()

                // Settings gear — same pattern as Agents screen
                GlassEffectContainerIfAvailable {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassCircleButtonStyle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.clear)
    }

    // MARK: - Conversation list

    private var conversationList: some View {
        Group {
            if chatStore.conversations.isEmpty {
                emptyState
            } else {
                // List is required for .swipeActions to work (LazyVStack doesn't support it).
                List {
                    ForEach(chatStore.conversations) { conv in
                        ChatConversationRow(
                            conversation: conv,
                            isEditing: isEditing,
                            isSelected: selectedIds.contains(conv.id),
                            isStreaming: chatStore.streamingConversationId == conv.id,
                            onTap: {
                                if isEditing {
                                    if selectedIds.contains(conv.id) { selectedIds.remove(conv.id) }
                                    else { selectedIds.insert(conv.id) }
                                } else {
                                    path.append(conv.id)
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                withAnimation { chatStore.delete(id: conv.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.red)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation { chatStore.delete(id: conv.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
            Text("No chats yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Tap ✏️ to start a conversation\nwith any AI model.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textTertiary)

            if settings.chatAPIKey.isEmpty {
                Button { showSettings = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "key.fill").font(.system(size: 13))
                        Text("Add API Key")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Conversation row

private struct ChatConversationRow: View {
    let conversation: ChatConversation
    let isEditing: Bool
    let isSelected: Bool
    let isStreaming: Bool
    let onTap: () -> Void

    private var timeLabel: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isEditing {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Theme.accent : Theme.textTertiary, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle().fill(Theme.accent).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.onAccent)
                        }
                    }
                }

                // Avatar bubble
                ZStack {
                    Circle().fill(Color.white.opacity(0.08)).frame(width: 42, height: 42)
                    Circle().strokeBorder(Theme.stroke, lineWidth: 0.8).frame(width: 42, height: 42)
                    if isStreaming {
                        TypingIndicator()
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(conversation.preview.isEmpty ? conversation.modelId : conversation.preview)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(timeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    if !isEditing {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        // Swipe actions and context menu are attached to the List row in
        // ChatListView so they get standard system rendering.
    }
}

// MARK: - Typing indicator (three pulsing dots)

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
