# Architecture: mobileworm

## Planning Context

- Planning readiness: 8/10
- Scope of this plan:
  - define the thinnest iPhone architecture that turns EarWorm's existing mobile browser experience into a native-feeling app
  - avoid rebuilding EarWorm's mobile UI in SwiftUI
  - keep first-run setup, validation, recovery, and server switching native
- Assumptions used to proceed:
  - EarWorm remains the source of truth for authentication and product UI
  - mobileworm is iPhone-first and distributed through personal TestFlight first
  - v1 only connects to `https://` EarWorm targets
  - one active saved server is enough for v1, but the storage model should not block multiple later
  - persistent web cookies via `WKWebsiteDataStore.default()` are desirable so the session survives launches
  - EarWorm's current `/api/auth/status` endpoint is sufficient for initial validation because it returns a browser-safe auth payload that includes `serverName: "EarWorm"`, but a dedicated client-validation endpoint is still the recommended cleanup

## System Shape

mobileworm should be a thin native shell with four responsibilities:

1. collect and normalize a server URL
2. validate that the target is an HTTPS EarWorm server
3. persist the chosen server for future launches
4. host EarWorm's existing mobile web session in `WKWebView`

Everything else should stay in EarWorm itself.

## Product Structure

```text
mobileworm iOS app
|- App shell (SwiftUI)
|  |- LaunchRouter
|  |- ConnectServerView
|  |- LoadingView
|  |- RecoveryView
|  |- WebContainerScreen
|     |- WKWebView bridge
|     |- native Change Server affordance
|
|- Services
|  |- ServerValidationService
|  |- SavedServerStore
|  |- WebSessionController
|
|- Models
|  |- SavedServer
|  |- ValidationResult
|  |- AppRoute
|  |- WebLoadState
|
`- EarWorm server
   |- public auth/validation route
   |- existing login page
   |- existing mobile routes and browser session cookies
```

## Module Boundaries

### 1. LaunchRouter

Responsibilities:

- decide the first screen at launch
- branch between first-run setup, reconnect loading, active web session, and failure recovery

Inputs:

- `SavedServerStore`
- last validation outcome
- current web loading state

Outputs:

- current app route

### 2. ConnectServerView

Responsibilities:

- capture the user's server URL
- explain HTTPS-only requirement
- trigger validation
- show validation and formatting errors

Rules:

- trim whitespace
- remove trailing slash
- reject non-HTTPS URLs before network calls

### 3. ServerValidationService

Responsibilities:

- normalize the user-entered URL
- perform a public network call to validate the target
- distinguish between transport failure and identity failure
- return the normalized final URL if redirects are accepted

Current validation contract:

- request `GET /api/auth/status`
- require:
  - HTTPS final URL
  - 200 response
  - JSON shape compatible with EarWorm browser auth status
  - `serverName === "EarWorm"`

Recommended future contract:

- add a dedicated public endpoint such as `/api/client/info`
- return a narrow identity payload intended for thin clients, for example:
  - product name
  - product id
  - server version
  - supported client capabilities

Why this split matters:

- `/api/auth/status` works today
- a dedicated endpoint is a cleaner long-term contract and reduces accidental coupling between mobile validation and browser-login behavior

### 4. SavedServerStore

Responsibilities:

- persist the active server locally
- expose read/write/clear operations
- leave room for future multiple-server support without forcing it into the UI now

v1 storage posture:

- store one active saved server in app-local persistent storage
- prefer a small Codable model over heavyweight persistence

### 5. WebContainerScreen

Responsibilities:

- host `WKWebView`
- load the saved EarWorm URL
- preserve cookies and session data
- expose native recovery controls around the web experience

What stays native:

- loading indicator before first meaningful paint
- top-level Change Server action
- fatal error recovery
- optional Open in Safari fallback

What stays web-owned:

- login UI
- authenticated navigation
- mobile browsing and playback UI
- server-authored errors inside the product surface

### 6. WebSessionController

Responsibilities:

- create the `WKWebViewConfiguration`
- use the default website data store for persistent web session behavior
- coordinate reloads, load failures, and server resets

## State and Data Flow

### First Launch

```text
App launch
-> no saved server
-> ConnectServerView
-> ServerValidationService
-> save normalized server
-> WebContainerScreen
-> EarWorm login page
```

### Subsequent Launch

```text
App launch
-> saved server exists
-> validate or attempt load
-> if healthy: WebContainerScreen
-> if unhealthy: RecoveryView
```

### Change Server

```text
User taps Change Server
-> clear active server
-> optionally clear web cookies for the old origin if needed
-> return to ConnectServerView
```

## Error Handling Strategy

### Validation Errors

- invalid URL
- non-HTTPS URL
- network unreachable
- TLS / trust failure
- reachable server that does not identify as EarWorm

These should be shown in native UI because the app has not committed to the web session yet.

### Web Loading Errors

- saved server unreachable on relaunch
- certificate trust changed
- server responds but web app fails to load

These should route to a native recovery view with:

- Retry
- Change Server
- Open in Safari

### Authentication Errors

These remain inside EarWorm's web UI unless they prevent the page from loading at all.

## Security Posture

- `https://` only in v1
- rely on Apple's App Transport Security default posture rather than punching broad exceptions
- no app-managed copy of EarWorm credentials
- use normal web session persistence from `WKWebView`
- keep server validation public and minimal
- do not attempt to bypass certificate trust failures inside the app

