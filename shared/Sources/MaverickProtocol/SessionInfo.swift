import Foundation

public struct SessionInfo: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let shell: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, shell: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.shell = shell
        self.createdAt = createdAt
    }
}
