import Foundation

public struct ModelDownloadState: Equatable, Sendable {
    public let modelID: String
    public let displayName: String
    public let status: String
    public let fraction: Double?

    public init(modelID: String, displayName: String, status: String, fraction: Double?) {
        self.modelID = modelID
        self.displayName = displayName
        self.status = status
        self.fraction = fraction
    }

    public func updating(with progress: PullProgress) -> ModelDownloadState {
        ModelDownloadState(
            modelID: modelID,
            displayName: displayName,
            status: progress.status.capitalized,
            fraction: progress.total == nil ? nil : progress.fraction
        )
    }
}

public struct CuratedModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let sizeLabel: String
    public let tags: [String]

    public init(id: String, displayName: String, description: String, sizeLabel: String, tags: [String]) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.sizeLabel = sizeLabel
        self.tags = tags
    }
}
