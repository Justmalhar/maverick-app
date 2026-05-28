// server/Sources/AgentEventBroadcaster.swift
import Foundation
import MaverickProtocol

/// Merges `AgentEvent`s arriving from two sources — direct `AgentSession` output
/// (chat mode) and `HookServer` hook POSTs (both modes) — and forwards each event
/// to the registered `onEvent` callback together with its session UUID.
///
/// No deduplication is applied at this stage; that is deferred to a later
/// enhancement if needed.
final class AgentEventBroadcaster {

    /// Called for every normalized event received from either source.
    /// Parameters: (sessionId, event)
    var onEvent: ((UUID, AgentEvent) -> Void)?

    // MARK: - From AgentSession (chat mode stdout)

    /// Called when `AgentSession` emits a normalized `AgentEvent`.
    func receive(event: AgentEvent, for sessionId: UUID) {
        onEvent?(sessionId, event)
    }

    // MARK: - From HookServer (both modes)

    /// Called when `HookServer` fires a hook-derived `AgentEvent`.
    /// `sessionIdString` is the raw `session_id` field from the hook payload;
    /// if it cannot be converted to a `UUID` the event is silently dropped.
    func receiveHook(event: AgentEvent, sessionIdString: String) {
        guard let sessionId = UUID(uuidString: sessionIdString) else {
            NSLog("[AgentEventBroadcaster] Dropping hook event — invalid session UUID: %@", sessionIdString)
            return
        }
        onEvent?(sessionId, event)
    }
}
