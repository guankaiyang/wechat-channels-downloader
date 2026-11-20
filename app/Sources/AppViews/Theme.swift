import SwiftUI

/// One palette colour, kept as hex so contrast can be checked in tests.
public struct ThemeColor: Sendable, Equatable {
    public let hex: UInt32

    public init(hex: UInt32) { self.hex = hex }

    private var channels: (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    public var color: Color {
        let (r, g, b) = channels
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = channels
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

/// WCAG contrast ratio between two colours (1…21).
public func contrastRatio(_ a: ThemeColor, _ b: ThemeColor) -> Double {
    let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
    return (hi + 0.05) / (lo + 0.05)
}

/// "Night cinema": dark green-black, WeChat green accent.
public enum Theme {
    public static let background = ThemeColor(hex: 0x0E1512)
    public static let surface = ThemeColor(hex: 0x18221D)
    public static let surfaceRaised = ThemeColor(hex: 0x1F2C26)
    public static let hairline = ThemeColor(hex: 0x1E2B25)
    public static let hairlineStrong = ThemeColor(hex: 0x2A3B33)
    public static let text = ThemeColor(hex: 0xE8F3EC)
    public static let textSecondary = ThemeColor(hex: 0x8FA89A)
    public static let accent = ThemeColor(hex: 0x07C160)
    public static let onAccent = ThemeColor(hex: 0x062814)
    public static let accentLabel = ThemeColor(hex: 0x5FD394)
    public static let warningBackground = ThemeColor(hex: 0x3A2E12)
    public static let warningText = ThemeColor(hex: 0xF3C062)
    public static let danger = ThemeColor(hex: 0xFF7A70)
    public static let successBackground = ThemeColor(hex: 0x12301F)
    public static let dangerBackground = ThemeColor(hex: 0x3A1715)
}
