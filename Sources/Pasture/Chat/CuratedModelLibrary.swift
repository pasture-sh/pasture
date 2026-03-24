import Foundation
import PastureShared

// NOTE(v2): Replace this hardcoded list with a remotely-fetched config so model names,
// sizes, and tags stay current as Ollama releases new versions.
enum CuratedModelLibrary {
    static let recommended: [CuratedModel] = [
        CuratedModel(
            id: "gemma2:2b",
            displayName: "Gemma 2",
            description: "Friendly model for everyday tasks.",
            sizeLabel: "~1.6 GB",
            tags: ["Friendly", "General"]
        ),
        CuratedModel(
            id: "qwen2.5:3b",
            displayName: "Qwen 2.5",
            description: "Balanced responses with strong reasoning.",
            sizeLabel: "~1.9 GB",
            tags: ["Capable", "General"]
        ),
        CuratedModel(
            id: "llama3.2:3b",
            displayName: "Llama 3.2",
            description: "Great all-around model by Meta.",
            sizeLabel: "~2.0 GB",
            tags: ["Fast", "General"]
        ),
        CuratedModel(
            id: "phi3:mini",
            displayName: "Phi 3 Mini",
            description: "Compact and surprisingly strong on-device.",
            sizeLabel: "~2.2 GB",
            tags: ["Fast", "Lightweight"]
        ),
        CuratedModel(
            id: "mistral:7b",
            displayName: "Mistral 7B",
            description: "Reliable writing and analysis quality.",
            sizeLabel: "~4.1 GB",
            tags: ["Capable", "Writing"]
        ),
        CuratedModel(
            id: "qwen2.5-coder:7b",
            displayName: "Qwen Coder",
            description: "Best first pick for coding tasks.",
            sizeLabel: "~4.7 GB",
            tags: ["Coding", "Fast"]
        ),
    ]
}
