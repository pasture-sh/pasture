import Foundation
import SwiftData

@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String?
    var modelName: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    var messages: [MessageRecord] = []

    init(
        id: UUID = UUID(),
        title: String? = nil,
        modelName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.modelName = modelName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        title ?? "New conversation"
    }

    var sortedMessages: [MessageRecord] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var previewText: String? {
        let sorted = sortedMessages
        return sorted.last(where: { $0.role == "assistant" })?.content
            ?? sorted.first(where: { $0.role == "user" })?.content
    }
}

extension ConversationRecord: Hashable {
    static func == (lhs: ConversationRecord, rhs: ConversationRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
