# Open Questions: mobileworm

> Generated from `.app-freedom/memory/`. Update through memory events and workflow checkpoints rather than editing this file by hand.

## Outstanding

- none

## Resolved

- none

## Implementation Safety

- Completed /plan for mobileworm. Defined the app as an iPhone-first SwiftUI shell with WKWebView reuse of EarWorm's existing mobile UI, lightweight saved-server persistence, HTTPS-only validation, and a staged plan for foundation, validation hardening, recovery flows, and TestFlight QA.
- Do not weaken ATS or add broad insecure-network exceptions unless a real blocker appears during implementation.
- Treat any attempt to recreate EarWorm screens natively as scope drift unless the web shell proves insufficient.
- Completed /dream for mobileworm. Defined the app as an iPhone-first personal-TestFlight wrapper around EarWorm's existing mobile web UI, with first-launch HTTPS server entry, saved-server behavior, change-server recovery, and a WKWebView-based login/app flow.
- Prefer validating against an explicit EarWorm-specific public endpoint during implementation instead of relying only on loose page-title or HTML checks.
- Treat Safari fallback as a troubleshooting path for certificate trust and development-time recovery, not the primary experience.
- Created the external mobileworm app workspace by cloning Earworm-iOS-Client into /Volumes/T7/projects/mobileworm, registering it in App Freedom, scaffolding app-local memory/ideas files, and verifying push-app plan resolves the repo correctly.
