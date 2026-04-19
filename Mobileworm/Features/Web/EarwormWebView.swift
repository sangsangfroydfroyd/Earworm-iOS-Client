import SwiftUI
import UIKit
import WebKit

struct EarwormWebView: UIViewRepresentable {
    let url: URL
    let onAuthenticationStateChanged: (Bool) -> Void
    let onLoadFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onAuthenticationStateChanged: onAuthenticationStateChanged,
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
        configuration.userContentController.addUserScript(Self.viewportLockScript)
        configuration.userContentController.addUserScript(Self.bridgeScript)
        configuration.userContentController.addUserScript(Self.metadataCacheBridgeScript)
        configuration.userContentController.addUserScript(Self.downloadBridgeScript)
        configuration.userContentController.addUserScript(Self.nowPlayingBridgeScript)
        configuration.userContentController.add(context.coordinator, name: Coordinator.authStateHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.metadataCacheHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.downloadHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.nowPlayingHandler)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        WebNowPlayingManager.shared.attach(webView: webView)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        Self.disableNativeInsets(for: webView)
        webView.scrollView.delegate = context.coordinator
        Self.lockZoom(for: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        Self.disableNativeInsets(for: webView)
        Self.lockZoom(for: webView)
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.authStateHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.metadataCacheHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.downloadHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.nowPlayingHandler)
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
          window.__mobilewormNowPlaying = {
            update(payload) {
              nowPlayingHandler.postMessage({
                action: "update",
                ...payload
              });
            },
            clear() {
              nowPlayingHandler.postMessage({ action: "clear" });
            }
          };

          window.__mobilewormNowPlayingCommand = (command) => {
            window.dispatchEvent(new CustomEvent("mobileworm:remote-command", {
              detail: { command }
            }));
          };
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        static let authStateHandler = "mobilewormAuthState"
        static let metadataCacheHandler = "mobilewormMetadataCache"
        static let downloadHandler = "mobilewormDownloads"
        static let nowPlayingHandler = "mobilewormNowPlaying"

        private let onAuthenticationStateChanged: (Bool) -> Void
        private let onLoadFailure: (String) -> Void
        weak var webView: WKWebView?

        init(
            onAuthenticationStateChanged: @escaping (Bool) -> Void,
            onLoadFailure: @escaping (String) -> Void
        ) {
            self.onAuthenticationStateChanged = onAuthenticationStateChanged
            self.onLoadFailure = onLoadFailure
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(error)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.__mobilewormBridgeSync?.()")
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
                    Task {
                        await WebNowPlayingManager.shared.clear()
                    }
                    return
                }

                guard action == "update", let payload = WebNowPlayingPayload(messageBody: body) else {
                    return
                }

                Task {
                    let cookies = await cookies(for: payload.artworkURL)
                    await WebNowPlayingManager.shared.update(payload: payload, cookies: cookies)
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

            onLoadFailure(error.localizedDescription)
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
