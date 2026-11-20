import SwiftUI

public enum PillKind: Sendable {
    /// Dark outlined pill.
    case plain
    /// WeChat green fill.
    case prominent
    /// Dark pill with green outline and text.
    case accent
}

/// Label colour for each pill kind.
public func pillForeground(_ kind: PillKind) -> ThemeColor {
    switch kind {
    case .plain: return Theme.text
    case .prominent: return Theme.onAccent
    case .accent: return Theme.accent
    }
}

/// Rounded pill button.
public struct PillButtonStyle: ButtonStyle {
    let kind: PillKind

    public init(kind: PillKind) { self.kind = kind }
    public init(prominent: Bool = false) { self.kind = prominent ? .prominent : .plain }

    private var prominent: Bool { kind == .prominent }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, prominent ? 18 : 12)
            .padding(.vertical, 7)
            .foregroundStyle(pillForeground(kind).color)
            .background(
                Capsule().fill(prominent ? Theme.accent.color : Theme.surface.color)
            )
            .overlay(
                Capsule().stroke(kind == .prominent ? Color.clear : kind == .accent ? Theme.accent.color : Theme.hairlineStrong.color, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Dark pill-shaped search field.
public struct PillSearchField: View {
    @Binding var text: String

    public init(text: Binding<String>) { _text = text }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary.color)
            TextField("", text: $text, prompt: Text("Search").foregroundStyle(Theme.textSecondary.color))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.text.color)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary.color)
                    .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 13, design: .rounded))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Theme.surface.color))
        .overlay(Capsule().stroke(Theme.hairlineStrong.color, lineWidth: 1))
    }
}
