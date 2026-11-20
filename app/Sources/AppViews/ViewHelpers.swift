import SwiftUI

/// Secondary text colour for a row; on a selected (highlighted) row it switches to full-strength text.
public func secondaryTextColor(selected: Bool) -> ThemeColor {
    selected ? Theme.text : Theme.textSecondary
}

/// Status detail lines: failures show in full (the last log line is usually the real error).
public func statusDetailLineLimit(isFailure: Bool) -> Int? {
    isFailure ? nil : 3
}

/// Muted text that stays readable when its table row is selected.
public struct RowSecondaryText: View {
    let text: String
    @Environment(\.backgroundProminence) private var prominence

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).foregroundStyle(secondaryTextColor(selected: prominence == .increased).color)
    }
}
