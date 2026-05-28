// server/Sources/AgentEventNormalizer.swift
import Foundation
import MaverickProtocol

/// Conforming types translate provider-specific wire formats into canonical `AgentEvent` values.
protocol AgentEventNormalizing {
    /// Normalize one line of `--output-format stream-json` stdout output.
    /// Returns zero or more events; most lines produce exactly one.
    /// Returning multiple events (e.g., toolCallStart + statusBadge) is explicitly supported.
    func normalize(streamLine: Data) -> [AgentEvent]

    /// Normalize one hook POST payload (already decoded from JSON).
    /// Returns zero or more events.
    func normalize(hookPayload: [String: Any]) -> [AgentEvent]
}
