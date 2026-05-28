// shared/Sources/MaverickProtocol/AgentEvent.swift
import Foundation

// MARK: - Simple enums

public enum AgentProvider: String, Codable, Sendable, Equatable {
    case claudeCode
    case codex
    case antigravity
    case opencode
    case hermes
}

public enum SessionMode: String, Codable, Sendable, Equatable {
    case terminal
    case chat
}

public enum SessionSource: String, Codable, Sendable, Equatable {
    case startup
    case resume
    case clear
    case compact
}

public enum SessionEndReason: String, Codable, Sendable, Equatable {
    case clear
    case resume
    case logout
    case promptExit
    case other
}

public enum StopFailureReason: String, Codable, Sendable, Equatable {
    case rateLimit
    case authFailed
    case billing
    case serverError
    case maxTokens
    case unknown
}

public enum BadgeKind: String, Codable, Sendable, Equatable {
    case info
    case warning
    case error
    case success
}

public enum NotificationType: String, Codable, Sendable, Equatable {
    case permissionPrompt
    case idlePrompt
    case authSuccess
    case elicitation
}

public enum EffortLevel: String, Codable, Sendable, Equatable {
    case low
    case medium
    case high
    case xhigh
    case max
}

// MARK: - ToolKind

public enum ToolKind: Codable, Sendable, Equatable {
    // File I/O (blue)
    case read, write, edit, notebookEdit
    // Search (purple)
    case glob, grep, lsp
    // Shell (orange)
    case bash, powerShell, monitor
    // Web (teal)
    case webFetch, webSearch
    // Agents / orchestration (green)
    case agent, skill, sendMessage
    // Task management (yellow)
    case taskCreate, taskUpdate, taskGet, taskList, taskStop
    case cronCreate, cronDelete, cronList
    // Planning (gray)
    case enterPlanMode, exitPlanMode, askUserQuestion
    // Git worktrees (red)
    case enterWorktree, exitWorktree
    // MCP (indigo)
    case listMcpResources, readMcpResource, waitForMcpServers, toolSearch
    // System / infra (gray)
    case pushNotification, scheduleWakeup, remoteTrigger, shareOnboardingGuide
    // Unknown tool
    case custom(String)

    private static let knownCases: [String: ToolKind] = [
        "read": .read, "write": .write, "edit": .edit, "notebookEdit": .notebookEdit,
        "glob": .glob, "grep": .grep, "lsp": .lsp,
        "bash": .bash, "powerShell": .powerShell, "monitor": .monitor,
        "webFetch": .webFetch, "webSearch": .webSearch,
        "agent": .agent, "skill": .skill, "sendMessage": .sendMessage,
        "taskCreate": .taskCreate, "taskUpdate": .taskUpdate, "taskGet": .taskGet,
        "taskList": .taskList, "taskStop": .taskStop,
        "cronCreate": .cronCreate, "cronDelete": .cronDelete, "cronList": .cronList,
        "enterPlanMode": .enterPlanMode, "exitPlanMode": .exitPlanMode, "askUserQuestion": .askUserQuestion,
        "enterWorktree": .enterWorktree, "exitWorktree": .exitWorktree,
        "listMcpResources": .listMcpResources, "readMcpResource": .readMcpResource,
        "waitForMcpServers": .waitForMcpServers, "toolSearch": .toolSearch,
        "pushNotification": .pushNotification, "scheduleWakeup": .scheduleWakeup,
        "remoteTrigger": .remoteTrigger, "shareOnboardingGuide": .shareOnboardingGuide
    ]

