# Open Questions: mobileworm

> Generated from `.app-freedom/memory/`. Update through memory events and workflow checkpoints rather than editing this file by hand.

## Outstanding

- none

## Resolved

- none

## Implementation Safety

- Adjusted WKWebView safe-area behavior and moved the unauthenticated Change Server control into a bottom safeAreaInset so the wrapper no longer hard-codes bottom spacing.
- Validated that mobileworm still reaches EarWorm's login UI and Change Server flow with the live host. Attempted to continue with the provided test credentials, but simulator automation could not reliably type into the WKWebView login fields, and the Cloudflare tunnel for earworm.sillytina.fun degraded to HTTP 502 during direct login verification.
- If auth/status or auth/login start returning Cloudflare 502 during testing, stop attributing the failure to the app until the tunnel/origin is healthy again.
- Live simulator validation now passes for https://earworm.sillytina.fun. The app validates the EarWorm server, saves it, opens EarWorm's existing mobile login UI in WKWebView with no native browser toolbar, and the login-screen Change EarWorm Server control returns to first-launch server entry. Replaced the unreliable DOM-injected change-server button with a native EarWorm-styled overlay shown only while unauthenticated.
- If testing login-screen Change Server, use the accessibility label Change EarWorm Server; coordinate screenshots may not match AX coordinates in the WebView.
- Validated provided EarWorm URL for mobileworm. Direct HTTPS initially returned EarWorm auth status, but the Cloudflare tunnel then began returning HTTP 530 / error 1033 for both curl and the iOS validator. mobileworm launched in the simulator, accepted the URL, and correctly stayed on first-launch with 'EarWorm returned HTTP 530.'
- If /api/auth/status returns HTTP 530/Cloudflare 1033, the app is not failing identity validation; Cloudflare cannot reach the EarWorm origin.
- Aligned mobileworm to use EarWorm's existing mobile web UI by removing native WebView toolbar/title chrome, adding a WebKit bridge that injects an EarWorm-styled Change Server button only on the web login screen, and updating status docs after successful simulator/security validation.
- The next meaningful runtime test should use a real HTTPS EarWorm server to verify validation, saving, and WKWebView login behavior end-to-end.
- Once full Xcode is available, the first follow-up should be xcodegen generate, xcodebuild -list, and a simulator build to catch any SwiftUI or project-setting issues.
- Completed /plan for mobileworm. Defined the app as an iPhone-first SwiftUI shell with WKWebView reuse of EarWorm's existing mobile UI, lightweight saved-server persistence, HTTPS-only validation, and a staged plan for foundation, validation hardening, recovery flows, and TestFlight QA.
- Do not weaken ATS or add broad insecure-network exceptions unless a real blocker appears during implementation.
- Treat any attempt to recreate EarWorm screens natively as scope drift unless the web shell proves insufficient.
- Completed /dream for mobileworm. Defined the app as an iPhone-first personal-TestFlight wrapper around EarWorm's existing mobile web UI, with first-launch HTTPS server entry, saved-server behavior, change-server recovery, and a WKWebView-based login/app flow.
- Prefer validating against an explicit EarWorm-specific public endpoint during implementation instead of relying only on loose page-title or HTML checks.
- Treat Safari fallback as a troubleshooting path for certificate trust and development-time recovery, not the primary experience.
- Created the external mobileworm app workspace by cloning Earworm-iOS-Client into /Volumes/T7/projects/mobileworm, registering it in App Freedom, scaffolding app-local memory/ideas files, and verifying push-app plan resolves the repo correctly.
