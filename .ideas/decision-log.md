# Decision Log: mobileworm

> Generated from `.app-freedom/memory/`. Update through memory events and workflow checkpoints rather than editing this file by hand.

## 2026-04-17

### 1. Architecture -> Use a thin native SwiftUI shell with WKWebView rather than rebuilding EarWorm natively.

- Summary: Completed planning docs for mobileworm as an iPhone-first SwiftUI shell that validates an HTTPS EarWorm server and hosts EarWorm's existing mobile web UI inside WKWebView.
- Reason: Completed /plan using the ideation contracts plus EarWorm's existing LAN/auth implementation and Jellyfin-inspired server-connect research.
- Outcome: Created architecture, tech-stack, implementation plan, data-model, and platform-matrix docs and marked the app ready for Stage 1 foundation work.
- Decision: Validation path -> Use EarWorm's public /api/auth/status endpoint initially because it already returns serverName: EarWorm over a browser-safe JSON payload.
- Decision: Session model -> Keep authentication and session ownership inside EarWorm's web app and rely on WKWebView persistent website data.
- Decision: Persistence model -> Store one active saved server locally in v1 with room for multiple later.
- Decision: Implementation order -> Build shell and web container first, then validation hardening and recovery flows.
- Future-self note: Do not weaken ATS or add broad insecure-network exceptions unless a real blocker appears during implementation.
- Future-self note: Treat any attempt to recreate EarWorm screens natively as scope drift unless the web shell proves insufficient.
- Files touched: /Volumes/T7/projects/mobileworm/.ideas/architecture.md, /Volumes/T7/projects/mobileworm/.ideas/tech-stack.md, /Volumes/T7/projects/mobileworm/.ideas/plan.md, /Volumes/T7/projects/mobileworm/.ideas/data-model.md, /Volumes/T7/projects/mobileworm/.ideas/platform-matrix.md

### 2. Platform -> iPhone-first iOS app for personal TestFlight distribution.

- Summary: Documented mobileworm v1 as a thin iOS wrapper around EarWorm's existing mobile web UI with a first-launch HTTPS server-entry flow and saved-server behavior.
- Reason: Completed /dream after clarifying scope, distribution, server persistence, and HTTPS-only requirements.
- Outcome: Created ideation contracts for a SwiftUI + WKWebView shell rather than a native rebuild of EarWorm's mobile UI.
- Decision: Scope boundary -> Reuse EarWorm's existing mobile web UI inside WKWebView instead of rebuilding the product natively.
- Decision: Server persistence -> Ask for the server URL on first launch, then save it locally and expose Change Server from the login experience.
- Decision: Connection policy -> HTTPS only in v1.
- Decision: Server model -> Support one active server in the v1 user experience while leaving room for multiple later.
- Future-self note: Prefer validating against an explicit EarWorm-specific public endpoint during implementation instead of relying only on loose page-title or HTML checks.
- Future-self note: Treat Safari fallback as a troubleshooting path for certificate trust and development-time recovery, not the primary experience.
- Files touched: /Volumes/T7/projects/mobileworm/.ideas/creative-brief.md, /Volumes/T7/projects/mobileworm/.ideas/feature-spec.md, /Volumes/T7/projects/mobileworm/.ideas/ui-mockups/launch-flow.md