    private var rawName: String {
        switch self {
        case .read: return "read"
        case .write: return "write"
        case .edit: return "edit"
        case .notebookEdit: return "notebookEdit"
        case .glob: return "glob"
        case .grep: return "grep"
        case .lsp: return "lsp"
        case .bash: return "bash"
        case .powerShell: return "powerShell"
        case .monitor: return "monitor"
        case .webFetch: return "webFetch"
        case .webSearch: return "webSearch"
        case .agent: return "agent"
        case .skill: return "skill"
        case .sendMessage: return "sendMessage"
        case .taskCreate: return "taskCreate"
        case .taskUpdate: return "taskUpdate"
        case .taskGet: return "taskGet"
        case .taskList: return "taskList"
        case .taskStop: return "taskStop"
        case .cronCreate: return "cronCreate"
        case .cronDelete: return "cronDelete"
        case .cronList: return "cronList"
        case .enterPlanMode: return "enterPlanMode"
        case .exitPlanMode: return "exitPlanMode"
        case .askUserQuestion: return "askUserQuestion"
        case .enterWorktree: return "enterWorktree"
        case .exitWorktree: return "exitWorktree"
        case .listMcpResources: return "listMcpResources"
        case .readMcpResource: return "readMcpResource"
        case .waitForMcpServers: return "waitForMcpServers"
        case .toolSearch: return "toolSearch"
        case .pushNotification: return "pushNotification"
        case .scheduleWakeup: return "scheduleWakeup"
        case .remoteTrigger: return "remoteTrigger"
        case .shareOnboardingGuide: return "shareOnboardingGuide"
        case .custom(let name): return "custom:\(name)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let known = ToolKind.knownCases[raw] {
            self = known
        } else if raw.hasPrefix("custom:") {
            self = .custom(String(raw.dropFirst("custom:".count)))
        } else {
            self = .custom(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawName)
    }
}

// MARK: - Supporting structs

public struct ToolCallEvent: Codable, Sendable, Identifiable {
    public var id: String
    public var tool: ToolKind
    public var inputSummary: String
    public var result: String?
    public var error: String?
    public var durationMs: Int?
    public var fileDiffs: [FileDiff]?
    public var effort: EffortLevel?

    public init(
        id: String,
        tool: ToolKind,
        inputSummary: String,
        result: String? = nil,
        error: String? = nil,
        durationMs: Int? = nil,
        fileDiffs: [FileDiff]? = nil,
        effort: EffortLevel? = nil
    ) {
        self.id = id
        self.tool = tool
        self.inputSummary = inputSummary
        self.result = result
        self.error = error
        self.durationMs = durationMs
        self.fileDiffs = fileDiffs
        self.effort = effort
    }
}

public struct FileDiff: Codable, Sendable {
    public var path: String
    public var added: Int
    public var removed: Int

    public init(path: String, added: Int, removed: Int) {
        self.path = path
        self.added = added
        self.removed = removed
    }
}

public struct PermissionEvent: Codable, Sendable {
    public var requestId: String
    public var tool: String
    public var inputSummary: String
    public var ruleMatched: String?

    public init(requestId: String, tool: String, inputSummary: String, ruleMatched: String? = nil) {
        self.requestId = requestId
        self.tool = tool
        self.inputSummary = inputSummary
        self.ruleMatched = ruleMatched
    }
}

public struct ElicitationField: Codable, Sendable {
    public var name: String
    public var type: String
    public var description: String
    public var required: Bool

