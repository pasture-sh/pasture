import SwiftUI

struct EnvironmentPalette {
    let skyTop: Color
    let skyBottom: Color
    let farLayer: Color
    let midLayer: Color
    let nearLayer: Color
    let accent: Color
    let userBubble: Color
}

enum ModelEnvironment: String, CaseIterable, Identifiable {
    case pasture
    case mesa
    case alpine
    case grove
    case bloom
    case tundra
    case dusk

    var id: String { rawValue }

    var palette: EnvironmentPalette {
        switch self {
        case .pasture:
            return EnvironmentPalette(
                skyTop: Color(red: 0.62, green: 0.79, blue: 0.50),
                skyBottom: Color(red: 0.46, green: 0.68, blue: 0.37),
                farLayer: Color(red: 0.71, green: 0.82, blue: 0.57).opacity(0.55),
                midLayer: Color(red: 0.53, green: 0.74, blue: 0.41).opacity(0.72),
                nearLayer: Color(red: 0.37, green: 0.57, blue: 0.29).opacity(0.9),
                accent: Color(red: 0.95, green: 0.79, blue: 0.38),
                userBubble: Color(red: 0.29, green: 0.52, blue: 0.26)
            )

        case .mesa:
            return EnvironmentPalette(
                skyTop: Color(red: 0.89, green: 0.57, blue: 0.36),
                skyBottom: Color(red: 0.75, green: 0.42, blue: 0.27),
                farLayer: Color(red: 0.92, green: 0.70, blue: 0.52).opacity(0.5),
                midLayer: Color(red: 0.75, green: 0.41, blue: 0.28).opacity(0.75),
                nearLayer: Color(red: 0.54, green: 0.27, blue: 0.20).opacity(0.92),
                accent: Color(red: 0.98, green: 0.73, blue: 0.34),
                userBubble: Color(red: 0.69, green: 0.31, blue: 0.22)
            )

        case .alpine:
            return EnvironmentPalette(
                skyTop: Color(red: 0.45, green: 0.57, blue: 0.70),
                skyBottom: Color(red: 0.31, green: 0.42, blue: 0.56),
                farLayer: Color(red: 0.78, green: 0.84, blue: 0.90).opacity(0.45),
                midLayer: Color(red: 0.47, green: 0.58, blue: 0.68).opacity(0.72),
                nearLayer: Color(red: 0.28, green: 0.35, blue: 0.47).opacity(0.92),
                accent: Color(red: 0.86, green: 0.92, blue: 0.98),
                userBubble: Color(red: 0.36, green: 0.47, blue: 0.62)
            )

        case .grove:
            return EnvironmentPalette(
                skyTop: Color(red: 0.18, green: 0.33, blue: 0.23),
                skyBottom: Color(red: 0.12, green: 0.23, blue: 0.17),
                farLayer: Color(red: 0.25, green: 0.45, blue: 0.31).opacity(0.42),
                midLayer: Color(red: 0.16, green: 0.32, blue: 0.22).opacity(0.75),
                nearLayer: Color(red: 0.09, green: 0.20, blue: 0.14).opacity(0.92),
                accent: Color(red: 0.51, green: 0.79, blue: 0.56),
                userBubble: Color(red: 0.15, green: 0.39, blue: 0.24)
            )

        case .bloom:
            return EnvironmentPalette(
                skyTop: Color(red: 0.95, green: 0.78, blue: 0.79),
                skyBottom: Color(red: 0.87, green: 0.71, blue: 0.70),
                farLayer: Color(red: 0.93, green: 0.86, blue: 0.78).opacity(0.45),
                midLayer: Color(red: 0.83, green: 0.74, blue: 0.68).opacity(0.72),
                nearLayer: Color(red: 0.69, green: 0.61, blue: 0.53).opacity(0.9),
                accent: Color(red: 0.77, green: 0.53, blue: 0.65),
                userBubble: Color(red: 0.74, green: 0.49, blue: 0.60)
            )

        case .tundra:
            return EnvironmentPalette(
                skyTop: Color(red: 0.86, green: 0.89, blue: 0.95),
                skyBottom: Color(red: 0.73, green: 0.77, blue: 0.87),
                farLayer: Color(red: 0.92, green: 0.94, blue: 0.98).opacity(0.52),
                midLayer: Color(red: 0.76, green: 0.80, blue: 0.89).opacity(0.75),
                nearLayer: Color(red: 0.60, green: 0.66, blue: 0.79).opacity(0.9),
                accent: Color(red: 0.81, green: 0.82, blue: 0.94),
                userBubble: Color(red: 0.55, green: 0.60, blue: 0.77)
            )

        case .dusk:
            return EnvironmentPalette(
                skyTop: Color(red: 0.20, green: 0.23, blue: 0.42),
                skyBottom: Color(red: 0.14, green: 0.16, blue: 0.31),
                farLayer: Color(red: 0.48, green: 0.37, blue: 0.34).opacity(0.38),
                midLayer: Color(red: 0.26, green: 0.24, blue: 0.35).opacity(0.72),
                nearLayer: Color(red: 0.14, green: 0.15, blue: 0.23).opacity(0.92),
                accent: Color(red: 0.98, green: 0.71, blue: 0.33),
                userBubble: Color(red: 0.46, green: 0.37, blue: 0.63)
            )
        }
    }

    static func forModelName(_ modelName: String?) -> ModelEnvironment {
        guard let normalized = modelName?.lowercased() else {
            return .pasture
        }

        if normalized.contains("coder") || normalized.contains("codellama") {
            return .grove
        }
        if normalized.contains("llama") {
            return .mesa
        }
        if normalized.contains("mistral") || normalized.contains("mixtral") {
            return .alpine
        }
        if normalized.contains("gemma") {
            return .bloom
        }
        if normalized.contains("phi") {
            return .tundra
        }
        if normalized.contains("deepseek") {
            return .dusk
        }

        return .pasture
    }
}
