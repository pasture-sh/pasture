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
        guard let raw = sorted.last(where: { $0.role == MessageRole.assistant.rawValue })?.content
            ?? sorted.first(where: { $0.role == MessageRole.user.rawValue })?.content
        else { return nil }
        return raw.strippingMarkdown
    }
}

extension String {
    var strippingMarkdown: String {
        var s = self
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: "…", options: .regularExpression)
        s = s.replacingOccurrences(of: "`[^`\n]+`", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*\\*([^*]+)\\*\\*\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*([^*\n]+)\\*\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*([^*\n]+)\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "__([^_\n]+)__", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "_([^_\n]+)_", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        s = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
