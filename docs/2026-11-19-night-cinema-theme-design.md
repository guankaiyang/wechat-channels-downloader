# Night cinema theme (design)

## Intent
The user wants the app to look less like a default Apple app. From three mockups they picked
"A · Night cinema": dark, WeChat green, glowing accents.

## Goals
- Always-dark window (ignores the Mac's light mode; the look is the point), title bar hidden so the
  dark top bar runs to the window edge with the traffic lights on it.
- Palette: background #0E1512, cards #18221D, hairlines #1E2B25 / #2A3B33, text #E8F3EC,
  secondary text #8FA89A, accent WeChat green #07C160 with dark text #062814 on it,
  section-label green #5FD394, VPN warning amber, error red.
- Rounded system font (SF Pro Rounded) for headings and buttons.
- Top bar: status dot (gently pulsing green while capturing), "Capturing" / "Idle" / "Starting…",
  pill search field, grid/list pills, green pill Start/Stop button.
- Library: letter-spaced green label "YOUR LIBRARY · N VIDEOS"; dark cards with rounded 3:4 thumbnails,
  green duration chip, light title, muted size · date; on hover a green ring and soft green glow.
- Empty state, footer ("Open folder" in green) and rename sheet restyled to match.

## Non-goals
- No behaviour changes (start/stop, proxy safety, library logic stay as they are).
- Native right-click menus and the system list (Table) keep macOS styling, shown in dark mode.

## Anti-goals
- Unreadable text: every text/background pair must meet WCAG AA (4.5:1).

## Approach
One `Theme` (colours + fonts) and reusable styles (pill button, pill search field) in the testable
`AppViews` target; existing views switch to them. Alternatives (asset-catalog colours, per-view
hard-coded colours) dropped: no Xcode asset catalogs here, and hard-coded colours drift.

## Left to the builder
Exact spacing, animation timing, glow strength.
