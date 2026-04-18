# Decision Log: mobileworm

> Generated from `.app-freedom/memory/`. Update through memory events and workflow checkpoints rather than editing this file by hand.

## 2026-04-18

### 1. Attempted live password login validation for mobileworm using the provided test account.

- Summary: Attempted live password login validation for mobileworm using the provided test account.
- Reason: User supplied test credentials for simulator validation past the EarWorm login screen.
- Outcome: mobileworm still reaches EarWorm's login UI and Change Server flow, but simulator automation could not reliably type into the WKWebView login fields. During direct API verification, the Cloudflare edge for earworm.sillytina.fun flipped from healthy to HTTP 502, so the credentials could not be verified end to end in this turn.
- Future-self note: If auth/status or auth/login start returning Cloudflare 502 during testing, stop attributing the failure to the app until the tunnel/origin is healthy again.

## 2026-04-17

### 2. Use a native EarWorm-styled login-screen Change Server overlay instead of injecting a DOM button, because the DOM button rendered in WKWebView but simulator taps did not fire its click handler reliably.

- Summary: Validated mobileworm against live EarWorm server earworm.sillytina.fun in the iOS simulator.
- Reason: User restored the Cloudflare tunnel and provided a successful curl check.
- Outcome: mobileworm validated /api/auth/status, saved the server, opened EarWorm's existing mobile login UI in WKWebView without native toolbar chrome, and Change Server from the login screen returned to first-launch server entry. Replaced unreliable DOM-injected Change Server tap with a native EarWorm-styled overlay visible only while unauthenticated.
- Future-self note: If testing login-screen Change Server, use the accessibility label Change EarWorm Server; coordinate screenshots may not match AX coordinates in the WebView.

### 3. Tested earworm.sillytina.fun for mobileworm live validation.

- Summary: Tested earworm.sillytina.fun for mobileworm live validation.
- Reason: User provided the HTTPS EarWorm server URL for end-to-end validation.
- Outcome: Initial /api/auth/status check returned HTTP 200 with serverName EarWorm, but subsequent direct curl requests and the iOS app validator returned Cloudflare HTTP 530 error code 1033, so the Cloudflare tunnel/origin was unavailable and mobileworm correctly refused to save the server.
- Future-self note: If /api/auth/status returns HTTP 530/Cloudflare 1033, the app is not failing identity validation; Cloudflare cannot reach the EarWorm origin.

### 4. Simulator validation -> Use Xcode 26.4 with the iOS 26.4 runtime for the first verified build.

- Summary: Installed the iOS 26.4 simulator platform, built mobileworm successfully with Xcode 26.4, launched it on an iPhone 17 Pro simulator, and verified the native first-launch EarWorm connection screen.
- Reason: Explicit app-memory refresh after local file changes.
- Outcome: Current working-tree changes were acknowledged and captured in app memory.
- Decision: Stage 1 foundation -> Use XcodeGen to generate a minimal native iOS project around the planned SwiftUI + WKWebView shell.
- Decision: Validation UX -> Reject non-HTTPS URLs locally and validate EarWorm identity via /api/auth/status before saving the server.
- Decision: Recovery UX -> Expose Retry, Change Server, and Safari fallback as native flows outside the web view.
- Decision: Architecture -> Use a thin native SwiftUI shell with WKWebView rather than rebuilding EarWorm natively.
- Decision: Validation path -> Use EarWorm's public /api/auth/status endpoint initially because it already returns serverName: EarWorm over a browser-safe JSON payload.
- Decision: Session model -> Keep authentication and session ownership inside EarWorm's web app and rely on WKWebView persistent website data.
- Decision: Persistence model -> Store one active saved server locally in v1 with room for multiple later.
- Decision: Implementation order -> Build shell and web container first, then validation hardening and recovery flows.
- Decision: Platform -> iPhone-first iOS app for personal TestFlight distribution.
- Decision: Scope boundary -> Reuse EarWorm's existing mobile web UI inside WKWebView instead of rebuilding the product natively.
- Decision: Server persistence -> Ask for the server URL on first launch, then save it locally and expose Change Server from the login experience.
- Decision: Connection policy -> HTTPS only in v1.
- Decision: Server model -> Support one active server in the v1 user experience while leaving room for multiple later.
- Future-self note: The next meaningful runtime test should use a real HTTPS EarWorm server to verify validation, saving, and WKWebView login behavior end-to-end.
- Future-self note: Once full Xcode is available, the first follow-up should be xcodegen generate, xcodebuild -list, and a simulator build to catch any SwiftUI or project-setting issues.
- Future-self note: Completed /plan for mobileworm. Defined the app as an iPhone-first SwiftUI shell with WKWebView reuse of EarWorm's existing mobile UI, lightweight saved-server persistence, HTTPS-only validation, and a staged plan for foundation, validation hardening, recovery flows, and TestFlight QA.
- Files touched: .app-freedom/memory/current.json, .app-freedom/memory/current.md, .app-freedom/memory/history/events.jsonl, .app-freedom/memory/mempalace/current-snapshot.md, .app-freedom/memory/mempalace/status.json, .ideas/decision-log.md

### 5. Simulator validation -> Use Xcode 26.4 with the iOS 26.4 runtime for the first verified build.

