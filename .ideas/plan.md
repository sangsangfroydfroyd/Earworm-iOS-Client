# Implementation Plan: mobileworm

## Planning Summary

Goal: deliver a small iPhone app that remembers one EarWorm server, validates it over HTTPS, and hosts EarWorm's existing mobile web experience inside a native shell.

## Delivery Order

### Stage 1: Foundation

1. Create the iOS project scaffold and app shell.
2. Add the native first-launch connect screen.
3. Implement saved-server persistence.
4. Add a minimal `WKWebView` bridge and load a configurable server URL.
5. Confirm that the app can load a known-good EarWorm login page manually.

Exit criteria:

- app launches in simulator
- server URL can be saved and reloaded
- `WKWebView` loads the saved EarWorm URL

### Stage 2: Validation Contract

1. Implement `ServerValidationService` in mobileworm.
2. Validate against EarWorm's existing `GET /api/auth/status`.
3. Confirm the response includes:
   - HTTP 200
   - HTTPS final URL
   - `serverName: "EarWorm"`
4. Decide whether to freeze that contract or add a dedicated EarWorm-side client-info endpoint.
5. If needed, add the dedicated public endpoint in EarWorm and switch mobileworm to it.

Exit criteria:

- non-HTTPS URLs are rejected locally
- non-EarWorm HTTPS hosts fail validation cleanly
- valid EarWorm hosts proceed into the web container

### Stage 3: Recovery and Session Behavior

1. Add native recovery states for failed reconnects.
2. Add Change Server action from the web-container shell.
3. Confirm persistent web cookies keep users signed in across app relaunches when EarWorm allows it.
4. Add Safari fallback for certificate/trust troubleshooting.

Exit criteria:

- relaunch works with saved server
- change-server flow resets correctly
- recovery UI distinguishes retry vs change server

### Stage 4: Hardening and QA

1. Run simulator QA for first launch, reconnect, logout, and broken-server cases.
2. Verify safe-area layout, Dynamic Type tolerance, and VoiceOver labels on native screens.
3. Run TestFlight smoke testing against a real EarWorm server.

Exit criteria:

- personal TestFlight build is usable end-to-end
- no blocking reconnect or validation bugs remain

## Work Breakdown

### Mobileworm App Work

- Xcode project setup
- SwiftUI root routing
- server connection screen
- validation networking
- `WKWebView` integration
- persistence layer
- recovery states
- UI tests and manual QA support

### EarWorm Support Work

- verify existing public validation endpoint behavior
- optionally add dedicated public client-info endpoint
- preserve stable browser auth/login behavior used by mobileworm

## Risk Register

### 1. Validation Contract Too Implicit

Risk:

- mobileworm relies on a browser-auth endpoint that was not originally intended as a long-term client identity contract

Mitigation:

- add a dedicated public client-info endpoint during implementation if needed

### 2. Web Session Edge Cases

Risk:

- cookies or login redirects may behave differently in `WKWebView` than in Safari

Mitigation:

- test directly against the real EarWorm server early
- keep login ownership in the web app rather than trying to bridge credentials natively

### 3. Certificate Trust Friction

Risk:

- personal LAN HTTPS setups may still hit trust issues on device

Mitigation:

- keep HTTPS-only policy
- expose Safari fallback for troubleshooting
- document trust steps for personal TestFlight use

### 4. Scope Drift into Native Client Work

Risk:

- implementation starts recreating parts of EarWorm instead of wrapping them

Mitigation:

- treat any native playback, search, or library browsing request as future scope unless it is strictly required for shell reliability

## Validation Checklist

- Connect screen accepts valid HTTPS EarWorm URL
- Connect screen rejects HTTP URL
- Connect screen rejects non-EarWorm HTTPS URL
- Relaunch resumes to saved server
- EarWorm login renders correctly in `WKWebView`
- Change Server clears the active server and returns to connect flow
- Recovery screen appears when saved server fails
- Safari fallback opens the saved URL

## Recommended Next Implementation Command

- Continue to `/implement mobileworm`
