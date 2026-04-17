# Tech Stack: mobileworm

## Chosen Stack

| Layer | Choice | Why It Fits | Alternatives Considered | Remaining Risk |
|--------|--------|-------------|--------------------------|----------------|
| App language | Swift 5.10+ | Native iOS path with the least friction for a small shell app | React Native, Flutter | Native/web boundary still needs careful testing |
| App UI shell | SwiftUI | Ideal for the small number of native screens in v1 | UIKit-only | `WKWebView` still needs a representable bridge |
| Embedded web runtime | `WKWebView` | Best fit for hosting EarWorm's existing mobile web UI | SFSafariViewController, external Safari only | Some app-to-web coordination is less transparent than a native stack |
| Web session persistence | `WKWebsiteDataStore.default()` | Persists cookies and web data across launches by default | nonpersistent web data store | Session debugging and reset behavior require explicit handling |
| Validation networking | `URLSession` | Simple and native for one lightweight validation flow | Alamofire | Minimal risk; keep it small |
| Local persistence | `UserDefaults` / `@AppStorage` for v1 server config | Small footprint for one active saved server | SwiftData, Keychain-first storage | Future multi-server support may outgrow the simplest model |
| Error recovery fallback | Safari handoff | Useful for cert/trust troubleshooting in early TestFlight use | no fallback | Can mask server issues if overused |
| EarWorm server contract | Existing `GET /api/auth/status` initially | Already public and includes `serverName: "EarWorm"` | new `/api/client/info` endpoint immediately | Existing endpoint is broader than ideal for client validation |

## Keep vs Add

### Keep

- EarWorm's existing mobile browser UI
- EarWorm's existing login page
- EarWorm's existing session-cookie behavior
- EarWorm's existing HTTPS LAN/tunnel access model

### Add in mobileworm

- SwiftUI connection screen
- validation service
- saved-server storage
- `WKWebView` bridge and container
- native recovery and change-server affordances

### Add in EarWorm if tightened during implementation

- a dedicated public client-validation endpoint for thin clients

## Stack Decisions

### Native Shell Strategy

- Decision: use SwiftUI for all native screens
- Why:
  - v1 only needs a few screens
  - fits iPhone-first TestFlight scope
  - keeps the app lightweight and modern

### Web Embedding Strategy

- Decision: embed EarWorm with `WKWebView`
- Why:
  - EarWorm already owns the authenticated experience
  - `WKWebView` keeps the app inside a branded iOS shell
  - supports persistent website data and cookies

### Persistence Strategy

- Decision: persist the active server in lightweight local storage
- Why:
  - only one active server matters in v1
  - configuration is tiny
  - avoids unnecessary database work before the app earns it
- Future path:
  - store an array of `SavedServer` values if multi-server support becomes real

### Authentication Strategy

- Decision: do not implement native credentials or native token exchange in v1
- Why:
  - EarWorm already has browser auth routes and UI
  - duplicating auth in iOS would create drift and more security surface

### Networking Security Strategy

- Decision: keep ATS defaults and only support HTTPS in v1
- Why:
  - directly matches product requirements
  - reduces insecure-local-network exceptions
  - keeps trust posture simple

## Recommended App Structure

```text
mobileworm/
|- App/
|  |- MobilewormApp.swift
|  |- AppRoute.swift
|  `- RootView.swift
|- Features/
|  |- Connect/
|  |- Recovery/
|  `- WebContainer/
|- Services/
|  |- SavedServerStore.swift
|  |- ServerValidationService.swift
|  `- WebSessionController.swift
|- Models/
|  |- SavedServer.swift
|  |- ValidationResult.swift
|  `- WebLoadState.swift
`- Support/
   `- WKWebViewRepresentable.swift
```

## Testing Stack

- XCTest for URL normalization and validation parsing
- lightweight UI tests for first-launch and change-server flows
- manual simulator/device QA against a real EarWorm server

## Packaging Fit

- Xcode project
- iPhone target first
- personal TestFlight distribution
