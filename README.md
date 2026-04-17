# mobileworm

iPhone-first iOS client for EarWorm.

## Current Shape

mobileworm is a thin SwiftUI shell around EarWorm's existing mobile web interface:

- native first-launch server entry
- HTTPS-only EarWorm validation via `GET /api/auth/status`
- saved active server
- `WKWebView` container for EarWorm's existing login and mobile UI
- native recovery and Change Server flows

## Project Files

- `project.yml`: XcodeGen spec
- `Mobileworm/`: SwiftUI app sources
- `.ideas/`: App Freedom product and planning docs

## Generate the Xcode Project

```bash
xcodegen generate
```

## Current Local Limitation

This repo was scaffolded and the Xcode project was generated, but a simulator build could not be validated on this machine because the active developer tools only include Command Line Tools and not a full Xcode app installation.
