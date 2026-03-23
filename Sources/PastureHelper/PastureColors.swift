import SwiftUI
import AppKit

enum PastureColors {
    /// Yellow-gold accent used in the menu bar popover and model manager.
    static let accent = Color(red: 0.96, green: 0.78, blue: 0.26)

    /// AppKit variant of `accent` for use in NSStatusItem symbol configuration.
    static let accentNS = NSColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 1)

    /// Pasture green used for the menu bar icon, onboarding, and "Get Started" button.
    static let green = Color(red: 0.690, green: 0.894, blue: 0.416)

    /// AppKit variant of `green` for use in NSStatusItem symbol configuration.
    static let greenNS = NSColor(red: 0.690, green: 0.894, blue: 0.416, alpha: 1)

    /// Dark charcoal background used by the menu bar popover.
    static let popoverBackground = Color(red: 0.11, green: 0.11, blue: 0.12)
}
