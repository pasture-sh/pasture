import Foundation

enum ChatIntent: String, CaseIterable, Identifiable, Sendable {
    case writing
    case coding
    case research
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .writing: "Writing"
        case .coding: "Coding"
        case .research: "Research"
        case .chat: "Just chatting"
        }
    }

    var subtitle: String {
        switch self {
        case .writing: "Draft and refine text quickly."
        case .coding: "Build and debug software."
        case .research: "Analyze and synthesize information."
        case .chat: "Have natural everyday conversations."
        }
    }

    var icon: String {
        switch self {
        case .writing: "pencil.and.outline"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .research: "magnifyingglass"
        case .chat: "bubble.left.and.bubble.right.fill"
        }
    }
}
