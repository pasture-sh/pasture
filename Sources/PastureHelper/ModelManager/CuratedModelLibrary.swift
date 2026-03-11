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
            id: "llama3.1:8b",
            displayName: "Llama 3.1 8B",
            description: "Stronger quality for writing and everyday use.",
            sizeLabel: "Medium",
            tags: ["Capable", "General"]
        ),
        CuratedModel(
            id: "mistral:7b",
            displayName: "Mistral 7B",
            description: "Reliable writing and analysis quality.",
            sizeLabel: "Medium",
            tags: ["Writing", "Capable"]
        ),
        CuratedModel(
            id: "qwen2.5:7b",
            displayName: "Qwen 2.5",
            description: "Balanced responses with strong reasoning.",
            sizeLabel: "Medium",
            tags: ["Reasoning", "General"]
        ),
        CuratedModel(
            id: "qwen2.5-coder:7b",
            displayName: "Qwen Coder",
            description: "Excellent first pick for coding tasks.",
            sizeLabel: "Medium",
            tags: ["Coding", "Fast"]
        ),
        CuratedModel(
            id: "deepseek-coder:6.7b",
            displayName: "DeepSeek Coder",
            description: "Strong code generation and debugging.",
            sizeLabel: "Medium",
            tags: ["Coding", "Capable"]
        ),
        CuratedModel(
            id: "gemma2:2b",
            displayName: "Gemma 2",
            description: "Friendly model for lightweight everyday tasks.",
            sizeLabel: "Small",
            tags: ["Friendly", "Lightweight"]
        ),
        CuratedModel(
            id: "phi3:mini",
            displayName: "Phi 3 Mini",
            description: "Compact and quick for short interactions.",
            sizeLabel: "Small",
            tags: ["Fast", "Lightweight"]
        )
    ]
}
