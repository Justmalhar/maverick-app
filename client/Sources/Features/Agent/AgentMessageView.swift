// client/Sources/Features/Agent/AgentMessageView.swift
import SwiftUI
import MaverickProtocol

// MARK: - Item router

struct AgentMessageView: View {
    let item: AgentChatItem
    let sessionId: UUID

    var body: some View {
        Group {
            switch item.kind {
            case .userBubble(let text):
                UserBubbleView(text: text)
            case .assistantBubble(let text, let isStreaming):
                AssistantBubbleView(text: text, isStreaming: isStreaming)
            case .toolBatch(let tools, let isCollapsed):
                ToolBatchRowView(tools: tools, initiallyCollapsed: isCollapsed)
            case .permissionRequest(let event):
                PermissionHistoryRow(event: event)
            case .statusBadge(let text, let kind):
                StatusBadgeView(text: text, kind: kind)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .turnSummary(let cost, let inputTokens, let outputTokens, let effortLevel):
                TurnSummaryRow(cost: cost, inputTokens: inputTokens,
                               outputTokens: outputTokens, effortLevel: effortLevel)
            case .sessionError(let reason):
                SessionErrorRow(reason: reason)
            }
        }
    }
}

// MARK: - User bubble

struct UserBubbleView: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Assistant bubble

struct AssistantBubbleView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                MarkdownContentView(text: text.isEmpty && isStreaming ? " " : text)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)

                if isStreaming && !text.isEmpty {
                    StreamingCursor()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 0.5)
            )
            Spacer(minLength: 60)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Streaming cursor

private struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Theme.textPrimary)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.55).repeatForever(), value: visible)
            .onAppear { visible = false }
    }
}

// MARK: - Thinking indicator

struct ThinkingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.13),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.5)
        )
        .onAppear {
            withAnimation { phase = 1 }
        }
    }
}

// MARK: - Status badge

struct StatusBadgeView: View {
    let text: String
    let kind: BadgeKind

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(kindColor)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(kindColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(kindColor.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(kindColor.opacity(0.3), lineWidth: 0.5))
    }

    private var kindColor: Color {
        switch kind {
        case .info:    return Theme.textSecondary
        case .warning: return Color(hex: "#facc15")
        case .error:   return Theme.danger
        case .success: return Theme.success
        }
    }
}

// MARK: - Permission history row (inline chat record)

private struct PermissionHistoryRow: View {
    let event: PermissionEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#facc15"))
            Text("Permission requested: ")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            + Text(event.tool)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: "#facc15").opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(hex: "#facc15").opacity(0.2), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Turn summary row

struct TurnSummaryRow: View {
    let cost: Double?
    let inputTokens: Int?
    let outputTokens: Int?
    let effortLevel: EffortLevel?

    var body: some View {
        HStack(spacing: 12) {
            if let cost, cost > 0 {
                label(icon: "dollarsign.circle", text: String(format: "$%.4f", cost))
            }
            if let inputTokens {
                label(icon: "arrow.down.circle", text: "\(formatTokens(inputTokens)) in")
            }
            if let outputTokens {
                label(icon: "arrow.up.circle", text: "\(formatTokens(outputTokens)) out")
            }
            if let effortLevel {
                label(icon: "gauge.with.dots.needle.67percent", text: effortLevel.rawValue)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

// MARK: - Session error row

struct SessionErrorRow: View {
    let reason: StopFailureReason

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.danger)
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundStyle(Theme.danger)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var errorMessage: String {
        switch reason {
        case .rateLimit:   return "Rate limit reached"
        case .authFailed:  return "Authentication failed"
        case .billing:     return "Billing issue — check your plan"
        case .serverError: return "Server error"
        case .maxTokens:   return "Context limit reached"
        case .unknown:     return "Session ended unexpectedly"
        }
    }
}

// MARK: - Permission overlay dialog

struct PermissionDialogView: View {
    let event: PermissionEvent
    let sessionId: UUID
    @Environment(AgentSessionStore.self) var agentStore
    @Environment(ConnectionManager.self) var connection

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .blur(radius: 0)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "#facc15"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permission Required")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(event.tool)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color(hex: "#facc15"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider().overlay(Theme.stroke)

                // Input summary
                if !event.inputSummary.isEmpty {
                    Text(event.inputSummary)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().overlay(Theme.stroke)

                // Action buttons
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        respond(allowed: false)
                    } label: {
                        Text("Deny")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        respond(allowed: true)
                    } label: {
                        Text("Allow")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.success)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.strokeStrong, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
    }

    private func respond(allowed: Bool) {
        if let requestId = UUID(uuidString: event.requestId) {
            connection.send(.permissionResponse(sessionId: sessionId, requestId: requestId, allowed: allowed))
        }
        agentStore.session(for: sessionId)?.resolvePermission(requestId: event.requestId)
    }
}
