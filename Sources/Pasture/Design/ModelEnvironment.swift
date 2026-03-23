import SwiftUI
import Foundation

struct EnvironmentPalette {
    let skyTop: Color
    let skyBottom: Color
    let horizonGlow: Color
    let farLayer: Color
    let midLayer: Color
    let nearLayer: Color
    let foregroundLayer: Color
    let cloudTint: Color
    let atmosphereTint: Color
    let accent: Color
    let userBubble: Color
    let primaryTextOnAccent: Color
    let layerCount: Int
}

enum TimeOfDay: String, Equatable {
    case morning
    case afternoon
    case evening
    case night

    static var current: TimeOfDay {
        from(date: Date())
    }

    static func from(date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 6..<12:
            return .morning
        case 12..<18:
            return .afternoon
        case 18..<21:
            return .evening
        default:
            return .night
        }
    }
}

enum ModelComplexity: String, Equatable {
    case small
    case medium
    case large

    var layerCount: Int {
        switch self {
        case .small: return 2
        case .medium: return 3
        case .large: return 4
        }
    }

    static func from(modelName: String?) -> ModelComplexity {
        guard let modelName else {
            return .medium
        }

        let name = modelName.lowercased()

        if let parameterSize = extractParameterBillions(from: name) {
            switch parameterSize {
            case ..<5:
                return .small
            case ..<30:
                return .medium
            default:
                return .large
            }
        }

        if name.contains("mini") || name.contains("small") {
            return .small
        }

        if name.contains("large") || name.contains("r1") {
            return .large
        }

        return .medium
    }

    private static let paramBillionsRegex = try! NSRegularExpression(pattern: "(\\d+)\\s*b", options: [.caseInsensitive])

    private static func extractParameterBillions(from modelName: String) -> Int? {
        let regex = paramBillionsRegex
        let nsRange = NSRange(modelName.startIndex..<modelName.endIndex, in: modelName)
        let matches = regex.matches(in: modelName, options: [], range: nsRange)
        guard let valueRange = matches
            .compactMap({ match -> Range<String.Index>? in
                guard match.numberOfRanges > 1 else { return nil }
                return Range(match.range(at: 1), in: modelName)
            })
            .compactMap({ Int(modelName[$0]) })
            .max()
        else {
            return nil
        }
        return valueRange
    }
}

struct ModelEnvironment: Equatable, Identifiable {
    let timeOfDay: TimeOfDay
    let complexity: ModelComplexity
    let isLateNight: Bool

    var id: String {
        "\(timeOfDay.rawValue)-\(complexity.rawValue)-\(isLateNight)"
    }

    var displayName: String {
        timeOfDay.rawValue.capitalized
    }

    var ambience: String {
        switch timeOfDay {
        case .morning:
            return "Soft warm light"
        case .afternoon:
            return "Bright open sky"
        case .evening:
            return "Golden-hour warmth"
        case .night:
            return "Quiet indigo calm"
        }
    }

    var palette: EnvironmentPalette {
        var base = Self.basePalette(for: timeOfDay, isLateNight: isLateNight)

        switch complexity {
        case .small:
            break
        case .medium:
            base.skyTop = base.skyTop.adjustedHSB(hueDegrees: -2, brightnessPercent: 1.5)
            base.skyBottom = base.skyBottom.adjustedHSB(hueDegrees: -2, brightnessPercent: 1.2)
        case .large:
            base.skyTop = base.skyTop.adjustedHSB(hueDegrees: -4, brightnessPercent: 3.0, saturationPercent: 3.0)
            base.skyBottom = base.skyBottom.adjustedHSB(hueDegrees: -4, brightnessPercent: 2.5, saturationPercent: 2.5)
            base.farLayer = base.farLayer.adjustedHSB(saturationPercent: 2.0)
            base.midLayer = base.midLayer.adjustedHSB(saturationPercent: 2.0)
            base.nearLayer = base.nearLayer.adjustedHSB(saturationPercent: 2.0)
        }

        return EnvironmentPalette(
            skyTop: base.skyTop,
            skyBottom: base.skyBottom,
            horizonGlow: base.horizonGlow,
            farLayer: base.farLayer,
            midLayer: base.midLayer,
            nearLayer: base.nearLayer,
            foregroundLayer: base.foregroundLayer,
            cloudTint: base.cloudTint,
            atmosphereTint: base.atmosphereTint,
            accent: base.accent,
            userBubble: base.userBubble,
            primaryTextOnAccent: base.primaryTextOnAccent,
            layerCount: complexity.layerCount
        )
    }

    static let onboardingDefault = ModelEnvironment(timeOfDay: .morning, complexity: .medium, isLateNight: false)

    static let pasture = onboardingDefault

    static func forModelName(_ modelName: String?) -> ModelEnvironment {
        chat(for: modelName)
    }