    public init(name: String, type: String, description: String, required: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

// MARK: - AgentEvent

public enum AgentEvent: Codable, Sendable {
    // Session lifecycle
    case sessionStart(id: String, provider: AgentProvider, cwd: String, model: String?, source: SessionSource)
    case sessionEnd(reason: SessionEndReason)
    case cwdChanged(from: String, to: String)

    // User / assistant turns
    case userMessage(text: String)
    case tokenDelta(text: String)
    case assistantMessage(text: String)

    // Tool call lifecycle
    case toolCallStart(ToolCallEvent)
    case toolCallComplete(ToolCallEvent)
    case toolCallFailed(ToolCallEvent)
    case toolBatchComplete([ToolCallEvent])

    // Permissions
    case permissionRequest(PermissionEvent)
    case permissionDenied(tool: String, reason: String)

    // Agent / subagent
    case subagentStart(id: String, agentType: String, parentSessionId: String)
    case subagentStop(id: String, agentType: String)

    // Task tracking
    case taskCreated(id: String, title: String)
    case taskCompleted(id: String)

    // Compaction
    case compactionStarted
    case compactionComplete

    // Worktrees
    case worktreeCreated(name: String, branch: String)
    case worktreeRemoved(path: String)

    // Status / notifications
    case notification(type: NotificationType, message: String)
    case statusBadge(text: String, kind: BadgeKind)
    case sessionError(StopFailureReason)

    // Turn complete (cost + token usage)
    case turnStop(cost: Double?, inputTokens: Int?, outputTokens: Int?, effortLevel: EffortLevel?)

    // MCP elicitation
    case elicitation(server: String, fields: [ElicitationField])

    // Pass-through for terminal view
    case rawTerminalBytes(Data)

    // MARK: Manual Codable

    private enum CodingKeys: String, CodingKey {
        case type
        // session lifecycle
        case id, provider, cwd, model, source, reason
        case from, to
        // turns
        case text
        // tool
        case event, events
        // permission
        case tool, permissionEvent
        case requestId, inputSummary, ruleMatched
        // permission denied
        // tool is reused, reason is reused
        // subagent
        case agentType, parentSessionId
        // task
        case title
        // worktree
        case name, branch, path
        // notification
        case notificationType = "notification_type", message
        // badge
        case kind
        // turn stop
        case cost, inputTokens, outputTokens, effortLevel
        // elicitation
        case server, fields
        // raw terminal bytes
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "session_start":
            self = .sessionStart(
                id: try container.decode(String.self, forKey: .id),
                provider: try container.decode(AgentProvider.self, forKey: .provider),
                cwd: try container.decode(String.self, forKey: .cwd),
                model: try container.decodeIfPresent(String.self, forKey: .model),
                source: try container.decode(SessionSource.self, forKey: .source)
            )
        case "session_end":
            self = .sessionEnd(reason: try container.decode(SessionEndReason.self, forKey: .reason))
        case "cwd_changed":
            self = .cwdChanged(
                from: try container.decode(String.self, forKey: .from),
                to: try container.decode(String.self, forKey: .to)
            )
        case "user_message":
            self = .userMessage(text: try container.decode(String.self, forKey: .text))
        case "token_delta":
            self = .tokenDelta(text: try container.decode(String.self, forKey: .text))
        case "assistant_message":
            self = .assistantMessage(text: try container.decode(String.self, forKey: .text))
        case "tool_call_start":
            self = .toolCallStart(try container.decode(ToolCallEvent.self, forKey: .event))
        case "tool_call_complete":
            self = .toolCallComplete(try container.decode(ToolCallEvent.self, forKey: .event))
        case "tool_call_failed":
            self = .toolCallFailed(try container.decode(ToolCallEvent.self, forKey: .event))
        case "tool_batch_complete":
            self = .toolBatchComplete(try container.decode([ToolCallEvent].self, forKey: .events))
        case "permission_request":
            self = .permissionRequest(try container.decode(PermissionEvent.self, forKey: .permissionEvent))
        case "permission_denied":
            self = .permissionDenied(
                tool: try container.decode(String.self, forKey: .tool),
                reason: try container.decode(String.self, forKey: .reason)
            )
        case "subagent_start":
            self = .subagentStart(
                id: try container.decode(String.self, forKey: .id),
                agentType: try container.decode(String.self, forKey: .agentType),
                parentSessionId: try container.decode(String.self, forKey: .parentSessionId)
            )
        case "subagent_stop":
            self = .subagentStop(
                id: try container.decode(String.self, forKey: .id),
                agentType: try container.decode(String.self, forKey: .agentType)
            )
        case "task_created":
            self = .taskCreated(
                id: try container.decode(String.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title)
            )
        case "task_completed":
            self = .taskCompleted(id: try container.decode(String.self, forKey: .id))
        case "compaction_started":
            self = .compactionStarted
        case "compaction_complete":
            self = .compactionComplete
        case "worktree_created":
            self = .worktreeCreated(
                name: try container.decode(String.self, forKey: .name),
                branch: try container.decode(String.self, forKey: .branch)
            )
        case "worktree_removed":
            self = .worktreeRemoved(path: try container.decode(String.self, forKey: .path))
        case "notification":
            self = .notification(
                type: try container.decode(NotificationType.self, forKey: .notificationType),
                message: try container.decode(String.self, forKey: .message)
            )
        case "status_badge":
            self = .statusBadge(
                text: try container.decode(String.self, forKey: .text),
                kind: try container.decode(BadgeKind.self, forKey: .kind)
            )
        case "session_error":
            self = .sessionError(try container.decode(StopFailureReason.self, forKey: .reason))
        case "turn_stop":
            self = .turnStop(
                cost: try container.decodeIfPresent(Double.self, forKey: .cost),
                inputTokens: try container.decodeIfPresent(Int.self, forKey: .inputTokens),
                outputTokens: try container.decodeIfPresent(Int.self, forKey: .outputTokens),
                effortLevel: try container.decodeIfPresent(EffortLevel.self, forKey: .effortLevel)
            )
        case "elicitation":
            self = .elicitation(
                server: try container.decode(String.self, forKey: .server),
                fields: try container.decode([ElicitationField].self, forKey: .fields)
            )
        case "raw_terminal_bytes":
            let b64 = try container.decode(String.self, forKey: .data)
            guard let decoded = Data(base64Encoded: b64) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .data,
                    in: container,
                    debugDescription: "Invalid base64 data for raw_terminal_bytes"
                )
            }
            self = .rawTerminalBytes(decoded)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown AgentEvent type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionStart(let id, let provider, let cwd, let model, let source):
            try container.encode("session_start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(provider, forKey: .provider)
            try container.encode(cwd, forKey: .cwd)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encode(source, forKey: .source)
        case .sessionEnd(let reason):
            try container.encode("session_end", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .cwdChanged(let from, let to):
            try container.encode("cwd_changed", forKey: .type)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .userMessage(let text):
            try container.encode("user_message", forKey: .type)
            try container.encode(text, forKey: .text)
        case .tokenDelta(let text):
            try container.encode("token_delta", forKey: .type)
            try container.encode(text, forKey: .text)
        case .assistantMessage(let text):
            try container.encode("assistant_message", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolCallStart(let event):
            try container.encode("tool_call_start", forKey: .type)
            try container.encode(event, forKey: .event)
        case .toolCallComplete(let event):
            try container.encode("tool_call_complete", forKey: .type)
            try container.encode(event, forKey: .event)
        case .toolCallFailed(let event):
            try container.encode("tool_call_failed", forKey: .type)
            try container.encode(event, forKey: .event)
        case .toolBatchComplete(let events):
            try container.encode("tool_batch_complete", forKey: .type)
            try container.encode(events, forKey: .events)
        case .permissionRequest(let event):
            try container.encode("permission_request", forKey: .type)
            try container.encode(event, forKey: .permissionEvent)
        case .permissionDenied(let tool, let reason):
            try container.encode("permission_denied", forKey: .type)
            try container.encode(tool, forKey: .tool)
            try container.encode(reason, forKey: .reason)
        case .subagentStart(let id, let agentType, let parentSessionId):
            try container.encode("subagent_start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(agentType, forKey: .agentType)
            try container.encode(parentSessionId, forKey: .parentSessionId)
        case .subagentStop(let id, let agentType):
            try container.encode("subagent_stop", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(agentType, forKey: .agentType)
        case .taskCreated(let id, let title):
            try container.encode("task_created", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
        case .taskCompleted(let id):
            try container.encode("task_completed", forKey: .type)
            try container.encode(id, forKey: .id)
        case .compactionStarted:
            try container.encode("compaction_started", forKey: .type)
        case .compactionComplete:
            try container.encode("compaction_complete", forKey: .type)
        case .worktreeCreated(let name, let branch):
            try container.encode("worktree_created", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(branch, forKey: .branch)
        case .worktreeRemoved(let path):
            try container.encode("worktree_removed", forKey: .type)
            try container.encode(path, forKey: .path)
        case .notification(let type, let message):
            try container.encode("notification", forKey: .type)
            try container.encode(type, forKey: .notificationType)
            try container.encode(message, forKey: .message)
        case .statusBadge(let text, let kind):
            try container.encode("status_badge", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(kind, forKey: .kind)
        case .sessionError(let reason):
            try container.encode("session_error", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .turnStop(let cost, let inputTokens, let outputTokens, let effortLevel):
            try container.encode("turn_stop", forKey: .type)
            try container.encodeIfPresent(cost, forKey: .cost)
            try container.encodeIfPresent(inputTokens, forKey: .inputTokens)
            try container.encodeIfPresent(outputTokens, forKey: .outputTokens)
            try container.encodeIfPresent(effortLevel, forKey: .effortLevel)
        case .elicitation(let server, let fields):
            try container.encode("elicitation", forKey: .type)
            try container.encode(server, forKey: .server)
            try container.encode(fields, forKey: .fields)
        case .rawTerminalBytes(let data):
            try container.encode("raw_terminal_bytes", forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .data)
        }
    }
}