- Summary: Installed the iOS 26.4 simulator platform, built mobileworm successfully with Xcode 26.4, launched it on an iPhone 17 Pro simulator, and verified the native first-launch EarWorm connection screen.
- Reason: Finished the first working simulator validation pass after unblocking Xcode and simulator components.
- Outcome: mobileworm now compiles and launches successfully on the iOS 26.4 simulator with the expected native server-entry UI.
- Future-self note: The next meaningful runtime test should use a real HTTPS EarWorm server to verify validation, saving, and WKWebView login behavior end-to-end.
- Files touched: /Volumes/T7/projects/mobileworm/project.yml, /Volumes/T7/projects/mobileworm/Mobileworm/App/MobilewormApp.swift, /Volumes/T7/projects/mobileworm/Mobileworm/App/RootView.swift, /Volumes/T7/projects/mobileworm/Mobileworm/Features/Connect/ConnectServerView.swift

### 6. Stage 1 foundation -> Use XcodeGen to generate a minimal native iOS project around the planned SwiftUI + WKWebView shell.

- Summary: Scaffolded the first implementation pass for mobileworm: XcodeGen project spec, SwiftUI app shell, saved-server persistence, EarWorm validation service, WKWebView container, recovery flow, and repo README.
- Reason: Explicit app-memory refresh after local file changes.
- Outcome: Current working-tree changes were acknowledged and captured in app memory.
- Decision: Validation UX -> Reject non-HTTPS URLs locally and validate EarWorm identity via /api/auth/status before saving the server.
- Decision: Recovery UX -> Expose Retry, Change Server, and Safari fallback as native flows outside the web view.
- Decision: Architecture -> Use a thin native SwiftUI shell with WKWebView rather than rebuilding EarWorm natively.
- Decision: Validation path -> Use EarWorm's public /api/auth/status endpoint initially because it already returns serverName: EarWorm over a browser-safe JSON payload.
- Decision: Session model -> Keep authentication and session ownership inside EarWorm's web app and rely on WKWebView persistent website data.
- Decision: Persistence model -> Store one active saved server locally in v1 with room for multiple later.
- Decision: Implementation order -> Build shell and web container first, then validation hardening and recovery flows.
- Decision: Platform -> iPhone-first iOS app for personal TestFlight distribution.
- Decision: Scope boundary -> Reuse EarWorm's existing mobile web UI inside WKWebView instead of rebuilding the product natively.
- Decision: Server persistence -> Ask for the server URL on first launch, then save it locally and expose Change Server from the login experience.
- Decision: Connection policy -> HTTPS only in v1.
- Decision: Server model -> Support one active server in the v1 user experience while leaving room for multiple later.
- Future-self note: Once full Xcode is available, the first follow-up should be xcodegen generate, xcodebuild -list, and a simulator build to catch any SwiftUI or project-setting issues.
- Future-self note: Completed /plan for mobileworm. Defined the app as an iPhone-first SwiftUI shell with WKWebView reuse of EarWorm's existing mobile UI, lightweight saved-server persistence, HTTPS-only validation, and a staged plan for foundation, validation hardening, recovery flows, and TestFlight QA.
- Future-self note: Do not weaken ATS or add broad insecure-network exceptions unless a real blocker appears during implementation.
- Files touched: .app-freedom/memory/current.json, .app-freedom/memory/current.md, .app-freedom/memory/history/events.jsonl, .app-freedom/memory/mempalace/current-snapshot.md, .app-freedom/memory/mempalace/status.json, .gitignore

### 7. Stage 1 foundation -> Use XcodeGen to generate a minimal native iOS project around the planned SwiftUI + WKWebView shell.

- Summary: Scaffolded the first implementation pass for mobileworm: XcodeGen project spec, SwiftUI app shell, saved-server persistence, EarWorm validation service, WKWebView container, recovery flow, and repo README.
- Reason: Continued from /plan into /implement to complete Stage 1 foundation work for the iOS wrapper app.
- Outcome: The app scaffold and Xcode project now exist, but simulator build validation is blocked on this machine because only Command Line Tools are installed and full Xcode is not available.
- Decision: Validation UX -> Reject non-HTTPS URLs locally and validate EarWorm identity via /api/auth/status before saving the server.
- Decision: Recovery UX -> Expose Retry, Change Server, and Safari fallback as native flows outside the web view.
- Future-self note: Once full Xcode is available, the first follow-up should be xcodegen generate, xcodebuild -list, and a simulator build to catch any SwiftUI or project-setting issues.
- Files touched: /Volumes/T7/projects/mobileworm/project.yml, /Volumes/T7/projects/mobileworm/Mobileworm/App/MobilewormApp.swift, /Volumes/T7/projects/mobileworm/Mobileworm/App/AppModel.swift, /Volumes/T7/projects/mobileworm/Mobileworm/App/RootView.swift, /Volumes/T7/projects/mobileworm/Mobileworm/Features/Connect/ConnectServerView.swift, /Volumes/T7/projects/mobileworm/Mobileworm/Features/Recovery/RecoveryView.swift

### 8. Architecture -> Use a thin native SwiftUI shell with WKWebView rather than rebuilding EarWorm natively.

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

### 9. Platform -> iPhone-first iOS app for personal TestFlight distribution.

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
