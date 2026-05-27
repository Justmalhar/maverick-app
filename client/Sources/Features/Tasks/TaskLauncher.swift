// client/Sources/Features/Tasks/TaskLauncher.swift
import Foundation
import Observation
import MaverickProtocol

/// Coordinates the "user composed a task" flow:
///   1. Compose: enqueue a pending launch (session name + binary + task body)
///   2. Server replies `sessionCreated` for the matching name
///   3. Send the binary + newline (opens the interactive CLI inside the shell)
///   4. After the CLI is up, send the task body + newline (this is what the
///      user "types" into the agent's chat box — no `-p` / one-shot flags)
///   5. Publish `launchedSessionId` so the UI can navigate
///
/// The two-step pattern (instead of `claude -p "task"`) keeps the agent in
/// interactive mode, which providers like Anthropic and OpenAI bill differently
/// — usually cheaper or covered by an existing seat.
@Observable
final class TaskLauncher {
    var launchedSessionId: UUID?

    struct Pending {
        let binary: String
        let task: String
    }
    private var pending: [String: Pending] = [:]

    func enqueue(sessionName: String, binary: String, task: String) {
        pending[sessionName] = Pending(binary: binary, task: task)
    }

    func handle(_ message: ServerMessage, connection: ConnectionManager) {
        guard case .sessionCreated(let info) = message else { return }
        guard let p = pending.removeValue(forKey: info.name) else { return }

        // Step 1: launch the CLI inside the freshly-opened shell.
        // Wait a beat so zsh has rendered its prompt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.sendLine(p.binary, sessionId: info.id, connection: connection)
        }

        // Step 2: paste the task body and submit. We give the CLI 1.5s to
        // initialize and show its input box before we type. For most agents
        // this is enough; we can make this configurable later if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if !p.task.isEmpty {
                Self.sendLine(p.task, sessionId: info.id, connection: connection)
            }
            self?.launchedSessionId = info.id
        }
    }

    private static func sendLine(_ line: String, sessionId: UUID, connection: ConnectionManager) {
        let bytes = Data((line + "\n").utf8)
        connection.send(.input(sessionId: sessionId, data: bytes.base64EncodedString()))
    }
}