    static func chat(for modelName: String?, at date: Date = Date()) -> ModelEnvironment {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        return ModelEnvironment(
            timeOfDay: TimeOfDay.from(date: date, calendar: calendar),
            complexity: ModelComplexity.from(modelName: modelName),
            isLateNight: (0..<5).contains(hour)
        )
    }

    private static func basePalette(for timeOfDay: TimeOfDay, isLateNight: Bool) -> (skyTop: Color, skyBottom: Color, horizonGlow: Color, farLayer: Color, midLayer: Color, nearLayer: Color, foregroundLayer: Color, cloudTint: Color, atmosphereTint: Color, accent: Color, userBubble: Color, primaryTextOnAccent: Color) {
        switch timeOfDay {
        case .morning:
            return (
                skyTop: Color(hex: "BFD8E2"),
                skyBottom: Color(hex: "8FB5C1"),
                horizonGlow: Color(hex: "F7E8C8"),
                farLayer: Color(hex: "B8C9A7"),
                midLayer: Color(hex: "91A97D"),
                nearLayer: Color(hex: "718D63"),
                foregroundLayer: Color(hex: "5A7053"),
                cloudTint: .white.opacity(0.54),
                atmosphereTint: Color(hex: "EADAB4").opacity(0.30),
                accent: Color(hex: "D9BC7A"),
                userBubble: Color(hex: "617F67"),
                primaryTextOnAccent: Color(red: 0.19, green: 0.21, blue: 0.16)
            )
        case .afternoon:
            return (
                skyTop: Color(hex: "B3CFDA"),
                skyBottom: Color(hex: "80AAB7"),
                horizonGlow: Color(hex: "F0E3C2"),
                farLayer: Color(hex: "B7C4A2"),
                midLayer: Color(hex: "92A47D"),
                nearLayer: Color(hex: "6F8660"),
                foregroundLayer: Color(hex: "586C52"),
                cloudTint: .white.opacity(0.44),
                atmosphereTint: Color(hex: "DBD8B6").opacity(0.24),
                accent: Color(hex: "CDB77A"),
                userBubble: Color(hex: "58725E"),
                primaryTextOnAccent: Color(red: 0.18, green: 0.20, blue: 0.15)
            )
        case .evening:
            return (
                skyTop: Color(hex: "5C7A9A"),
                skyBottom: Color(hex: "C4905E"),
                horizonGlow: Color(hex: "F0B040"),
                farLayer: Color(hex: "A08E74"),
                midLayer: Color(hex: "7D6D52"),
                nearLayer: Color(hex: "5B5040"),
                foregroundLayer: Color(hex: "3C3228"),
                cloudTint: Color(hex: "FFE8B0").opacity(0.50),
                atmosphereTint: Color(hex: "D4845A").opacity(0.22),
                accent: Color(hex: "D98040"),
                userBubble: Color(hex: "7A5C44"),
                primaryTextOnAccent: Color(red: 0.22, green: 0.16, blue: 0.10)
            )
        case .night:
            return (
                skyTop: Color(hex: isLateNight ? "162031" : "3D4B62"),
                skyBottom: Color(hex: isLateNight ? "0D1521" : "243244"),
                horizonGlow: Color(hex: isLateNight ? "293248" : "697485"),
                farLayer: Color(hex: isLateNight ? "3D463D" : "576255"),
                midLayer: Color(hex: isLateNight ? "313A31" : "465041"),
                nearLayer: Color(hex: isLateNight ? "262D26" : "343C30"),
                foregroundLayer: Color(hex: isLateNight ? "1A201A" : "272D25"),
                cloudTint: Color(hex: "E3E7F3").opacity(isLateNight ? 0.14 : 0.24),
                atmosphereTint: Color(hex: isLateNight ? "222C3D" : "4B5770").opacity(isLateNight ? 0.28 : 0.24),
                accent: Color(hex: "CBB98B"),
                userBubble: Color(hex: isLateNight ? "4A574A" : "556557"),
                primaryTextOnAccent: Color(red: 0.18, green: 0.17, blue: 0.13)
            )
        }
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red, green, blue: UInt64
        switch cleaned.count {
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            red = 0
            green = 0
            blue = 0
        }

        self.init(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0
        )
    }

    func adjustedHSB(hueDegrees: Double = 0, brightnessPercent: Double = 0, saturationPercent: Double = 0) -> Color {
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }

        let hueDelta = CGFloat(hueDegrees / 360.0)
        let newHue = (hue + hueDelta).truncatingRemainder(dividingBy: 1)
        let clampedHue = newHue < 0 ? newHue + 1 : newHue
        let newSaturation = min(max(saturation + CGFloat(saturationPercent / 100.0), 0), 1)
        let newBrightness = min(max(brightness + CGFloat(brightnessPercent / 100.0), 0), 1)
        return Color(
            UIColor(
                hue: clampedHue,
                saturation: newSaturation,
                brightness: newBrightness,
                alpha: alpha
            )
        )
#else
        return self
#endif
    }
}
