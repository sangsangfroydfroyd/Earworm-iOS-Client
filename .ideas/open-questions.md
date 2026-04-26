# Open Questions: mobileworm

> Generated from `.app-freedom/memory/`. Update through memory events and workflow checkpoints rather than editing this file by hand.

## Outstanding

- none

## Resolved

- none

## Implementation Safety

- Added and verified debug-only MobileWorm offline search QA navigation hook for simulator testing after implementing EarWorm offline search fallback.
- Implemented and verified offline MobileWorm playlist caching: native app-shell fallback, larger metadata cache, debug-gated QA playlist downloader, and offline simulator validation with downloaded AIFF files.
- Implemented MobileWorm offline launch support: saved-server reconnect failures now enter the cached web UI, MobileWorm metadata cache accepts larger playlist responses, and EarWorm web client now registers a service worker, uses cached auth/data fallbacks, saves MobileWorm playback state, and refreshes playlist data on reconnect.
- Added remote-command fallback handling so lock-screen next/previous first dispatches the page event, then clicks matching DOM transport controls if the track does not actually change.
- Strengthened MobileWorm now-playing control overrides so the injected WKWebView bridge reclaims Media Session handlers from the page and native skip-interval commands route to next/previous track actions.
- Patched MobileWorm now-playing integration so the WKWebView bridge advertises track-based media session actions and the native audio session publishes long-form audio playback state.
- Removed the native floating settings gear and added a WKWebView developer bridge so EarWorm's mobile settings page can open the native diagnostics sheet on demand.
- Moved MobileWorm diagnostics out of the global floating debug button and into a native Settings sheet under a Developer section. Added AppSettingsSheet with current server info and change-server action, replaced the root overlay icon with a settings gear, and verified in the iOS simulator that Settings opens first and Diagnostics launches from Developer.
- Used the new diagnostics report to fix remaining MobileWorm integration issues. Patched EarwormWebView URL loading to normalize same-page URLs so the app stops reloading https://host and https://host/ as different pages, which was causing auth churn and repeated provisional navigations. Rebuilt simulator and security check passed.
- Analyzed MobileWorm-only playback with in-app diagnostics. The copied diagnostics showed native now-playing flipping between playing and paused every 1-2 seconds while Safari playback stayed stable, pointing at the MobileWorm bridge layer rather than the EarWorm mobile UI. Patched WebNowPlayingManager to stop reactivating AVAudioSession on every now-playing update, and improved diagnostics to hook detached Audio() instances so future reports include real play/pause/error events from EarWorm's...
- Added in-app iOS diagnostics capture for MobileWorm with a shareable diagnostics sheet, WebView/app state snapshot, and event logging for navigation, auth, JS errors, console warnings/errors, audio element lifecycle, downloads, and now-playing updates. Verified by building/running in the iOS simulator and confirming the diagnostics UI opens and shows live state and captured events.
- Added native WKWebView bridges for original track downloads and lock-screen now-playing metadata/artwork. Downloads use authenticated URLSession writes into Documents/EarWorm Downloads exposed through Files; Info.plist now enables file sharing, opening in place, and audio background mode. Validated with xcodegen, iOS simulator build, built Info.plist inspection, scoped security checks, and simulator launch.
- Added native WKWebView bridges for original track downloads and lock-screen now-playing metadata/artwork. Downloads use authenticated URLSession writes into Documents/EarWorm Downloads exposed through Files; Info.plist now enables file sharing, opening in place, and audio background mode. Validated with xcodegen, iOS simulator build, built Info.plist inspection, and scoped security checks.
- Removed the brittle WKWebView artwork interception that blanked EarWorm images and replaced it with a native metadata cache bridge. MobileWorm now injects a bridge for cached EarWorm JSON payloads, persists those snapshots in the app cache directory, keeps native safe-area handling intact, and surfaces EarWorm branding in the iOS shell. Xcode 26.4 build passed, mobileworm security scan had no findings, and the simulator now renders the real EarWorm Home screen with artwork tiles again.
- Added a launch-scoped native artwork cache for the iOS wrapper, wired WKWebView image requests through a custom earworm-cache URL scheme, clear the cache on every app bootstrap, and renamed the built iOS product/display name to EarWorm while keeping the repo/app id mobileworm. Rebuilt with Xcode 26.4, security check passed, installed/launched on the iPhone 17 Pro simulator, and confirmed the renamed bootstrap screen appears.
- Fixed MobileWorm bottom safe-area behavior by disabling WKWebView UIScrollView automatic content inset adjustment and zeroing native scroll/content insets on create/update. Built with Xcode 26.4, security scan had no findings, installed/launched on iPhone 17 Pro simulator, and captured /tmp/mobileworm-safe-area.png showing the embedded Earworm bottom nav background reaches the physical bottom edge.
- Tightened fullscreen fit after bottom safe-area remained visible. Web destination now ignores safe areas at the RootView route level, RootView hides navigation toolbar and paints a safe fallback background, and WebContainerView uses overlay instead of safeAreaInset for unauthenticated Change Server so the WKWebView is no longer resized by native bottom insets. Simulator build/run and screenshot sanity check passed; security scan had no findings.
- Fixed remaining bottom safe-area bar by moving ignoresSafeArea(.container) onto the WKWebView itself, making the web content edge-to-edge on all sides while keeping native unauthenticated Change Server control in SwiftUI safe-area placement. iOS simulator build passed; mobileworm security scan had no findings.
- Finished native fullscreen container follow-up. mobileworm WebContainerView now lets the WKWebView ignore the top safe area so Earworm can render edge-to-edge under the notch/status area. iOS simulator build passed and mobileworm security scan had no findings.
- Made the one permitted mobileworm native-container edit: locked iPhone orientation to portrait in XcodeGen config, preserved signing team in project.yml, added WKWebView zoom/viewport suppression, regenerated the Xcode project, verified the built Info.plist orientation key, passed simulator build, and ran security check with no findings.
