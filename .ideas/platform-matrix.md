# Platform Matrix: mobileworm

| Target | Priority | UI Strategy | Packaging | Signing / Trust | Data Location | Accessibility | Notes |
|--------|----------|-------------|-----------|-----------------|---------------|---------------|-------|
| iPhone (iOS) | P0 | SwiftUI shell around `WKWebView` | TestFlight build | Apple signing + TestFlight; ATS default posture; HTTPS-only server policy | app sandbox; lightweight local config plus persistent web view website data store | touch-first, Dynamic Type on native screens, VoiceOver labels for connect/recovery actions | Primary target for v1 |
| iPadOS | P2 | same shell, likely letterboxed or lightly adapted | not a launch priority | same as iPhone | same sandbox model | touch, Dynamic Type, VoiceOver | Defer layout-specific polish until iPhone flow is proven |
| macOS | None | no native macOS client in this app | none | none | n/a | n/a | EarWorm desktop app already serves this role |
| Android | Future | none in this cycle | none | none | n/a | n/a | Out of scope for current plan |

## Release Notes

- v1 is intentionally iPhone-first.
- Personal TestFlight is the only planned distribution channel in this cycle.
- The app should avoid decisions that would block future iPad polish, but should not absorb iPad-specific scope now.

## Packaging Guidance

- keep the app shell small
- keep EarWorm as the owner of authenticated product UI
- avoid ATS exceptions unless a real blocker proves they are necessary
