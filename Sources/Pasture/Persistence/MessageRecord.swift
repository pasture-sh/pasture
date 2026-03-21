import Foundation
import SwiftData

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var createdAt: Date
    var conversation: ConversationRecord?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        createdAt: Date = .now,
        conversation: ConversationRecord? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.conversation = conversation
    }
}
