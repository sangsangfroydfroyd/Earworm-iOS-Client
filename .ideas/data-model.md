# Data Model: mobileworm

## Overview

mobileworm is intentionally light on local data. In v1 it only needs to persist enough information to reconnect to an EarWorm server and manage the native shell around the web experience.

## Local Models

### SavedServer

```ts
SavedServer {
  id: string
  displayName: string
  baseURL: string
  lastValidatedAt: string | null
  validationSource: "authStatus" | "clientInfo"
}
```

Notes:

- `id` can initially be derived from the normalized URL
- `displayName` can default to `EarWorm`
- `validationSource` records which server contract was used

### AppRoute

```ts
AppRoute =
  | "connect"
  | "connecting"
  | "web"
  | "recovery"
```

### ValidationResult

```ts
ValidationResult {
  status: "success" | "invalidURL" | "insecureURL" | "networkFailure" | "notEarWorm" | "tlsFailure"
  normalizedURL: string | null
  serverName: string | null
  message: string
}
```

### WebLoadState

```ts
WebLoadState {
  phase: "idle" | "loading" | "loaded" | "failed"
  url: string | null
  errorMessage: string | null
}
```

## Persistent Storage

### V1

- one active `SavedServer`
- lightweight app-local persistence

### Future-Compatible Shape

If multi-server support becomes real, the storage can expand to:

```ts
SavedServersStore {
  activeServerID: string | null
  servers: SavedServer[]
}
```

## Remote Contract: Current EarWorm Validation

Current planned request:

```http
GET /api/auth/status
```

Expected response shape today:

```json
{
  "setupRequired": true,
  "serverName": "EarWorm",
  "authMethods": {
    "password": true,
    "passkey": false,
    "passkeySupportedOnOrigin": false,
    "passkeyNote": "...",
    "oidc": false,
    "oidcProvider": null,
    "oidcNote": null
  },
  "hasAnyPasskeys": false
}
```

Validation rule for v1:

- response must parse as JSON
- `serverName` must equal `EarWorm`

## Remote Contract: Recommended Future EarWorm Endpoint

Recommended dedicated public endpoint:

```http
GET /api/client/info
```

Recommended response:

```json
{
  "productId": "earworm",
  "productName": "EarWorm",
  "serverVersion": "0.0.0",
  "authEntrypoint": "/api/auth/status",
  "webEntrypoint": "/"
}
```

Why it helps:

- narrower and more stable than auth status
- easier for mobile clients and future thin clients to validate
- separates identity from login-state semantics

## Cookie and Session Model

mobileworm does not persist EarWorm credentials directly.

The session model is:

- EarWorm login happens in `WKWebView`
- cookies live in the web view's website data store
- app relaunch uses the same persistent website data store
- logout behavior remains primarily server/web-driven

## Change-Server Reset Rules

When the user changes server:

- remove the active saved server
- return route to `connect`
- optionally clear related web cookies for the old origin if stale-session issues appear during implementation

## Drift Watchpoints

- If EarWorm changes `/api/auth/status`, update this file and mobile validation logic together.
- If multi-server support is added, migrate persistence shape before the UI exposes it.
