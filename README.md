# mobileworm

iPhone-first iOS client for EarWorm.

## Current Shape

mobileworm is a thin SwiftUI shell around EarWorm's existing mobile web interface:

- native first-launch server entry
- HTTPS-only EarWorm validation via `GET /api/auth/status`
- saved active server
- `WKWebView` container for EarWorm's existing login and mobile UI
- native recovery flow
- EarWorm-styled Change Server control injected only on the web login screen

## Project Files

- `project.yml`: XcodeGen spec
- `Mobileworm/`: SwiftUI app sources
- `.ideas/`: App Freedom product and planning docs

## Generate the Xcode Project

```bash
xcodegen generate
```

## Local Validation

Built successfully with Xcode 26.4 against the iOS 26.4 simulator SDK:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.4.0.app/Contents/Developer xcodebuild -project mobileworm.xcodeproj -scheme mobileworm -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/mobileworm-derived build
```

The next validation pass should use a real HTTPS EarWorm server URL to verify server validation, saved-server persistence, and WebView login behavior end to end.
