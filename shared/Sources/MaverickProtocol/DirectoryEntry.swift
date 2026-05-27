// shared/Sources/MaverickProtocol/DirectoryEntry.swift
import Foundation

public struct DirectoryEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    public let isDirectory: Bool
    public let isHidden: Bool

    public var id: String { name }

    public init(name: String, isDirectory: Bool, isHidden: Bool) {
        self.name = name
        self.isDirectory = isDirectory
        self.isHidden = isHidden
    }
}
