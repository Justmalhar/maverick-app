import Foundation

public struct SessionInfo: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let shell: String
    public let createdAt: Date

    /// Non-nil for agent-backed sessions; nil for raw PTY sessions.
    public var agentProvider: AgentProvider?
    /// Non-nil for agent-backed sessions; nil for raw PTY sessions.
    public var sessionMode: SessionMode?

    public init(
        id: UUID = UUID(),
        name: String,
        shell: String,
        createdAt: Date = Date(),
        agentProvider: AgentProvider? = nil,
        sessionMode: SessionMode? = nil
    ) {
        self.id = id
        self.name = name
        self.shell = shell
        self.createdAt = createdAt
        self.agentProvider = agentProvider
        self.sessionMode = sessionMode
    }
}
