// server/Sources/ClaudeCodeAdapter.swift
import Foundation
import MaverickProtocol

/// Translates Claude Code `--output-format stream-json` lines and hook payloads
/// into canonical `AgentEvent` values.
final class ClaudeCodeAdapter: AgentEventNormalizing {

    // MARK: - Stream-JSON normalization

    func normalize(streamLine: Data) -> AgentEvent? {
        guard !streamLine.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: streamLine) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }

        switch type {
        case "stream":
            // { type:"stream", event: { delta: { type:"text_delta", text:"..." } } }
            guard
                let event = obj["event"] as? [String: Any],
                let delta = event["delta"] as? [String: Any],
                (delta["type"] as? String) == "text_delta",
                let text = delta["text"] as? String
            else { return nil }
            return .tokenDelta(text: text)

        case "assistant":
            // { type:"assistant", message: { content: [ { type:"text", text:"..." } ] } }
            let text = extractAssistantText(from: obj)
            guard !text.isEmpty else { return nil }
            return .assistantMessage(text: text)

        case "result":
            // { type:"result", total_cost_usd: 0.001, total_input_tokens: 100, total_output_tokens: 50 }
            let cost = obj["total_cost_usd"] as? Double
            let inputTokens = obj["total_input_tokens"] as? Int
            let outputTokens = obj["total_output_tokens"] as? Int
            return .turnStop(cost: cost, inputTokens: inputTokens, outputTokens: outputTokens, effortLevel: nil)

        case "user":
            // { type:"user", message: { content: [ { type:"text", text:"..." } ] } }
            let text = extractUserText(from: obj)
            guard !text.isEmpty else { return nil }
            return .userMessage(text: text)

        default:
            return nil
        }
    }

    // MARK: - Hook payload normalization

    func normalize(hookPayload: [String: Any]) -> AgentEvent? {
        guard let hookEventName = hookPayload["hook_event_name"] as? String else { return nil }

        switch hookEventName {
        case "PreToolUse":
            let toolName = hookPayload["tool_name"] as? String ?? ""
            let toolUseId = hookPayload["tool_use_id"] as? String ?? UUID().uuidString
            let toolInput = hookPayload["tool_input"] as? [String: Any]
            let effortDict = hookPayload["effort"] as? [String: Any]
            let event = ToolCallEvent(
                id: toolUseId,
                tool: toolKind(from: toolName),
                inputSummary: summarizeInput(toolInput),
                result: nil,
                error: nil,
                durationMs: nil,
                fileDiffs: nil,
                effort: effortLevel(from: effortDict)
            )
            return .toolCallStart(event)

        case "PostToolUse":
            let toolName = hookPayload["tool_name"] as? String ?? ""
            let toolUseId = hookPayload["tool_use_id"] as? String ?? UUID().uuidString
            let toolInput = hookPayload["tool_input"] as? [String: Any]
            let toolResult = hookPayload["tool_result"] as? String
            let durationMs = hookPayload["duration_ms"] as? Int
            let effortDict = hookPayload["effort"] as? [String: Any]
            let event = ToolCallEvent(
                id: toolUseId,
                tool: toolKind(from: toolName),
                inputSummary: summarizeInput(toolInput),
                result: toolResult,
                error: nil,
                durationMs: durationMs,
                fileDiffs: parseDiffs(toolName, toolResult),
                effort: effortLevel(from: effortDict)
            )
            return .toolCallComplete(event)

        case "PostToolUseFailure":
            let toolName = hookPayload["tool_name"] as? String ?? ""
            let toolUseId = hookPayload["tool_use_id"] as? String ?? UUID().uuidString
            let toolInput = hookPayload["tool_input"] as? [String: Any]
            let toolError = hookPayload["tool_error"] as? String
            let event = ToolCallEvent(
                id: toolUseId,
                tool: toolKind(from: toolName),
                inputSummary: summarizeInput(toolInput),
                result: nil,
                error: toolError,
                durationMs: nil,
                fileDiffs: nil,
                effort: nil
            )
            return .toolCallFailed(event)

        case "PostToolBatch":
            guard let toolCallsArr = hookPayload["tool_calls"] as? [[String: Any]] else {
                return .toolBatchComplete([])
            }
            let events = toolCallsArr.map { call -> ToolCallEvent in
                let toolName = call["tool_name"] as? String ?? ""
                let toolUseId = call["tool_use_id"] as? String ?? UUID().uuidString
                let toolInput = call["tool_input"] as? [String: Any]
                let toolResult = call["tool_result"] as? String
                let durationMs = call["duration_ms"] as? Int
                let effortDict = call["effort"] as? [String: Any]
                return ToolCallEvent(
                    id: toolUseId,
                    tool: toolKind(from: toolName),
                    inputSummary: summarizeInput(toolInput),
                    result: toolResult,
                    error: nil,
                    durationMs: durationMs,
                    fileDiffs: parseDiffs(toolName, toolResult),
                    effort: effortLevel(from: effortDict)
                )
            }
            return .toolBatchComplete(events)

        case "PermissionRequest":
            let requestId = hookPayload["request_id"] as? String ?? UUID().uuidString
            let toolName = hookPayload["tool_name"] as? String ?? ""
            let toolInput = hookPayload["tool_input"] as? [String: Any]
            let ruleMatched = hookPayload["rule_matched"] as? String
            let permEvent = PermissionEvent(
                requestId: requestId,
                tool: toolName,
                inputSummary: summarizeInput(toolInput),
                ruleMatched: ruleMatched
            )
            return .permissionRequest(permEvent)

        case "PermissionDenied":
            let toolName = hookPayload["tool_name"] as? String ?? ""
            let denialReason = hookPayload["denial_reason"] as? String ?? ""
            return .permissionDenied(tool: toolName, reason: denialReason)

        case "Stop":
            return .turnStop(cost: nil, inputTokens: nil, outputTokens: nil, effortLevel: nil)

        case "SubagentStart":
            let agentId = hookPayload["agent_id"] as? String ?? UUID().uuidString
            let agentType = hookPayload["agent_type"] as? String ?? ""
            let parentSessionId = hookPayload["parent_session_id"] as? String ?? ""
            return .subagentStart(id: agentId, agentType: agentType, parentSessionId: parentSessionId)

        case "SubagentStop":
            let agentId = hookPayload["agent_id"] as? String ?? UUID().uuidString
            let agentType = hookPayload["agent_type"] as? String ?? ""
            return .subagentStop(id: agentId, agentType: agentType)

        case "SessionStart":
            let sessionId = hookPayload["session_id"] as? String ?? UUID().uuidString
            let cwd = hookPayload["cwd"] as? String ?? ""
            let model = hookPayload["model"] as? String
            let sourceRaw = hookPayload["source"] as? String ?? "startup"
            let source = SessionSource(rawValue: sourceRaw) ?? .startup
            return .sessionStart(
                id: sessionId,
                provider: .claudeCode,
                cwd: cwd,
                model: model,
                source: source
            )

        case "Notification":
            let message = hookPayload["message"] as? String ?? ""
            return .notification(type: .permissionPrompt, message: message)

        case "TaskCreated":
            let taskId = hookPayload["task_id"] as? String ?? UUID().uuidString
            let taskTitle = hookPayload["task_title"] as? String ?? ""
            return .taskCreated(id: taskId, title: taskTitle)

        case "TaskCompleted":
            let taskId = hookPayload["task_id"] as? String ?? UUID().uuidString
            return .taskCompleted(id: taskId)

        case "PreCompact":
            return .compactionStarted

        case "PostCompact":
            return .compactionComplete

        case "WorktreeCreate":
            let worktreeName = hookPayload["worktree_name"] as? String ?? ""
            let baseBranch = hookPayload["base_branch"] as? String ?? ""
            return .worktreeCreated(name: worktreeName, branch: baseBranch)

        case "CwdChanged":
            let from = hookPayload["previous_cwd"] as? String ?? ""
            let to = hookPayload["cwd"] as? String ?? ""
            return .cwdChanged(from: from, to: to)

        case "StopFailure":
            let failureType = hookPayload["failure_type"] as? String ?? ""
            let reason = mapFailureType(failureType)
            return .sessionError(reason)

        default:
            return nil
        }
    }

    // MARK: - Private helpers

    /// Extract concatenated text from an assistant message's content array.
    private func extractAssistantText(from obj: [String: Any]) -> String {
        // Claude Code stream-json assistant: { message: { content: [ {type:"text", text:"..."} ] } }
        if let message = obj["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            return content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()
        }
        // Fallback: direct content array on root
        if let content = obj["content"] as? [[String: Any]] {
            return content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()
        }
        return ""
    }

    /// Extract text from a user turn message.
    private func extractUserText(from obj: [String: Any]) -> String {
        // { type:"user", message: { content: [ {type:"text", text:"..."} ] } }
        if let message = obj["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            return content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()
        }
        // Plain string content
        if let message = obj["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
        }
        return ""
    }

    /// Map a Claude Code tool name string → ToolKind.
    private func toolKind(from name: String) -> ToolKind {
        // Normalize: "Read" → "read", "Bash" → "bash", etc.
        let lower = name.lowercased()
        switch lower {
        case "read": return .read
        case "write": return .write
        case "edit", "multiedit": return .edit
        case "notebookedit": return .notebookEdit
        case "glob": return .glob
        case "grep": return .grep
        case "lsp": return .lsp
        case "bash": return .bash
        case "powershell": return .powerShell
        case "monitor": return .monitor
        case "webfetch": return .webFetch
        case "websearch": return .webSearch
        case "agent": return .agent
        case "skill": return .skill
        case "sendmessage": return .sendMessage
        case "taskcreate": return .taskCreate
        case "taskupdate": return .taskUpdate
        case "taskget": return .taskGet
        case "tasklist": return .taskList
        case "taskstop": return .taskStop
        case "croncreate": return .cronCreate
        case "crondelete": return .cronDelete
        case "cronlist": return .cronList
        case "enterplanmode": return .enterPlanMode
        case "exitplanmode": return .exitPlanMode
        case "askuserquestion": return .askUserQuestion
        case "enterworktree": return .enterWorktree
        case "exitworktree": return .exitWorktree
        case "listmcpresources": return .listMcpResources
        case "readmcpresource": return .readMcpResource
        case "waitformcpservers": return .waitForMcpServers
        case "toolsearch": return .toolSearch
        case "pushnotification": return .pushNotification
        case "schedulewakeup": return .scheduleWakeup
        case "remotetrigger": return .remoteTrigger
        case "shareonboardingguide": return .shareOnboardingGuide
        default: return .custom(name)
        }
    }

    /// Build a human-readable 1-line summary of tool_input dict.
    private func summarizeInput(_ input: [String: Any]?) -> String {
        guard let input else { return "" }

        // Common key patterns ordered by priority.
        if let cmd = input["command"] as? String {
            // Bash: truncate long commands
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(120))
        }
        if let path = input["path"] as? String {
            return path
        }
        if let filePath = input["file_path"] as? String {
            return filePath
        }
        if let query = input["query"] as? String {
            return query
        }
        if let url = input["url"] as? String {
            return url
        }
        if let prompt = input["prompt"] as? String {
            return String(prompt.prefix(120))
        }
        if let content = input["content"] as? String {
            return String(content.prefix(80))
        }
        // Generic fallback: first string value found
        for (_, value) in input {
            if let str = value as? String {
                return String(str.prefix(120))
            }
        }
        return ""
    }

    /// Parse file diffs from a Write/Edit tool result string.
    /// Deferred: Claude Code's PostToolUse result for Edit is typically a
    /// success message without embedded diff stats; returning nil here until
    /// a git-diff-based enhancement is implemented.
    private func parseDiffs(_ toolName: String, _ result: String?) -> [FileDiff]? {
        return nil
    }

    /// Map effort dict → EffortLevel?
    private func effortLevel(from effort: [String: Any]?) -> EffortLevel? {
        guard let effort,
              let levelStr = effort["level"] as? String
        else { return nil }
        return EffortLevel(rawValue: levelStr)
    }

    /// Map Claude Code StopFailure `failure_type` string → StopFailureReason.
    private func mapFailureType(_ failureType: String) -> StopFailureReason {
        switch failureType.lowercased() {
        case "rate_limit", "ratelimit": return .rateLimit
        case "auth_failed", "authfailed", "unauthorized": return .authFailed
        case "billing": return .billing
        case "server_error", "servererror": return .serverError
        case "max_tokens", "maxtokens": return .maxTokens
        default: return .unknown
        }
    }
}
