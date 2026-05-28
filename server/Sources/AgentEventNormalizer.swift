// server/Sources/AgentEventNormalizer.swift
import Foundation
import MaverickProtocol

/// Conforming types translate provider-specific wire formats into canonical `AgentEvent` values.
protocol AgentEventNormalizing {
    /// Normalize one line of `--output-format stream-json` stdout output.
    /// Returns `nil` if the line should be ignored.
    func normalize(streamLine: Data) -> AgentEvent?

    /// Normalize one hook POST payload (already decoded from JSON).
    /// Returns `nil` if the hook event should be ignored.
    /// `requestId` is only non-nil for PermissionRequest hooks.
    func normalize(hookPayload: [String: Any]) -> AgentEvent?
}
