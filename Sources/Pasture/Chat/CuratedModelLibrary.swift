import Foundation

struct CuratedModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let sizeLabel: String
    let tags: [String]
}

enum CuratedModelLibrary {
    static let recommended: [CuratedModel] = [
        CuratedModel(
            id: "llama3.2:3b",
            displayName: "Llama 3.2",
            description: "Great all-around model by Meta.",
            sizeLabel: "Small",
            tags: ["Fast", "General"]
        ),
        CuratedModel(
            id: "qwen2.5:3b",
            displayName: "Qwen 2.5",
            description: "Balanced responses with strong reasoning.",
            sizeLabel: "Small",
            tags: ["Capable", "General"]
        ),
        CuratedModel(
            id: "mistral:7b",
            displayName: "Mistral 7B",
            description: "Reliable writing and analysis quality.",
            sizeLabel: "Medium",
            tags: ["Capable", "Writing"]
        ),
        CuratedModel(
            id: "qwen2.5-coder:7b",
            displayName: "Qwen Coder",
            description: "Best first pick for coding tasks.",
            sizeLabel: "Medium",
            tags: ["Coding", "Fast"]
        ),
        CuratedModel(
            id: "gemma2:2b",
            displayName: "Gemma 2",
            description: "Friendly model for everyday tasks.",
            sizeLabel: "Small",
            tags: ["Friendly", "General"]
        ),
        CuratedModel(
            id: "phi3:mini",
            displayName: "Phi 3 Mini",
            description: "Compact and surprisingly strong on-device.",
            sizeLabel: "Small",
            tags: ["Fast", "Lightweight"]
        ),
    ]
}
