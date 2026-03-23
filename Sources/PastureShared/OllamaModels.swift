import Foundation

public struct OllamaModel: Codable, Identifiable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let size: Int64?
    public let details: ModelDetails?

    public init(name: String, size: Int64?, details: ModelDetails?) {
        self.name = name
        self.size = size
        self.details = details
    }

    public func matches(_ curatedModel: CuratedModel) -> Bool {
        name == curatedModel.id || name.hasPrefix("\(curatedModel.id):")
    }

    public struct ModelDetails: Codable, Sendable, Hashable {
        public let family: String?
        public let parameterSize: String?

        public init(family: String?, parameterSize: String?) {
            self.family = family
            self.parameterSize = parameterSize
        }

        enum CodingKeys: String, CodingKey {
            case family
            case parameterSize = "parameter_size"
        }
    }
}

public struct ChatMessage: Codable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct PullProgress: Codable, Sendable {
    public let status: String
    public let total: Int64?
    public let completed: Int64?
    public let error: String?

    public init(status: String, total: Int64?, completed: Int64?, error: String? = nil) {
        self.status = status
        self.total = total
        self.completed = completed
        self.error = error
    }

    public var fraction: Double {
        guard let total, let completed, total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var isComplete: Bool { status == "success" }
}
