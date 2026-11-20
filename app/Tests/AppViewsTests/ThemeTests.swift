import AppViews
import Testing

@Suite struct ThemeTests {
    @Test func textPairsMeetAA() {
        let pairs: [(String, ThemeColor, ThemeColor)] = [
            ("text on background", Theme.text, Theme.background),
            ("secondary on background", Theme.textSecondary, Theme.background),
            ("text on surface", Theme.text, Theme.surface),
            ("secondary on surface", Theme.textSecondary, Theme.surface),
            ("text on raised", Theme.text, Theme.surfaceRaised),
            ("secondary on raised", Theme.textSecondary, Theme.surfaceRaised),
            ("on accent", Theme.onAccent, Theme.accent),
            ("label on background", Theme.accentLabel, Theme.background),
            ("accent on background", Theme.accent, Theme.background),
            ("danger on background", Theme.danger, Theme.background),
            ("warning", Theme.warningText, Theme.warningBackground),
            ("vpn mode on", Theme.accentLabel, Theme.successBackground),
            ("vpn leftover", Theme.danger, Theme.dangerBackground),
        ]
        for (name, fg, bg) in pairs {
            #expect(contrastRatio(fg, bg) >= 4.5, "\(name): \(contrastRatio(fg, bg))")
        }
    }

    @Test func contrastMatchesKnownValues() {
        let black = ThemeColor(hex: 0x000000), white = ThemeColor(hex: 0xFFFFFF)
        #expect(abs(contrastRatio(white, black) - 21) < 0.01)
        #expect(abs(contrastRatio(black, black) - 1) < 0.01)
    }
}
