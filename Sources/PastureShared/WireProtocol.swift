import Foundation

public enum ProxyRequestType: String, Codable, Sendable {
    case tags, chat, pull, delete, cancel, backup, status
}

public enum ProxyResponseType: String, Codable, Sendable {
    case tags, chat, pull, delete, cancel, error, status
}

public struct ProxyRequest: Codable, Sendable {
    public let id: String
    public let type: ProxyRequestType
    public let model: String?
    public let messages: [ChatMessage]?
    public let targetRequestID: String?
    public let payload: String?

    public init(
        id: String,
        type: ProxyRequestType,
        model: String? = nil,
        messages: [ChatMessage]? = nil,
        targetRequestID: String? = nil,
        payload: String? = nil
    ) {
        self.id = id
        self.type = type
        self.model = model
        self.messages = messages
        self.targetRequestID = targetRequestID
        self.payload = payload
    }

    public static func cancelRequest(targetRequestID: String) -> ProxyRequest {
        ProxyRequest(
            id: UUID().uuidString,
            type: .cancel,
            targetRequestID: targetRequestID
        )
    }
}

public struct OllamaStatus: Codable, Sendable, Equatable {
    public let isReachable: Bool
    public let version: String?

    public init(isReachable: Bool, version: String? = nil) {
        self.isReachable = isReachable
        self.version = version
    }
}

public struct ProxyResponse: Codable, Sendable {
    public let id: String
    public let type: ProxyResponseType
    public var models: [OllamaModel]?
    public var token: String?
    public var pullProgress: PullProgress?
    public var errorMessage: String?
    public var ollamaStatus: OllamaStatus?
    public var done: Bool

    public init(
        id: String,
        type: ProxyResponseType,
        models: [OllamaModel]? = nil,
        token: String? = nil,
        pullProgress: PullProgress? = nil,
        errorMessage: String? = nil,
        ollamaStatus: OllamaStatus? = nil,
        done: Bool
    ) {
        self.id = id
        self.type = type
        self.models = models
        self.token = token
        self.pullProgress = pullProgress
        self.errorMessage = errorMessage
        self.ollamaStatus = ollamaStatus
        self.done = done
    }
}