## Redirect Policy

- allow redirects during validation only if the final URL remains HTTPS
- persist the normalized final server URL so the app reconnects to the canonical location
- this mirrors the useful part of Swiftfin's server-connect behavior without adopting its full native client scope

## Dependency on EarWorm

EarWorm already provides most of what mobileworm needs:

- browser-safe authentication status
- login page
- session cookie flow
- mobile routes and responsive UI
- HTTPS LAN server

The main missing contract is explicit client validation. That should be treated as a small EarWorm-side support task in Stage 1 unless the team decides the current `/api/auth/status` payload is good enough to freeze as a client contract.

## Packaging and Distribution

- target: personal TestFlight
- no App Store-specific production hardening is required in this cycle beyond standard iOS app correctness
- the architecture should still avoid decisions that would make broader distribution harder later

## Testing and Validation Plan

### Unit-Level

- URL normalization
- HTTPS enforcement
- validation result parsing
- saved-server persistence behavior

### Integration-Level

- first-launch connect flow against a real EarWorm server
- relaunch with persisted server and existing cookie session
- change-server reset flow
- recovery behavior when saved server becomes unavailable

### Manual QA

- local HTTPS LAN URL
- tunnel HTTPS URL
- certificate trust failure behavior
- login/logout in web container
- iPhone safe-area, Dynamic Type, and rotation sanity

## Major Decisions and Trade-Offs

### Thin Wrapper vs Native Rebuild

- Chosen: thin wrapper around EarWorm mobile web UI
- Why:
  - EarWorm already has the mobile experience
  - avoids duplicate feature work and drift
  - minimizes iOS-specific maintenance
- Remaining risk:
  - some web interactions may feel less native than a full SwiftUI client

### Validation Against Existing Auth Status vs New Endpoint

- Chosen for immediate planning: validate against existing `/api/auth/status`
- Why:
  - it already exists
  - it is public
  - it already includes `serverName: "EarWorm"`
- Remaining risk:
  - this couples client identity checks to a browser-auth endpoint
- Recommendation:
  - introduce a dedicated public client-info endpoint in EarWorm during implementation

### Persistent Web Session vs App-Managed Tokens

- Chosen: persistent web session through `WKWebView`
- Why:
  - keeps auth ownership in EarWorm
  - avoids duplicating credential/token logic natively
  - matches the thin-shell goal
- Remaining risk:
  - session debugging is more web-oriented than native-token debugging
