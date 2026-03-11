import Foundation
import SwiftData

@Model
final class ConversationHistoryRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var selectedModelName: String?
    var selectedIntentRawValue: String?
    var payload: Data

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        selectedModelName: String? = nil,
        selectedIntentRawValue: String? = nil,
        payload: Data = Data()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.selectedModelName = selectedModelName
        self.selectedIntentRawValue = selectedIntentRawValue
        self.payload = payload
    }
}

struct PersistedConversationMessage: Codable {
    let role: String
    let content: String

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
