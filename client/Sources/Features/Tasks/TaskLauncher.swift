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
/// In RESUME mode (e.g. tapping a Previous row), step 4 is skipped and the
/// binary is invoked with its `resumeFlag` (claude -c, codex --resume) so the
/// CLI rehydrates the prior conversation from its own on-disk session store.
@Observable
final class TaskLauncher {
    var launchedSessionId: UUID?

    /// Callback invoked once a queued task lands and the CLI is dispatched.
    /// Hosted in the app entry point so SessionHistory can record (agent, cwd).
    var onLaunched: ((_ sessionId: UUID, _ agent: CodingAgent, _ cwd: String?) -> Void)?

    struct Pending {
        let binary: String
        let task: String?      // nil = resume mode, no body to paste
        let agent: CodingAgent
        let cwd: String?
        let resume: Bool
    }
    private var pending: [String: Pending] = [:]

    func enqueue(
        sessionName: String,
        binary: String,
        task: String?,
        agent: CodingAgent,
        cwd: String?,
        resume: Bool = false
    ) {
        pending[sessionName] = Pending(
            binary: binary,
            task: task,
            agent: agent,
            cwd: cwd,
            resume: resume
        )
    }

    func handle(_ message: ServerMessage, connection: ConnectionManager) {
        guard case .sessionCreated(let info) = message else { return }
        guard let p = pending.removeValue(forKey: info.name) else { return }

        let launchLine: String = {
            if p.resume, let flag = p.agent.resumeFlag {
                return "\(p.binary) \(flag)"
            }
            return p.binary
        }()

        // Step 1: launch the CLI inside the freshly-opened shell. Wait a beat
        // so zsh has rendered its prompt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.sendLine(launchLine, sessionId: info.id, connection: connection)
        }

        // Step 2: paste the task body and submit (skipped in resume mode).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if !p.resume, let body = p.task, !body.isEmpty {
                Self.sendLine(body, sessionId: info.id, connection: connection)
            }
            self?.launchedSessionId = info.id
            self?.onLaunched?(info.id, p.agent, p.cwd)
        }
    }

    private static func sendLine(_ line: String, sessionId: UUID, connection: ConnectionManager) {
        let bytes = Data((line + "\n").utf8)
        connection.send(.input(sessionId: sessionId, data: bytes.base64EncodedString()))
    }
}
