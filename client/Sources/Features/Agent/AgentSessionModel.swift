// client/Sources/Features/Agent/AgentSessionModel.swift
import Foundation
import MaverickProtocol

// MARK: - Chat timeline item

struct AgentChatItem: Identifiable {
    enum Kind {
        case userBubble(text: String)
        case assistantBubble(text: String, isStreaming: Bool)
        case toolBatch(tools: [ToolCallEvent], isCollapsed: Bool)
        case permissionRequest(event: PermissionEvent)
        case statusBadge(text: String, kind: BadgeKind)
        case turnSummary(cost: Double?, inputTokens: Int?, outputTokens: Int?, effortLevel: EffortLevel?)
        case sessionError(reason: StopFailureReason)
    }

    let id: UUID
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

// MARK: - Per-session accumulator

@Observable
final class AgentSessionModel {
    let sessionId: UUID
    var provider: AgentProvider
    var mode: SessionMode
    var cwd: String
    var model: String?

    var isThinking: Bool = false
    var items: [AgentChatItem] = []

    /// Active permission request awaiting user input. Nil when none is pending.
    var pendingPermission: PermissionEvent? = nil

    private var pendingToolCalls: [String: ToolCallEvent] = [:]
    private var completedBatch: [ToolCallEvent] = []
    private var streamingBubbleId: UUID? = nil

    init(sessionId: UUID, provider: AgentProvider, mode: SessionMode, cwd: String) {
        self.sessionId = sessionId
        self.provider = provider
        self.mode = mode
        self.cwd = cwd
    }

    // MARK: - Public API

    /// Called by the UI after the user approves or denies a permission.
    func resolvePermission(requestId: String) {
        if pendingPermission?.requestId == requestId {
            pendingPermission = nil
        }
    }

    func apply(_ event: AgentEvent) {
        switch event {
        case .sessionStart(_, let provider, let cwd, let model, _):
            self.provider = provider
            self.cwd = cwd
            self.model = model

        case .cwdChanged(_, let to):
            cwd = to

        case .userMessage(let text):
            flushBatch()
            items.append(AgentChatItem(kind: .userBubble(text: text)))

        case .tokenDelta(let text):
            flushBatch()
            isThinking = false
            // Optimistic O(1) check: streaming bubble is always the last item.
            if let sid = streamingBubbleId,
               let last = items.last, last.id == sid,
               case .assistantBubble(let existing, _) = last.kind {
                items[items.count - 1].kind = .assistantBubble(text: existing + text, isStreaming: true)
            } else {
                let newId = UUID()
                streamingBubbleId = newId
                items.append(AgentChatItem(id: newId, kind: .assistantBubble(text: text, isStreaming: true)))
            }

        case .assistantMessage(let text):
            flushBatch()
            finalizeStreamingBubble()
            items.append(AgentChatItem(kind: .assistantBubble(text: text, isStreaming: false)))

        case .toolCallStart(let evt):
            isThinking = true
            pendingToolCalls[evt.id] = evt

        case .toolCallComplete(let evt):
            pendingToolCalls.removeValue(forKey: evt.id)
            completedBatch.append(evt)
            if pendingToolCalls.isEmpty { isThinking = false }

        case .toolCallFailed(let evt):
            pendingToolCalls.removeValue(forKey: evt.id)
            completedBatch.append(evt)
            if pendingToolCalls.isEmpty { isThinking = false }

        case .toolBatchComplete(let events):
            // Server-authoritative batch supersedes our locally accumulated list.
            completedBatch = []
            pendingToolCalls = [:]
            items.append(AgentChatItem(kind: .toolBatch(tools: events, isCollapsed: true)))
            isThinking = false

        case .permissionRequest(let evt):
            pendingPermission = evt
            items.append(AgentChatItem(kind: .permissionRequest(event: evt)))
            isThinking = false

        case .permissionDenied:
            pendingPermission = nil

        case .statusBadge(let text, let kind):
            items.append(AgentChatItem(kind: .statusBadge(text: text, kind: kind)))

        case .turnStop(let cost, let inputTokens, let outputTokens, let effortLevel):
            flushBatch()
            finalizeStreamingBubble()
            isThinking = false
            if cost != nil || inputTokens != nil || outputTokens != nil {
                items.append(AgentChatItem(kind: .turnSummary(
                    cost: cost, inputTokens: inputTokens,
                    outputTokens: outputTokens, effortLevel: effortLevel
                )))
            }

        case .sessionError(let reason):
            flushBatch()
            finalizeStreamingBubble()
            isThinking = false
            items.append(AgentChatItem(kind: .sessionError(reason: reason)))

        case .sessionEnd:
            flushBatch()
            finalizeStreamingBubble()
            isThinking = false

        default:
            break
        }
    }

    // MARK: - Private

    private func flushBatch() {
        guard !completedBatch.isEmpty else { return }
        let batch = completedBatch
        completedBatch = []
        items.append(AgentChatItem(kind: .toolBatch(tools: batch, isCollapsed: true)))
    }

    private func finalizeStreamingBubble() {
        guard let sid = streamingBubbleId else { return }
        streamingBubbleId = nil
        guard let last = items.last, last.id == sid,
              case .assistantBubble(let text, _) = last.kind else { return }
        items[items.count - 1].kind = .assistantBubble(text: text, isStreaming: false)
    }
}
