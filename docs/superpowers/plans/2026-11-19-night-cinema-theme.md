# Night Cinema Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Restyle the app to the approved "Night cinema" look without changing behaviour.
**Architecture:** `Theme` palette + fonts and reusable `PillButtonStyle` / `PillSearchField` live in the testable `AppViews` target; app views switch to them; window forced dark with hidden title bar.
**Tech Stack:** SwiftUI (macOS 14+), Swift Testing, ImageRenderer pixel probes.
**Spec:** `docs/2026-11-19-night-cinema-theme-design.md`

## Global Constraints
- Palette hexes exactly as the spec. Every text/background pair ≥ 4.5:1 (WCAG AA).
- No behaviour changes; all existing tests stay green (`app/scripts/test.sh`).
- `@ViewState` instead of `@State` (Command Line Tools lack the SwiftUI macro plugin).

## Review Focus
1. Text readable on every surface (contrast test).
2. Traffic lights must not overlap top-bar controls with the hidden title bar (28-pt drag strip).
3. Hover glow must not shift the grid layout (overlay/shadow only).
4. Search and layout controls moved to the top bar still drive the library.
5. Native menus, alerts, sheets and the Table stay legible (forced dark scheme).

### Task 1: Theme + reusable styles (AppViews)
**Files:** Create `app/Sources/AppViews/Theme.swift`, `app/Sources/AppViews/PillStyles.swift`; Modify `app/Sources/AppViews/ThumbnailFrame.swift`; Test `app/Tests/AppViewsTests/ThemeTests.swift`, `ThumbnailFrameTests.swift`.
**Produces:** `public struct ThemeColor { hex: UInt32; color: Color; luminance: Double }`, `public func contrastRatio(_:_:) -> Double`, `public enum Theme { background, surface, surfaceRaised, hairline, hairlineStrong, text, textSecondary, accent, onAccent, accentLabel, warningBackground, warningText, danger: ThemeColor }`, `public struct PillButtonStyle: ButtonStyle { init(prominent: Bool) }`, `public struct PillSearchField: View { init(text: Binding<String>) }`.
- [ ] Failing tests: `textPairsMeetAA` (text/textSecondary on background+surface+surfaceRaised, onAccent on accent, accentLabel/accent/danger on background, warningText on warningBackground ≥ 4.5); `durationChipIsAccentGreen` (pixel inside chip ≈ #07C160).
- [ ] Run `scripts/test.sh --filter AppViewsTests` → FAIL. Implement. Run → PASS.

### Task 2: Restyle app views
**Files:** Modify `ChannelsDownloaderApp.swift` (hidden title bar, dark scheme, rounded font, background), `StatusBarView.swift` (pulsing dot, labels, search + layout + Start/Stop pills, amber VPN strip), `LibraryView.swift` (green section label, dark cards with hover ring + glow, dark table, empty state, footer, rename sheet).
- [ ] `scripts/test.sh` → all PASS; `scripts/build-app.sh --install` → signed; open the app for the user to check (screen access was declined earlier).
