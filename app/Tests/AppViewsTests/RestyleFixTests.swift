import AppViews
import Testing

@Suite struct RestyleFixTests {
    @Test func selectedRowSecondaryTextIsReadable() {
        let selectionBlue = ThemeColor(hex: 0x0059D1), inactiveSelection = ThemeColor(hex: 0x464646)
        #expect(contrastRatio(secondaryTextColor(selected: true), selectionBlue) >= 4.5)
        #expect(contrastRatio(secondaryTextColor(selected: true), inactiveSelection) >= 4.5)
        #expect(secondaryTextColor(selected: false) == Theme.textSecondary)
    }

    @Test func failureDetailIsNotTruncated() {
        #expect(statusDetailLineLimit(isFailure: true) == nil)
        #expect(statusDetailLineLimit(isFailure: false) == 3)
    }

    @Test func openFolderPillIsGreen() {
        #expect(pillForeground(.accent) == Theme.accent)
        #expect(contrastRatio(pillForeground(.accent), Theme.surface) >= 4.5)
        #expect(pillForeground(.prominent) == Theme.onAccent)
        #expect(pillForeground(.plain) == Theme.text)
    }
}
