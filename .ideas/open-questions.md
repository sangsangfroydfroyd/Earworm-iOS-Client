# Open Questions: mobileworm

> Generated from `.app-freedom/memory/`. Update through memory events and workflow checkpoints rather than editing this file by hand.

## Outstanding

- none

## Resolved

- none

## Implementation Safety

- Tightened fullscreen fit after bottom safe-area remained visible. Web destination now ignores safe areas at the RootView route level, RootView hides navigation toolbar and paints a safe fallback background, and WebContainerView uses overlay instead of safeAreaInset for unauthenticated Change Server so the WKWebView is no longer resized by native bottom insets. Simulator build/run and screenshot sanity check passed; security scan had no findings.
- Fixed remaining bottom safe-area bar by moving ignoresSafeArea(.container) onto the WKWebView itself, making the web content edge-to-edge on all sides while keeping native unauthenticated Change Server control in SwiftUI safe-area placement. iOS simulator build passed; mobileworm security scan had no findings.
- Finished native fullscreen container follow-up. mobileworm WebContainerView now lets the WKWebView ignore the top safe area so Earworm can render edge-to-edge under the notch/status area. iOS simulator build passed and mobileworm security scan had no findings.
- Made the one permitted mobileworm native-container edit: locked iPhone orientation to portrait in XcodeGen config, preserved signing team in project.yml, added WKWebView zoom/viewport suppression, regenerated the Xcode project, verified the built Info.plist orientation key, passed simulator build, and ran security check with no findings.
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
