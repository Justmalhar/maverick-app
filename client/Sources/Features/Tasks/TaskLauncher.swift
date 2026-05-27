// client/Sources/Features/Tasks/TaskLauncher.swift
import Foundation
import Observation
import MaverickProtocol

/// Bridges "user composed a task" → "session created on the Mac" → "send the
/// agent command as the first input line" → "navigate the UI to that session".
///
/// We enqueue the desired session name + command before sending `createSession`.
/// When the server replies with `sessionCreated` for that name, we send the
/// command as input (with a short delay so the shell has rendered its prompt).
/// The `launchedSessionId` becomes the trigger for UI navigation.
@Observable
final class TaskLauncher {
    /// Most-recently-launched session id; SessionsListView observes this and
    /// pushes the terminal screen. Caller should reset it back to nil after consuming.
    var launchedSessionId: UUID?

    /// sessionName → command-to-send
    private var pending: [String: String] = [:]

    func enqueue(sessionName: String, command: String) {
        pending[sessionName] = command
    }

    func handle(_ message: ServerMessage, connection: ConnectionManager) {
        guard case .sessionCreated(let info) = message else { return }
        guard let command = pending.removeValue(forKey: info.name) else { return }
        // Give zsh a moment to print its prompt before typing the agent command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let bytes = Data((command + "\n").utf8)
            connection.send(.input(sessionId: info.id, data: bytes.base64EncodedString()))
            self.launchedSessionId = info.id
        }
    }
}
