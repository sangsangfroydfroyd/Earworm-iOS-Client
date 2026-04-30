import SwiftUI
import UIKit
import WebKit

struct EarwormWebView: UIViewRepresentable {
    let url: URL
    let onAuthenticationStateChanged: (Bool) -> Void
    let onOpenDiagnostics: () -> Void
    let onLoadFailure: (String) -> Void

    private static let debugSessionCookieName = "earworm_session"
    private static let diagnostics = AppDiagnosticsStore.shared

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onAuthenticationStateChanged: onAuthenticationStateChanged,
            onOpenDiagnostics: onOpenDiagnostics,
            onLoadFailure: onLoadFailure
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.setURLSchemeHandler(
            MobilewormDownloadSchemeHandler(),
            forURLScheme: "mobileworm-download"
        )
        configuration.setURLSchemeHandler(
            MobilewormImageCacheSchemeHandler(),
            forURLScheme: "mobileworm-image-cache"
        )
        configuration.userContentController.addUserScript(Self.viewportLockScript)
        configuration.userContentController.addUserScript(Self.imageCacheBridgeScript)
        configuration.userContentController.addUserScript(Self.bridgeScript)
        configuration.userContentController.addUserScript(Self.metadataCacheBridgeScript)
        configuration.userContentController.addUserScript(Self.downloadBridgeScript)
        configuration.userContentController.addUserScript(Self.nowPlayingBridgeScript)
        configuration.userContentController.addUserScript(Self.diagnosticsBridgeScript)
        configuration.userContentController.addUserScript(Self.developerBridgeScript)
        configuration.userContentController.add(context.coordinator, name: Coordinator.authStateHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.metadataCacheHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.downloadHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.nowPlayingHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.diagnosticsHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.developerHandler)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        WebNowPlayingManager.shared.attach(webView: webView)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        Self.disableNativeInsets(for: webView)
        webView.scrollView.delegate = context.coordinator
        Self.lockZoom(for: webView)
        context.coordinator.prepareInitialLoad(for: url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        Self.disableNativeInsets(for: webView)
        Self.lockZoom(for: webView)
        context.coordinator.prepareInitialLoad(for: url, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.authStateHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.metadataCacheHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.downloadHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.nowPlayingHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.diagnosticsHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.developerHandler)
        WebNowPlayingManager.shared.detach(webView: webView)
        webView.scrollView.delegate = nil
        coordinator.webView = nil
    }

    private static func lockZoom(for webView: WKWebView) {
        let scrollView = webView.scrollView
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1
        scrollView.bouncesZoom = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
    }

    private static func disableNativeInsets(for webView: WKWebView) {
        let scrollView = webView.scrollView
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }

