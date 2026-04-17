# Feature Spec: mobileworm

## Product Definition

mobileworm is an iOS app that connects to an EarWorm desktop server and renders EarWorm's existing mobile web interface inside a native container.

## Platform and Release

- Primary platform: iPhone
- Release mode: personal TestFlight
- Authentication ownership: EarWorm server
- Supported connection type in v1: HTTPS only

## Core User Flow

1. User launches the app for the first time.
2. App presents a native server connection screen.
3. User enters an HTTPS EarWorm URL.
4. App validates that the URL is reachable and appears to be an EarWorm server.
5. App saves the server locally.
6. App loads the saved server inside an embedded web view.
7. User signs in through EarWorm's existing login page.
8. On future launches, the app skips server entry and goes directly to the saved server.
9. If the user wants to switch servers, they use a native "Change Server" action available from the login screen.

## Must-Have Features

### 1. First-Launch Server Setup

- Native input for a server URL
- Clear HTTPS-only requirement
- Input normalization for common mistakes:
  - trim whitespace
  - remove trailing slash
- Persist the last successfully validated server URL

### 2. EarWorm Server Validation

- The app must verify the target before launching the full web experience.
- Validation requirements:
  - URL must use `https://`
  - request must succeed against a public EarWorm-safe endpoint
  - response must match an expected EarWorm identity contract or known EarWorm auth-status shape
- If the existing public endpoints are not strong enough to uniquely identify EarWorm, implementation should add a dedicated public endpoint in EarWorm for client validation.

### 3. Embedded EarWorm Session

- Render EarWorm in `WKWebView`
- Load the saved server root or mobile entry path
- Preserve cookies/session state across app launches as allowed by the default web view data store
- Let EarWorm's existing login page and mobile interface handle authentication and navigation

### 4. Change Server Control

- Expose a native "Change Server" action on or before the login experience
- Allow the user to clear the saved server and return to the native connection screen
- Keep v1 as a one-active-server flow even if the internal storage model leaves room for more later

### 5. Connection and Error States

- Loading screen while validating or opening the web session
- Friendly errors for:
  - invalid URL
  - non-HTTPS URL
  - unreachable host
  - certificate/trust failure
  - reachable server that does not appear to be EarWorm
- Retry action after failure
- Optional open-in-Safari fallback for troubleshooting certificate trust during development

## Nice-to-Have Features

- Remember more than one validated EarWorm server in future versions
- Native server picker if multiple servers are later added
- Bonjour or LAN discovery if EarWorm gains a stable discovery story
- Share sheet or deep link that pre-fills a server URL

## Explicitly Out of Scope for V1

- Rebuilding EarWorm's mobile UI natively in SwiftUI
- Native playback, browsing, search, or playlist management screens
- Offline caching or downloads
- Multiple active saved servers in the user-facing experience
- App Store production hardening beyond personal TestFlight needs
- Android support

## Functional Requirements

### Connection Screen

- Show app name and one short explanation
- One text field for server URL
- One primary button to connect
- Inline validation feedback
- Optional example format such as `https://earworm.local:4533` or a tunnel URL

### Validation Behavior

- Do not accept plain HTTP
- Follow safe redirects only if the final destination remains HTTPS
- Store the normalized final server URL after validation
- Distinguish between "server not reachable" and "reachable but not EarWorm"

### Web Container Behavior

- Load the saved EarWorm server in a web view after validation
- Use the existing EarWorm login flow
- Preserve the signed-in session when possible
- Provide a minimal native overlay only for loading, fatal error recovery, and change-server access

### Settings and Recovery

- If the saved server fails on launch, show a recovery state with:
  - retry
  - change server
  - optional Safari fallback

## Non-Functional Requirements

- Minimize maintenance by keeping app logic thin
- Avoid introducing a duplicate auth stack in iOS
- Keep security posture simple:
  - HTTPS only
  - no hardcoded secrets
  - no local credential store beyond normal web session persistence
- Favor a straightforward SwiftUI shell with a `WKWebView` bridge rather than a heavy native architecture

## Jellyfin-Inspired Decisions

- Copy Swiftfin's pattern of:
  - user-supplied server URL
  - public endpoint validation before sign-in
  - saving the resolved server URL
- Do not copy Swiftfin's full native media-client scope
- Use Jellyfin's broader iOS lesson that self-hosted clients can succeed as thin native shells around server-owned experiences when the server already exposes a strong web/mobile UI