    private static let viewportLockScript = WKUserScript(
        source: """
        (() => {
          const viewportContent = [
            "width=device-width",
            "initial-scale=1.0",
            "minimum-scale=1.0",
            "maximum-scale=1.0",
            "user-scalable=no",
            "viewport-fit=cover",
            "interactive-widget=resizes-content"
          ].join(", ");

          const applyViewportLock = () => {
            let viewport = document.querySelector("meta[name='viewport']");
            if (!viewport) {
              viewport = document.createElement("meta");
              viewport.name = "viewport";
              document.head?.appendChild(viewport);
            }
            viewport.setAttribute("content", viewportContent);
            document.documentElement.style.setProperty("-webkit-text-size-adjust", "100%");
            document.documentElement.style.setProperty("text-size-adjust", "100%");
          };

          applyViewportLock();
          document.addEventListener("DOMContentLoaded", applyViewportLock, { once: true });

          ["gesturestart", "gesturechange", "gestureend"].forEach((eventName) => {
            document.addEventListener(eventName, (event) => event.preventDefault(), { passive: false });
          });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private static let metadataCacheBridgeScript = WKUserScript(
        source: """
        (() => {
          const metadataCacheHandler = window.webkit?.messageHandlers?.mobilewormMetadataCache;
          if (!metadataCacheHandler) {
            return;
          }

          if (window.__mobilewormMetadataCacheBridgeInstalled) {
            return;
          }

          window.__mobilewormMetadataCacheBridgeInstalled = true;
          let nextRequestId = 0;
          const pending = new Map();

          const settle = (payload) => {
            const requestId = payload?.id;
            if (!requestId || !pending.has(requestId)) {
              return;
            }

            const { resolve, reject } = pending.get(requestId);
            pending.delete(requestId);

            if (payload.ok) {
              resolve(payload.body ?? null);
            } else {
              reject(new Error(payload.error || "Metadata cache bridge failed"));
            }
          };

          window.__mobilewormMetadataCacheBridgeResolve = settle;

          window.__mobilewormMetadataCache = {
            get(cacheKey) {
              return new Promise((resolve, reject) => {
                const id = `metadata-${++nextRequestId}`;
                pending.set(id, { resolve, reject });
                metadataCacheHandler.postMessage({
                  action: "get",
                  id,
                  cacheKey
                });
              });
            },
            put(cacheKey, body) {
              return new Promise((resolve, reject) => {
                const id = `metadata-${++nextRequestId}`;
                pending.set(id, { resolve, reject });
                metadataCacheHandler.postMessage({
                  action: "put",
                  id,
                  cacheKey,
                  body
                });
              });
            }
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private static let imageCacheBridgeScript = WKUserScript(
        source: """
        (() => {
          if (window.__mobilewormImageCacheBridgeInstalled) {
            return;
          }

          window.__mobilewormImageCacheBridgeInstalled = true;
          const cacheSchemePrefix = "mobileworm-image-cache:";
          const artworkPathPattern = /^\\/api\\/artwork\\/(album|artist)\\/\\d+$/;

          const cachedArtworkURL = (value) => {
            if (!value || typeof value !== "string" || value.startsWith(cacheSchemePrefix)) {
              return value;
            }

            let url;
            try {
              url = new URL(value, document.baseURI || window.location.href);
            } catch {
              return value;
            }

            if (
              url.origin !== window.location.origin ||
              !artworkPathPattern.test(url.pathname)
            ) {
              return value;
            }

            return `mobileworm-image-cache://image?url=${encodeURIComponent(url.href)}`;
          };

          const rewriteImage = (image) => {
            if (!(image instanceof HTMLImageElement)) {
              return;
            }

            const rawSource = image.getAttribute("src");
            const cachedSource = cachedArtworkURL(rawSource);
            if (cachedSource && cachedSource !== rawSource) {
              image.setAttribute("src", cachedSource);
            }
          };

          const srcDescriptor = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, "src");
          if (srcDescriptor?.get && srcDescriptor?.set) {
            Object.defineProperty(HTMLImageElement.prototype, "src", {
              configurable: true,
              enumerable: srcDescriptor.enumerable,
              get() {
                return srcDescriptor.get.call(this);
              },
              set(value) {
                return srcDescriptor.set.call(this, cachedArtworkURL(value));
              }
            });
          }

          const nativeSetAttribute = Element.prototype.setAttribute;
          Element.prototype.setAttribute = function(name, value) {
            if (this instanceof HTMLImageElement && String(name).toLowerCase() === "src") {
              return nativeSetAttribute.call(this, name, cachedArtworkURL(String(value)));
            }
            return nativeSetAttribute.apply(this, arguments);
          };

          const scan = (root = document) => {
            if (root instanceof HTMLImageElement) {
              rewriteImage(root);
              return;
            }
            root.querySelectorAll?.("img[src]").forEach(rewriteImage);
          };

          new MutationObserver((mutations) => {
            for (const mutation of mutations) {
              if (mutation.type === "attributes") {
                rewriteImage(mutation.target);
                continue;
              }
              mutation.addedNodes.forEach((node) => {
                if (node instanceof Element) {
                  scan(node);
                }
              });
            }
          }).observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["src"],
            childList: true,
            subtree: true
          });

          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", () => scan(), { once: true });
          } else {
            scan();
          }
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private static let downloadBridgeScript = WKUserScript(
        source: """
        (() => {
          const downloadHandler = window.webkit?.messageHandlers?.mobilewormDownloads;
          if (!downloadHandler || window.__mobilewormDownloadBridgeInstalled) {
            return;
          }

          window.__mobilewormDownloadBridgeInstalled = true;
          let nextRequestId = 0;
          const pending = new Map();

          window.__mobilewormDownloadBridgeResolve = (payload) => {
            const requestId = payload?.id;
            if (!requestId || !pending.has(requestId)) {
              return;
            }

            const { resolve, reject } = pending.get(requestId);
            pending.delete(requestId);
            if (payload.ok) {
              resolve({
                filename: payload.filename ?? "",
                path: payload.path ?? null,
                localUrl: payload.localUrl ?? null,
                url: payload.url ?? null,
                savedCount: payload.savedCount ?? 0,
                skippedCount: payload.skippedCount ?? 0,
                downloadedTrackIds: payload.downloadedTrackIds ?? [],
                downloadedPlaylistIds: payload.downloadedPlaylistIds ?? []
              });
            } else {
              reject(new Error(payload.error || "Download failed"));
            }
          };

          window.__mobilewormDownloads = {
            downloadTrack(payload) {
              return new Promise((resolve, reject) => {
                const id = `download-${++nextRequestId}`;
                pending.set(id, { resolve, reject });
                downloadHandler.postMessage({
                  action: "downloadTrack",
                  id,
                  ...payload
                });
              });
            },
            downloadPlaylist(payload) {
              return new Promise((resolve, reject) => {
                const id = `download-${++nextRequestId}`;
                pending.set(id, { resolve, reject });
                downloadHandler.postMessage({
                  action: "downloadPlaylist",
                  id,
                  ...payload
                });
              });
            },
            getDownloadStatus(payload) {
              return new Promise((resolve, reject) => {
                const id = `download-${++nextRequestId}`;
                pending.set(id, { resolve, reject });
                downloadHandler.postMessage({
                  action: "getDownloadStatus",
                  id,
                  ...payload
                });
              });
            },
            getLocalTrackUrl(payload) {
              return new Promise((resolve, reject) => {
                const id = `download-${++nextRequestId}`;
                pending.set(id, { resolve, reject });
                downloadHandler.postMessage({
                  action: "getLocalTrackUrl",
                  id,
                  ...payload
                });
              });
            }
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private static let nowPlayingBridgeScript = WKUserScript(
        source: """
        (() => {
          const nowPlayingHandler = window.webkit?.messageHandlers?.mobilewormNowPlaying;
          if (!nowPlayingHandler || window.__mobilewormNowPlayingBridgeInstalled) {
            return;
          }

          window.__mobilewormNowPlayingBridgeInstalled = true;
          const mediaSession = navigator.mediaSession;
          const diagnosticsHandler = window.webkit?.messageHandlers?.mobilewormDiagnostics;
          let lastNowPlayingState = null;
          const emitDiagnostics = (message, metadata = {}) => {
            diagnosticsHandler?.postMessage({
              event: "remote_command",
              message,
              metadata
            });
          };
          const summarizeState = () => ({
            title: lastNowPlayingState?.title ?? "",
            artistName: lastNowPlayingState?.artistName ?? "",
            isPlaying: lastNowPlayingState?.isPlaying ?? false
          });
          const sameTrack = (lhs, rhs) =>
            lhs.title === rhs.title &&
            lhs.artistName === rhs.artistName;
          const commandSucceeded = (command, before, after) => {
            switch (command) {
            case "nextTrack":
            case "previousTrack":
              return !sameTrack(before, after);
            case "play":
            case "pause":
            case "togglePlayPause":
              return before.isPlaying !== after.isPlaying;
            default:
              return !sameTrack(before, after) || before.isPlaying !== after.isPlaying;
            }
          };
          const candidateMatchers = {
            play: [/^play$/i, /resume/i],
            pause: [/^pause$/i],
            nextTrack: [/next/i, /skip next/i, /next track/i, /next song/i],
            previousTrack: [/previous/i, /prev/i, /back/i, /restart/i]
          };
          const isVisible = (element) => {
            if (!element || !element.isConnected) {
              return false;
            }

            const style = window.getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden") {
              return false;
            }

            return Boolean(
              element.offsetWidth ||
              element.offsetHeight ||
              element.getClientRects().length
            );
          };
          const elementLabel = (element) => [
            element.getAttribute("aria-label"),
            element.getAttribute("title"),
            element.getAttribute("name"),
            element.getAttribute("data-testid"),
            typeof element.className === "string" ? element.className : "",
            typeof element.id === "string" ? element.id : "",
            element.textContent
          ]
            .filter(Boolean)
            .join(" ")
            .replace(/\\s+/g, " ")
            .trim();
          const clickTransportControl = (command) => {
            const matchers = candidateMatchers[command] ?? [];
            if (!matchers.length) {
              return false;
            }

            const candidates = Array.from(
              document.querySelectorAll("button, [role='button'], a, input[type='button'], input[type='submit']")
            );

            for (const element of candidates) {
              if (!isVisible(element) || element.disabled) {
                continue;
              }

              const label = elementLabel(element);
              if (!label || !matchers.some((matcher) => matcher.test(label))) {
                continue;
              }

              element.click();
              emitDiagnostics("Clicked DOM transport fallback.", {
                command,
                label
              });
              return true;
            }

            emitDiagnostics("No DOM transport fallback matched.", { command });
            return false;
          };
          const applyMediaElementFallback = (command) => {
            const media = document.querySelector("audio, video");
            if (!(media instanceof HTMLMediaElement)) {
              return false;
            }

            if (command === "play") {
              media.play?.();
              return true;
            }

            if (command === "pause") {
              media.pause?.();
              return true;
            }

            return false;
          };
          const dispatchRemoteCommand = (command) => {
            const stateBefore = summarizeState();
            emitDiagnostics("Received remote command.", {
              command,
              title: stateBefore.title,
              artistName: stateBefore.artistName,
              isPlaying: String(stateBefore.isPlaying)
            });

            window.dispatchEvent(new CustomEvent("mobileworm:remote-command", {
              detail: { command }
            }));

            setTimeout(() => {
              const stateAfter = summarizeState();
              if (commandSucceeded(command, stateBefore, stateAfter)) {
                emitDiagnostics("Remote command changed now playing state.", {
                  command,
                  title: stateAfter.title,
                  artistName: stateAfter.artistName,
                  isPlaying: String(stateAfter.isPlaying)
                });
                return;
              }

              if (clickTransportControl(command)) {
                return;
              }

              if (applyMediaElementFallback(command)) {
                emitDiagnostics("Applied media element fallback.", { command });
              }
            }, 250);
          };
          const nativeSetActionHandler = mediaSession?.setActionHandler?.bind(mediaSession);
          const setActionHandler = (action, handler) => {
            if (!nativeSetActionHandler) {
              return;
            }

            try {
              nativeSetActionHandler(action, handler);
            } catch (_) {
              return;
            }
          };
          const configureActionHandlers = () => {
            setActionHandler("play", () => dispatchRemoteCommand("play"));
            setActionHandler("pause", () => dispatchRemoteCommand("pause"));
            setActionHandler("nexttrack", () => dispatchRemoteCommand("nextTrack"));
            setActionHandler("previoustrack", () => dispatchRemoteCommand("previousTrack"));
            setActionHandler("seekforward", null);
            setActionHandler("seekbackward", null);
            setActionHandler("seekto", null);
          };
          const syncMediaSession = (payload) => {
            lastNowPlayingState = {
              title: payload.title ?? "",
              artistName: payload.artistName ?? "",
              isPlaying: Boolean(payload.isPlaying)
            };
            if (!mediaSession) {
              return;
            }
            configureActionHandlers();

            if (window.MediaMetadata) {
              try {
                mediaSession.metadata = new MediaMetadata({
                  title: payload.title ?? "",
                  artist: payload.artistName ?? "",
                  album: payload.albumTitle ?? "",
                  artwork: payload.artworkUrl ? [{ src: payload.artworkUrl }] : []
                });
              } catch (_) {
                mediaSession.metadata = null;
              }
            }

            if ("playbackState" in mediaSession) {
              mediaSession.playbackState = payload.isPlaying ? "playing" : "paused";
            }
          };
          const clearMediaSession = () => {
            lastNowPlayingState = null;
            if (!mediaSession) {
              return;
            }

            try {
              mediaSession.metadata = null;
            } catch (_) {
              return;
            }

            if ("playbackState" in mediaSession) {
              mediaSession.playbackState = "none";
            }
          };

          if (mediaSession && nativeSetActionHandler && !window.__mobilewormMediaSessionPatched) {
            window.__mobilewormMediaSessionPatched = true;
            mediaSession.setActionHandler = (action, handler) => {
              switch (action) {
              case "play":
                return setActionHandler(action, () => dispatchRemoteCommand("play"));
              case "pause":
                return setActionHandler(action, () => dispatchRemoteCommand("pause"));
              case "nexttrack":
                return setActionHandler(action, () => dispatchRemoteCommand("nextTrack"));
              case "previoustrack":
                return setActionHandler(action, () => dispatchRemoteCommand("previousTrack"));
              case "seekforward":
              case "seekbackward":
              case "seekto":
                return setActionHandler(action, null);
              default:
                return setActionHandler(action, handler);
              }
            };
          }

          configureActionHandlers();

          window.__mobilewormNowPlaying = {
            update(payload) {
              syncMediaSession(payload);
              nowPlayingHandler.postMessage({
                action: "update",
                ...payload
              });
            },
            clear() {
              clearMediaSession();
              nowPlayingHandler.postMessage({ action: "clear" });
            }
          };

          window.__mobilewormNowPlayingCommand = dispatchRemoteCommand;
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private static let bridgeScript = WKUserScript(
        source: """
        (() => {
          if (window.__mobilewormBridgeInstalled) {
            window.__mobilewormBridgeSync?.();
            return;
          }

          window.__mobilewormBridgeInstalled = true;

          const authKey = "earworm_user";
          const authHandler = window.webkit?.messageHandlers?.mobilewormAuthState;

          const isAuthenticated = () => Boolean(window.localStorage?.getItem(authKey));

          const postAuthState = () => {
            authHandler?.postMessage({
              authenticated: isAuthenticated(),
              path: window.location.pathname
            });
          };

          const sync = () => {
            postAuthState();
          };

          window.__mobilewormBridgeSync = sync;

          const storagePrototype = Object.getPrototypeOf(window.localStorage);
          const originalSetItem = storagePrototype.setItem;
          storagePrototype.setItem = function(key, value) {
            originalSetItem.apply(this, arguments);
            if (this === window.localStorage && key === authKey) {
              setTimeout(sync, 0);
            }
          };

          const originalRemoveItem = storagePrototype.removeItem;
          storagePrototype.removeItem = function(key) {
            originalRemoveItem.apply(this, arguments);
            if (this === window.localStorage && key === authKey) {
              setTimeout(sync, 0);
            }
          };

          new MutationObserver(sync).observe(document.documentElement, {
            childList: true,
            subtree: true
          });

          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", sync, { once: true });
          } else {
            sync();
          }
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    private static let diagnosticsBridgeScript = WKUserScript(
        source: """
        (() => {
          const diagnosticsHandler = window.webkit?.messageHandlers?.mobilewormDiagnostics;
          if (!diagnosticsHandler || window.__mobilewormDiagnosticsInstalled) {
            return;
          }

          window.__mobilewormDiagnosticsInstalled = true;

          const stringify = (value) => {
            if (typeof value === "string") {
              return value;
            }
            if (value instanceof Error) {
              return `${value.name}: ${value.message}`;
            }
            try {
              return JSON.stringify(value);
            } catch {
              return String(value);
            }
          };

          const send = (event, payload = {}) => {
            try {
              diagnosticsHandler.postMessage({
                event,
                href: window.location.href,
                path: window.location.pathname,
                title: document.title,
                ...payload
              });
            } catch {
              // Diagnostics are best-effort only.
            }
          };

          const originalWarn = console.warn;
          console.warn = (...args) => {
            send("console_warn", { message: args.map(stringify).join(" ") });
            return originalWarn.apply(console, args);
          };

          const originalError = console.error;
          console.error = (...args) => {
            send("console_error", { message: args.map(stringify).join(" ") });
            return originalError.apply(console, args);
          };

          window.addEventListener("error", (event) => {
            send("window_error", {
              message: event.message || "Unknown window error",
              source: event.filename || "",
              line: String(event.lineno || 0),
              column: String(event.colno || 0)
            });
          });

          window.addEventListener("unhandledrejection", (event) => {
            send("unhandled_rejection", {
              message: stringify(event.reason)
            });
          });

          const describeAudio = (audio) => ({
            currentSrc: audio.currentSrc || audio.src || "",
            paused: String(audio.paused),
            currentTime: String(audio.currentTime || 0),
            readyState: String(audio.readyState),
            networkState: String(audio.networkState),
            error: audio.error ? `${audio.error.code}` : ""
          });

          const attachAudioDiagnostics = (audio) => {
            if (!audio || audio.__mobilewormDiagnosticsAttached) {
              return;
            }

            audio.__mobilewormDiagnosticsAttached = true;
            [
              "loadstart",
              "loadedmetadata",
              "canplay",
              "play",
              "playing",
              "pause",
              "waiting",
              "stalled",
              "suspend",
              "abort",
              "ended",
              "error"
            ].forEach((name) => {
              audio.addEventListener(name, () => {
                send("audio_event", {
                  message: name,
                  ...describeAudio(audio)
                });
              });
            });
          };

          const OriginalAudio = window.Audio;
          if (typeof OriginalAudio === "function") {
            const PatchedAudio = function(...args) {
              const audio = new OriginalAudio(...args);
              attachAudioDiagnostics(audio);
              return audio;
            };
            PatchedAudio.prototype = OriginalAudio.prototype;
            Object.setPrototypeOf(PatchedAudio, OriginalAudio);
            window.Audio = PatchedAudio;
          }

          const scanForAudio = () => {
            document.querySelectorAll("audio").forEach(attachAudioDiagnostics);
          };

          new MutationObserver(scanForAudio).observe(document.documentElement, {
            childList: true,
            subtree: true
          });

          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", () => {
              send("dom_content_loaded");
              scanForAudio();
            }, { once: true });
          } else {
            send("document_ready", { readyState: document.readyState });
            scanForAudio();
          }
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    private static let developerBridgeScript = WKUserScript(
        source: """
        (() => {
          const developerHandler = window.webkit?.messageHandlers?.mobilewormDeveloper;
          if (!developerHandler || window.__mobilewormDeveloperBridgeInstalled) {
            return;
          }

          window.__mobilewormDeveloperBridgeInstalled = true;
          window.__mobilewormDeveloper = {
            openDiagnostics() {
              developerHandler.postMessage({ action: "openDiagnostics" });
            }
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        static let authStateHandler = "mobilewormAuthState"
        static let metadataCacheHandler = "mobilewormMetadataCache"
        static let downloadHandler = "mobilewormDownloads"
        static let nowPlayingHandler = "mobilewormNowPlaying"
        static let diagnosticsHandler = "mobilewormDiagnostics"
        static let developerHandler = "mobilewormDeveloper"

        private let onAuthenticationStateChanged: (Bool) -> Void
        private let onOpenDiagnostics: () -> Void
        private let onLoadFailure: (String) -> Void
        private var pendingURL: URL?
        private var loadingURL: String?
        private var debugCookieSeededHost: String?
        private var debugCookieSeedingInFlight = false
        private var debugDownloadPlaylistIdsStarted: Set<Int> = []
        private var debugSearchQueryApplied = false
        private var imageCacheSyncStartedRoots: Set<String> = []
        weak var webView: WKWebView?

        init(
            onAuthenticationStateChanged: @escaping (Bool) -> Void,
            onOpenDiagnostics: @escaping () -> Void,
            onLoadFailure: @escaping (String) -> Void
        ) {
            self.onAuthenticationStateChanged = onAuthenticationStateChanged
            self.onOpenDiagnostics = onOpenDiagnostics
            self.onLoadFailure = onLoadFailure
        }

        func prepareInitialLoad(for url: URL, in webView: WKWebView) {
            let targetURL = Self.normalizedLoadTarget(for: url)
            let currentLoadingURL = Self.normalizedLoadTarget(for: loadingURL)
            let currentWebViewURL = Self.normalizedLoadTarget(for: webView.url)
            guard targetURL != currentLoadingURL, targetURL != currentWebViewURL else {
                return
            }

            pendingURL = url
            Self.recordDiagnostic(
                .info,
                category: "webview",
                message: "Preparing initial EarWorm load.",
                metadata: ["url": url.absoluteString]
            )
            seedDebugSessionCookieIfNeeded(for: url, in: webView)
        }

        private func seedDebugSessionCookieIfNeeded(for url: URL, in webView: WKWebView) {
            guard
                let host = url.host,
                let token = ProcessInfo.processInfo.environment["EARWORM_SESSION_TOKEN"],
                !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                debugCookieSeededHost != host
            else {
                loadPendingURLIfReady(in: webView)
                return
            }

            guard !debugCookieSeedingInFlight else {
                return
            }

            debugCookieSeedingInFlight = true
            let properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/api",
                .name: EarwormWebView.debugSessionCookieName,
                .value: token,
                .secure: (url.scheme?.lowercased() == "https"),
                .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 30),
            ]

            guard let cookie = HTTPCookie(properties: properties) else {
                debugCookieSeedingInFlight = false
                loadPendingURLIfReady(in: webView)
                return
            }

            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { [weak self, weak webView] in
                guard let self, let webView else {
                    return
                }

                self.debugCookieSeededHost = host
                self.debugCookieSeedingInFlight = false
                self.loadPendingURLIfReady(in: webView)
            }
        }

        private func loadPendingURLIfReady(in webView: WKWebView) {
            guard !debugCookieSeedingInFlight, let pendingURL else {
                return
            }

            loadingURL = Self.normalizedLoadTarget(for: pendingURL)
            self.pendingURL = nil
            Self.recordDiagnostic(
                .info,
                category: "webview",
                message: "Loading EarWorm URL in WKWebView.",
                metadata: ["url": pendingURL.absoluteString]
            )
            webView.load(URLRequest(url: pendingURL))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateSnapshot(for: webView)
            Self.recordDiagnostic(
                .info,
                category: "navigation",
                message: "WKWebView started provisional navigation.",
                metadata: ["url": webView.url?.absoluteString ?? loadingURL ?? "unknown"]
            )
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateSnapshot(for: webView)
            Self.recordDiagnostic(
                .info,
                category: "navigation",
                message: "WKWebView committed navigation.",
                metadata: ["url": webView.url?.absoluteString ?? "unknown"]
            )
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loadingURL = nil
            updateSnapshot(for: webView)
            handleLoadFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loadingURL = nil
            updateSnapshot(for: webView)
            handleLoadFailure(error)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadingURL = webView.url?.absoluteString
            webView.evaluateJavaScript("window.__mobilewormBridgeSync?.()")
            syncDebugBrowserSessionIfNeeded(in: webView)
            runDebugPlaylistDownloadIfNeeded(in: webView)
            runDebugSearchNavigationIfNeeded(in: webView)
            refreshCachedAppShellIfNeeded(for: webView.url)
            syncImageCacheIfNeeded(for: webView.url)
            updateSnapshot(for: webView)
            Self.recordDiagnostic(
                .info,
                category: "navigation",
                message: "WKWebView finished navigation.",
                metadata: [
                    "url": webView.url?.absoluteString ?? "unknown",
                    "title": webView.title ?? "",
                ]
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard
                navigationResponse.isForMainFrame,
                let httpResponse = navigationResponse.response as? HTTPURLResponse,
                httpResponse.statusCode >= 500,
                let failedURL = httpResponse.url
            else {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            loadCachedAppShellFallback(
                in: webView,
                url: failedURL,
                reason: "HTTP \(httpResponse.statusCode)"
            )
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            updateSnapshot(for: webView)
            Self.recordDiagnostic(
                .error,
                category: "webview",
                message: "WKWebView web content process terminated."
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            nil
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.zoomScale = 1
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.authStateHandler:
                guard
                    let body = message.body as? [String: Any],
                    let authenticated = body["authenticated"] as? Bool
                else {
                    return
                }
                onAuthenticationStateChanged(authenticated)
                EarwormWebView.diagnostics.updateAuthenticationState(authenticated)
                Self.recordDiagnostic(
                    authenticated ? .info : .warning,
                    category: "auth",
                    message: authenticated
                        ? "Web app reported authenticated state."
                        : "Web app reported signed-out state.",
                    metadata: ["path": (body["path"] as? String) ?? ""]
                )
            case Self.metadataCacheHandler:
                guard
                    let body = message.body as? [String: Any],
                    let action = body["action"] as? String,
                    let requestId = body["id"] as? String,
                    let cacheKey = body["cacheKey"] as? String
                else {
                    return
                }

                Task {
                    do {
                        switch action {
                        case "get":
                            let cachedBody = await WebMetadataCache.shared.cachedBody(for: cacheKey)
                            await sendMetadataCacheResponse(
                                requestId: requestId,
                                ok: true,
                                body: cachedBody,
                                errorMessage: nil
                            )
                        case "put":
                            guard let body = body["body"] as? String else {
                                await sendMetadataCacheResponse(
                                    requestId: requestId,
                                    ok: false,
                                    body: nil,
                                    errorMessage: "Metadata cache body was missing."
                                )
                                return
                            }

                            await WebMetadataCache.shared.store(body: body, for: cacheKey)
                            await sendMetadataCacheResponse(
                                requestId: requestId,
                                ok: true,
                                body: nil,
                                errorMessage: nil
                            )
                        default:
                            await sendMetadataCacheResponse(
                                requestId: requestId,
                                ok: false,
                                body: nil,
                                errorMessage: "Unknown metadata cache action."
                            )
                        }
                    }
                }
            case Self.downloadHandler:
                guard
                    let body = message.body as? [String: Any],
                    let requestId = body["id"] as? String
                else {
                    return
                }

                Self.recordDiagnostic(
                    .debug,
                    category: "downloads",
                    message: "Received MobileWorm download bridge request.",
                    metadata: [
                        "action": (body["action"] as? String) ?? "unknown",
                        "requestId": requestId,
                    ]
                )

                Task {
                    await handleDownloadMessage(body, requestId: requestId)
                }
            case Self.nowPlayingHandler:
                guard
                    let body = message.body as? [String: Any],
                    let action = body["action"] as? String
                else {
                    return
                }

                if action == "clear" {
                    EarwormWebView.diagnostics.updateNowPlayingSummary(nil)
                    Self.recordDiagnostic(.info, category: "now_playing", message: "Cleared now playing state.")
                    Task {
                        await WebNowPlayingManager.shared.clear()
                    }
                    return
                }

                guard action == "update", let payload = WebNowPlayingPayload(messageBody: body) else {
                    return
                }

                EarwormWebView.diagnostics.updateNowPlayingSummary(
                    "\(payload.title) — \(payload.artistName) | playing=\(payload.isPlaying)"
                )
                Self.recordDiagnostic(
                    .info,
                    category: "now_playing",
                    message: "Updated native now playing state.",
                    metadata: [
                        "title": payload.title,
                        "artist": payload.artistName,
                        "isPlaying": payload.isPlaying ? "true" : "false",
                        "position": String(payload.position),
                        "duration": String(payload.duration),
                    ]
                )

                Task {
                    let cookies = await cookies(for: payload.artworkURL)
                    await WebNowPlayingManager.shared.update(payload: payload, cookies: cookies)
                }
            case Self.diagnosticsHandler:
                guard let body = message.body as? [String: Any] else {
                    return
                }
                handleDiagnosticsMessage(body)
            case Self.developerHandler:
                guard
                    let body = message.body as? [String: Any],
                    let action = body["action"] as? String,
                    action == "openDiagnostics"
                else {
                    return
                }

                Self.recordDiagnostic(
                    .info,
                    category: "developer",
                    message: "Opening native MobileWorm diagnostics from EarWorm settings."
                )
                Task { @MainActor in
                    onOpenDiagnostics()
                }
            default:
                break
            }
        }

        private func handleDownloadMessage(_ body: [String: Any], requestId: String) async {
            guard let action = body["action"] as? String else {
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: false,
                    filename: nil,
                    path: nil,
                    localUrl: nil,
                    savedCount: nil,
                    skippedCount: nil,
                    errorMessage: "Unknown download action."
                )
                return
            }

            switch action {
            case "downloadTrack":
                await handleTrackDownloadMessage(body, requestId: requestId)
            case "downloadPlaylist":
                await handlePlaylistDownloadMessage(body, requestId: requestId)
            case "getDownloadStatus":
                await handleDownloadStatusMessage(body, requestId: requestId)
            case "getLocalTrackUrl":
                await handleLocalTrackURLMessage(body, requestId: requestId)
            default:
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: false,
                    filename: nil,
                    path: nil,
                    localUrl: nil,
                    savedCount: nil,
                    skippedCount: nil,
                    errorMessage: "Unknown download action."
                )
            }
        }

        private func handleTrackDownloadMessage(_ body: [String: Any], requestId: String) async {
            guard
                let urlString = body["url"] as? String,
                let sourceURL = URL(string: urlString)
            else {
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: false,
                    filename: nil,
                    path: nil,
                    localUrl: nil,
                    savedCount: nil,
                    skippedCount: nil,
                    errorMessage: "Download URL was missing."
                )
                return
            }

            let filename = (body["filename"] as? String) ?? "Track.audio"
            let trackId = intValue(body["trackId"])
            let cookies = await cookies(for: sourceURL)

            do {
                let downloadedFile = try await WebDownloadManager.shared.downloadTrack(
                    from: sourceURL,
                    filename: filename,
                    cookies: cookies,
                    trackId: trackId
                )
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: true,
                    filename: downloadedFile.filename,
                    path: downloadedFile.url.path,
                    localUrl: downloadedFile.localPlaybackURL,
                    savedCount: nil,
                    skippedCount: nil,
                    errorMessage: nil
                )
            } catch {
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: false,
                    filename: nil,
                    path: nil,
                    localUrl: nil,
                    savedCount: nil,
                    skippedCount: nil,
                    errorMessage: error.localizedDescription
                )
            }
        }

        private func handlePlaylistDownloadMessage(_ body: [String: Any], requestId: String) async {
            guard let trackPayloads = body["tracks"] as? [[String: Any]] else {
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: false,
                    filename: nil,
                    path: nil,
                    localUrl: nil,
                    savedCount: nil,
                    skippedCount: nil,
                    errorMessage: "Playlist download tracks were missing."
                )
                return
            }

            var downloadRequests: [WebPlaylistTrackDownloadRequest] = []
            var skippedCount = (body["skippedTrackIds"] as? [Any])?.count ?? 0
            for payload in trackPayloads {
                guard
                    let trackId = intValue(payload["trackId"]),
                    let urlString = payload["url"] as? String,
                    let sourceURL = URL(string: urlString),
                    let filename = payload["filename"] as? String
                else {
                    skippedCount += 1
                    continue
                }

                let cookies = await cookies(for: sourceURL)
                downloadRequests.append(WebPlaylistTrackDownloadRequest(
                    trackId: trackId,
                    sourceURL: sourceURL,
                    filename: filename,
                    cookies: cookies
                ))
            }

            let playlistName = (body["playlistName"] as? String) ?? "Playlist"
            let playlistId = intValue(body["playlistId"])
            do {
                let downloadedPlaylist = try await WebDownloadManager.shared.downloadPlaylist(
                    named: playlistName,
                    playlistId: playlistId,
                    tracks: downloadRequests
                )
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: true,
                    filename: downloadedPlaylist.folderName,
                    path: downloadedPlaylist.url.path,
                    localUrl: nil,
                    savedCount: downloadedPlaylist.savedCount,
                    skippedCount: skippedCount + downloadedPlaylist.skippedCount,
                    errorMessage: nil
                )
            } catch {
                await sendDownloadResponse(
                    requestId: requestId,
                    ok: false,
                    filename: nil,
                    path: nil,
                    localUrl: nil,
                    savedCount: nil,
                    skippedCount: skippedCount,
                    errorMessage: error.localizedDescription
                )
            }
        }

        private func handleDownloadStatusMessage(_ body: [String: Any], requestId: String) async {
            let trackIds = intArrayValue(body["trackIds"])
            let playlistIds = intArrayValue(body["playlistIds"])
            let downloadedTrackIds = await WebDownloadManager.shared.downloadedTrackIds(from: trackIds)
            let downloadedPlaylistIds = await WebDownloadManager.shared.downloadedPlaylistIds(from: playlistIds)
            await sendDownloadStatusResponse(
                requestId: requestId,
                ok: true,
                downloadedTrackIds: downloadedTrackIds,
                downloadedPlaylistIds: downloadedPlaylistIds,
                localUrl: nil,
                errorMessage: nil
            )
        }

        private func handleLocalTrackURLMessage(_ body: [String: Any], requestId: String) async {
            guard let trackId = intValue(body["trackId"]) else {
                await sendDownloadStatusResponse(
                    requestId: requestId,
                    ok: false,
                    downloadedTrackIds: [],
                    downloadedPlaylistIds: [],
                    localUrl: nil,
                    errorMessage: "Track id was missing."
                )
                return
            }

            let localUrl = await WebDownloadManager.shared.localPlaybackURLString(trackId: trackId)
            await sendDownloadStatusResponse(
                requestId: requestId,
                ok: true,
                downloadedTrackIds: [],
                downloadedPlaylistIds: [],
                localUrl: localUrl,
                errorMessage: nil
            )
        }

        private func intValue(_ value: Any?) -> Int? {
            if let value = value as? Int {
                return value
            }
            if let value = value as? NSNumber {
                return value.intValue
            }
            return nil
        }

        private func intArrayValue(_ value: Any?) -> [Int] {
            if let values = value as? [Int] {
                return values
            }
            if let values = value as? [NSNumber] {
                return values.map(\.intValue)
            }
            if let values = value as? [Any] {
                return values.compactMap(intValue)
            }
            return []
        }

        private func cookies(for url: URL?) async -> [HTTPCookie] {
            guard let cookieStore = await MainActor.run(body: {
                webView?.configuration.websiteDataStore.httpCookieStore
            }) else {
                return []
            }

            let cookies = await withCheckedContinuation { continuation in
                cookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }

            guard let url else {
                return cookies
            }

            return cookies.filter { cookie in
                cookieMatches(cookie, url: url)
            }
        }

        private func cookieMatches(_ cookie: HTTPCookie, url: URL) -> Bool {
            guard let host = url.host?.lowercased() else {
                return false
            }

            let domain = cookie.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            let hostMatches = host == domain || host.hasSuffix(".\(domain)")
            let pathMatches = url.path.hasPrefix(cookie.path)
            return hostMatches && pathMatches
        }

        private func handleLoadFailure(_ error: Error) {
            if (error as NSError).code == URLError.cancelled.rawValue {
                return
            }

            let message = error.localizedDescription
            if let webView, let failedURL = webView.url ?? URL(string: loadingURL ?? "") {
                loadCachedAppShellFallback(in: webView, url: failedURL, reason: message)
                return
            }

            EarwormWebView.diagnostics.markLoadFailure(message)
            Self.recordDiagnostic(
                .error,
                category: "navigation",
                message: "WKWebView load failed.",
                metadata: ["error": message]
            )
            onLoadFailure(error.localizedDescription)
        }

        private func refreshCachedAppShellIfNeeded(for url: URL?) {
            guard
                let url,
                let scheme = url.scheme?.lowercased(),
                scheme == "https" || scheme == "http"
            else {
                return
            }

            Task {
                await WebAppShellCache.shared.refresh(from: url)
            }
        }

        private func syncImageCacheIfNeeded(for url: URL?) {
            guard
                let url,
                let scheme = url.scheme?.lowercased(),
                scheme == "https" || scheme == "http",
                let rootURL = rootURL(for: url)
            else {
                return
            }

            let rootKey = rootURL.absoluteString
            guard !imageCacheSyncStartedRoots.contains(rootKey) else {
                return
            }

            imageCacheSyncStartedRoots.insert(rootKey)
            Self.recordDiagnostic(
                .info,
                category: "image_cache",
                message: "Starting MobileWorm artwork cache sync.",
                metadata: ["serverURL": rootKey]
            )

            Task {
                let cookies = await cookies(for: rootURL)
                await WebImageCache.shared.syncLibraryArtwork(from: rootURL, cookies: cookies)
                Self.recordDiagnostic(
                    .info,
                    category: "image_cache",
                    message: "Finished MobileWorm artwork cache sync.",
                    metadata: ["serverURL": rootKey]
                )
            }
        }

        private func loadCachedAppShellFallback(in webView: WKWebView, url: URL, reason: String) {
            Self.recordDiagnostic(
                .warning,
                category: "webview",
                message: "Attempting cached EarWorm app shell fallback.",
                metadata: [
                    "url": url.absoluteString,
                    "reason": reason,
                ]
            )

            Task {
                guard let cachedHTML = await WebAppShellCache.shared.cachedHTML(for: url) else {
                    await MainActor.run {
                        EarwormWebView.diagnostics.markLoadFailure(reason)
                        Self.recordDiagnostic(
                            .error,
                            category: "webview",
                            message: "No cached EarWorm app shell was available.",
                            metadata: ["url": url.absoluteString]
                        )
                        onLoadFailure(reason)
                    }
                    return
                }

                await MainActor.run {
                    webView.loadHTMLString(cachedHTML, baseURL: url)
                    Self.recordDiagnostic(
                        .info,
                        category: "webview",
                        message: "Loaded cached EarWorm app shell fallback.",
                        metadata: ["url": url.absoluteString]
                    )
                }
            }
        }

        private func rootURL(for url: URL) -> URL? {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }

            components.path = "/"
            components.query = nil
            components.fragment = nil
            return components.url
        }

        private func syncDebugBrowserSessionIfNeeded(in webView: WKWebView) {
            guard
                ProcessInfo.processInfo.environment["EARWORM_SESSION_TOKEN"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false
            else {
                return
            }

            let script = """
            (() => {
              const userKey = "earworm_user";
              const authSourceKey = "earworm_auth_source";
              const authProviderKey = "earworm_auth_provider";

              if (window.localStorage?.getItem(userKey)) {
                window.__mobilewormBridgeSync?.();
                return;
              }

              fetch("/api/auth/me", { credentials: "same-origin" })
                .then((response) => {
                  if (!response.ok) {
                    throw new Error(`HTTP ${response.status}`);
                  }
                  return response.json();
                })
                .then((payload) => {
                  if (!payload?.user || !payload?.session?.source) {
                    return;
                  }

                  window.localStorage.setItem(userKey, JSON.stringify(payload.user));
                  window.localStorage.setItem(authSourceKey, payload.session.source);

                  if (payload.session.provider) {
                    window.localStorage.setItem(authProviderKey, payload.session.provider);
                  } else {
                    window.localStorage.removeItem(authProviderKey);
                  }

                  window.dispatchEvent(new StorageEvent("storage", { key: userKey }));
                  window.__mobilewormBridgeSync?.();
                })
                .catch(() => undefined);
            })();
            """

            webView.evaluateJavaScript(script)
        }

        private func runDebugPlaylistDownloadIfNeeded(in webView: WKWebView) {
            #if DEBUG
            guard
                let rawPlaylistId = ProcessInfo.processInfo.environment["EARWORM_QA_DOWNLOAD_PLAYLIST_ID"],
                let playlistId = Int(rawPlaylistId),
                !debugDownloadPlaylistIdsStarted.contains(playlistId)
            else {
                return
            }

            debugDownloadPlaylistIdsStarted.insert(playlistId)
            Self.recordDiagnostic(
                .info,
                category: "qa",
                message: "Starting debug playlist download through MobileWorm bridge.",
                metadata: ["playlistId": String(playlistId)]
            )

            guard let baseURL = webView.url else {
                Self.recordDiagnostic(
                    .error,
                    category: "qa",
                    message: "Debug playlist download failed before WebView URL was available.",
                    metadata: ["playlistId": String(playlistId)]
                )
                return
            }

            Task {
                await runDebugNativePlaylistDownload(playlistId: playlistId, baseURL: baseURL)
            }
            #endif
        }

        private func runDebugSearchNavigationIfNeeded(in webView: WKWebView) {
            #if DEBUG
            guard
                !debugSearchQueryApplied,
                let rawQuery = ProcessInfo.processInfo.environment["EARWORM_QA_SEARCH_QUERY"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !rawQuery.isEmpty
            else {
                return
            }

            debugSearchQueryApplied = true
            let encodedQuery = rawQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawQuery
            let script = """
            (() => {
              const path = `/search?q=\(encodedQuery)`;
              window.history.pushState({}, "", path);
              window.dispatchEvent(new PopStateEvent("popstate", { state: {} }));
            })();
            """

            Self.recordDiagnostic(
                .info,
                category: "qa",
                message: "Navigating to debug offline search query.",
                metadata: ["query": rawQuery]
            )
            webView.evaluateJavaScript(script)
            #endif
        }

        #if DEBUG
        private func runDebugNativePlaylistDownload(playlistId: Int, baseURL: URL) async {
            do {
                guard
                    let token = ProcessInfo.processInfo.environment["EARWORM_SESSION_TOKEN"]?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !token.isEmpty,
                    let manifestURL = URL(
                        string: "/api/download/playlists/\(playlistId)/manifest",
                        relativeTo: baseURL
                    )?.absoluteURL,
                    let cookie = Self.debugSessionCookie(token: token, url: manifestURL)
                else {
                    throw DebugPlaylistDownloadError.missingSession
                }

                var request = URLRequest(url: manifestURL)
                request.setValue("earworm_session=\(token)", forHTTPHeaderField: "Cookie")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode)
                else {
                    throw DebugPlaylistDownloadError.invalidManifestResponse
                }

                let manifest = try JSONDecoder().decode(DebugPlaylistDownloadManifest.self, from: data)
                let tracks = manifest.tracks.compactMap { track -> WebPlaylistTrackDownloadRequest? in
                    guard
                        let sourceURL = URL(string: track.url, relativeTo: baseURL)?.absoluteURL
                    else {
                        return nil
                    }

                    return WebPlaylistTrackDownloadRequest(
                        trackId: track.trackId,
                        sourceURL: sourceURL,
                        filename: track.filename,
                        cookies: [cookie]
                    )
                }

                let downloadedPlaylist = try await WebDownloadManager.shared.downloadPlaylist(
                    named: manifest.playlistName,
                    playlistId: manifest.playlistId,
                    tracks: tracks
                )

                await MainActor.run {
                    Self.recordDiagnostic(
                        .info,
                        category: "qa",
                        message: "Debug playlist download finished.",
                        metadata: [
                            "playlistId": String(playlistId),
                            "savedCount": String(downloadedPlaylist.savedCount),
                            "skippedCount": String(downloadedPlaylist.skippedCount),
                            "path": downloadedPlaylist.url.path,
                        ]
                    )
                }
            } catch {
                await MainActor.run {
                    Self.recordDiagnostic(
                        .error,
                        category: "qa",
                        message: "Debug playlist download failed.",
                        metadata: [
                            "playlistId": String(playlistId),
                            "error": error.localizedDescription,
                        ]
                    )
                }
            }
        }

        private static func debugSessionCookie(token: String, url: URL) -> HTTPCookie? {
            guard let host = url.host else {
                return nil
            }

            return HTTPCookie(properties: [
                .domain: host,
                .path: "/api",
                .name: EarwormWebView.debugSessionCookieName,
                .value: token,
                .secure: (url.scheme?.lowercased() == "https"),
                .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 30),
            ])
        }
        #endif

        private func handleDiagnosticsMessage(_ body: [String: Any]) {
            let event = (body["event"] as? String) ?? "unknown"
            let message = (body["message"] as? String) ?? event
            var metadata: [String: String] = [:]
            for (key, value) in body where key != "event" && key != "message" {
                metadata[key] = String(describing: value)
            }

            let level: AppDiagnosticsStore.Level
            switch event {
            case "console_error", "window_error", "unhandled_rejection":
                level = .error
            case "console_warn", "audio_event":
                level = .warning
            default:
                level = .debug
            }

            Self.recordDiagnostic(level, category: "web_\(event)", message: message, metadata: metadata)
        }

        private func updateSnapshot(for webView: WKWebView) {
            EarwormWebView.diagnostics.updateWebViewState(
                url: webView.url?.absoluteString ?? loadingURL,
                title: webView.title,
                isLoading: webView.isLoading,
                estimatedProgress: webView.estimatedProgress
            )
        }

        private static func normalizedLoadTarget(for rawURL: String?) -> String? {
            guard let rawURL else {
                return nil
            }

            guard let url = URL(string: rawURL) else {
                return rawURL
            }

            return normalizedLoadTarget(for: url)
        }

        private static func normalizedLoadTarget(for url: URL?) -> String? {
            guard let url else {
                return nil
            }

            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }

            if components.path.isEmpty {
                components.path = "/"
            }
            components.fragment = nil
            return components.string ?? url.absoluteString
        }

        private static func recordDiagnostic(
            _ level: AppDiagnosticsStore.Level,
            category: String,
            message: String,
            metadata: [String: String] = [:]
        ) {
            EarwormWebView.diagnostics.record(level, category: category, message: message, metadata: metadata)
        }

        @MainActor
        private func sendMetadataCacheResponse(
            requestId: String,
            ok: Bool,
            body: String?,
            errorMessage: String?
        ) {
            let payload: [String: Any] = [
                "id": requestId,
                "ok": ok,
                "body": body ?? NSNull(),
                "error": errorMessage ?? NSNull(),
            ]

            guard
                let webView,
                let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                let payloadString = String(data: payloadData, encoding: .utf8)
            else {
                return
            }

            webView.evaluateJavaScript("window.__mobilewormMetadataCacheBridgeResolve?.(\(payloadString))")
        }

        @MainActor
        private func sendDownloadResponse(
            requestId: String,
            ok: Bool,
            filename: String?,
            path: String?,
            localUrl: String?,
            savedCount: Int?,
            skippedCount: Int?,
            errorMessage: String?
        ) {
            let payload: [String: Any] = [
                "id": requestId,
                "ok": ok,
                "filename": filename ?? NSNull(),
                "path": path ?? NSNull(),
                "localUrl": localUrl ?? NSNull(),
                "savedCount": savedCount ?? NSNull(),
                "skippedCount": skippedCount ?? NSNull(),
                "error": errorMessage ?? NSNull(),
            ]

            guard
                let webView,
                let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                let payloadString = String(data: payloadData, encoding: .utf8)
            else {
                return
            }

            webView.evaluateJavaScript("window.__mobilewormDownloadBridgeResolve?.(\(payloadString))")
        }

        @MainActor
        private func sendDownloadStatusResponse(
            requestId: String,
            ok: Bool,
            downloadedTrackIds: [Int],
            downloadedPlaylistIds: [Int],
            localUrl: String?,
            errorMessage: String?
        ) {
            let payload: [String: Any] = [
                "id": requestId,
                "ok": ok,
                "downloadedTrackIds": downloadedTrackIds,
                "downloadedPlaylistIds": downloadedPlaylistIds,
                "url": localUrl ?? NSNull(),
                "error": errorMessage ?? NSNull(),
            ]

            guard
                let webView,
                let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                let payloadString = String(data: payloadData, encoding: .utf8)
            else {
                return
            }

            webView.evaluateJavaScript("window.__mobilewormDownloadBridgeResolve?.(\(payloadString))")
        }
    }
}

#if DEBUG
private struct DebugPlaylistDownloadManifest: Decodable {
    let playlistId: Int
    let playlistName: String
    let tracks: [DebugPlaylistDownloadTrack]
}

private struct DebugPlaylistDownloadTrack: Decodable {
    let trackId: Int
    let filename: String
    let url: String
}

private enum DebugPlaylistDownloadError: LocalizedError {
    case missingSession
    case invalidManifestResponse

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "The debug playlist downloader could not find a session token or manifest URL."
        case .invalidManifestResponse:
            return "The playlist manifest request did not return a successful HTTP response."
        }
    }
}
#endif
