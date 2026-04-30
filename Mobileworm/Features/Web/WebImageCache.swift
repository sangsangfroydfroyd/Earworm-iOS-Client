import CryptoKit
import Foundation
import UIKit
import WebKit

actor WebImageCache {
    static let shared = WebImageCache()

    private let cacheDirectory: URL
    private let imageDirectory: URL
    private let manifestURL: URL
    private let maxImageDimension: CGFloat = 700
    private let jpegQuality: CGFloat = 0.82
    private let staleCheckInterval: TimeInterval = 60 * 60 * 24

    private var manifest: ImageCacheManifest?
    private var refreshesInFlight: Set<String> = []
    private var syncRootsInFlight: Set<String> = []

    init(fileManager: FileManager = .default) {
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectory = cachesRoot.appendingPathComponent("EarwormImageCache", isDirectory: true)
        imageDirectory = cacheDirectory.appendingPathComponent("Images", isDirectory: true)
        manifestURL = cacheDirectory.appendingPathComponent("manifest.json")
    }

    func cachedImage(for targetURL: URL) async -> CachedImage? {
        await loadManifestIfNeeded()
        let key = cacheKey(for: targetURL.absoluteString)
        guard var entry = manifest?.entries[key] else {
            return nil
        }

        let fileURL = imageDirectory.appendingPathComponent(entry.fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            manifest?.entries.removeValue(forKey: key)
            await saveManifest()
            return nil
        }

        entry.lastSeenAt = .now
        manifest?.entries[key] = entry
        await saveManifest()
        return CachedImage(data: data, contentType: entry.contentType)
    }

    func fetchAndStoreImage(for targetURL: URL, cookies: [HTTPCookie]) async throws -> CachedImage {
        await loadManifestIfNeeded()
        let cachedEntry = manifest?.entries[cacheKey(for: targetURL.absoluteString)]
        let result = try await fetchImage(for: targetURL, cookies: cookies, cachedEntry: cachedEntry)
        return try await store(result, for: targetURL)
    }

    func refreshIfNeeded(targetURL: URL, cookies: [HTTPCookie]) async {
        await loadManifestIfNeeded()
        let key = cacheKey(for: targetURL.absoluteString)
        guard
            let entry = manifest?.entries[key],
            Date().timeIntervalSince(entry.lastCheckedAt) >= staleCheckInterval,
            !refreshesInFlight.contains(key)
        else {
            return
        }

        refreshesInFlight.insert(key)
        defer { refreshesInFlight.remove(key) }

        do {
            let result = try await fetchImage(for: targetURL, cookies: cookies, cachedEntry: entry)
            _ = try await store(result, for: targetURL)
        } catch ImageCacheError.notModified {
            var updatedEntry = entry
            updatedEntry.lastCheckedAt = .now
            updatedEntry.lastSeenAt = .now
            manifest?.entries[key] = updatedEntry
            await saveManifest()
        } catch {
            return
        }
    }

    func syncLibraryArtwork(from launchURL: URL, cookies: [HTTPCookie]) async {
        guard let rootURL = rootURL(for: launchURL) else {
            return
        }

        let rootKey = rootURL.absoluteString
        guard !syncRootsInFlight.contains(rootKey) else {
            return
        }

        syncRootsInFlight.insert(rootKey)
        defer { syncRootsInFlight.remove(rootKey) }

        do {
            await reportProgress(
                .start,
                detail: "Checking library artwork...",
                completed: 0,
                total: nil
            )
            await loadManifestIfNeeded()
            let artworkURLs = try await libraryArtworkURLs(from: rootURL, cookies: cookies)
            await reportProgress(
                .update,
                detail: artworkURLs.isEmpty ? "No artwork found" : "Checking \(artworkURLs.count) images...",
                completed: 0,
                total: max(artworkURLs.count, 1)
            )
            let signature = cacheKey(for: artworkURLs.map { $0.absoluteString }.sorted().joined(separator: "\n"))
            var completedCount = 0
            if manifest?.librarySignatures[rootKey] != signature {
                await pruneImages(keeping: Set(artworkURLs.map { cacheKey(for: $0.absoluteString) }))
                for artworkURL in artworkURLs {
                    if await cachedImage(for: artworkURL) != nil {
                        completedCount += 1
                        await reportProgress(
                            .update,
                            detail: "Checked cached image \(completedCount) of \(artworkURLs.count)",
                            completed: completedCount,
                            total: max(artworkURLs.count, 1)
                        )
                        continue
                    }

                    await reportProgress(
                        .update,
                        detail: "Downloading image \(completedCount + 1) of \(artworkURLs.count)",
                        completed: completedCount,
                        total: max(artworkURLs.count, 1)
                    )
                    _ = try? await fetchAndStoreImage(for: artworkURL, cookies: cookies)
                    completedCount += 1
                    await reportProgress(
                        .update,
                        detail: "Saved image \(completedCount) of \(artworkURLs.count)",
                        completed: completedCount,
                        total: max(artworkURLs.count, 1)
                    )
                }
                manifest?.librarySignatures[rootKey] = signature
            }
            for artworkURL in artworkURLs {
                await refreshIfNeeded(targetURL: artworkURL, cookies: cookies)
            }
            manifest?.lastLibrarySyncAt = .now
            await saveManifest()
            await reportProgress(
                .finish,
                detail: artworkURLs.isEmpty
                    ? "Artwork cache checked"
                    : "Artwork cache updated",
                completed: max(artworkURLs.count, 1),
                total: max(artworkURLs.count, 1)
            )
        } catch {
            await reportProgress(
                .finish,
                detail: "Artwork cache check failed",
                completed: 1,
                total: 1,
                failed: true
            )
            return
        }
    }

    private func libraryArtworkURLs(from rootURL: URL, cookies: [HTTPCookie]) async throws -> [URL] {
        async let albums = fetchLibraryEntities(
            from: rootURL.appendingPathComponent("api").appendingPathComponent("albums"),
            cookies: cookies
        )
        async let artists = fetchLibraryEntities(
            from: rootURL.appendingPathComponent("api").appendingPathComponent("artists"),
            cookies: cookies
        )

        var urls: [URL] = []
        for album in try await albums where album.hasCoverArt != false {
            urls.append(
                rootURL
                    .appendingPathComponent("api")
                    .appendingPathComponent("artwork")
                    .appendingPathComponent("album")
                    .appendingPathComponent(String(album.id))
            )
        }
        for artist in try await artists {
            urls.append(
                rootURL
                    .appendingPathComponent("api")
                    .appendingPathComponent("artwork")
                    .appendingPathComponent("artist")
                    .appendingPathComponent(String(artist.id))
            )
        }
        return urls
    }

    private func fetchLibraryEntities(from url: URL, cookies: [HTTPCookie]) async throws -> [LibraryArtworkEntity] {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        addCookies(cookies, to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw ImageCacheError.invalidResponse
        }

        return try JSONDecoder().decode([LibraryArtworkEntity].self, from: data)
    }

    private func fetchImage(
        for targetURL: URL,
        cookies: [HTTPCookie],
        cachedEntry: ImageCacheEntry?
    ) async throws -> FetchedImage {
        var request = URLRequest(url: targetURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = cachedEntry?.etag {
            request.addValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cachedEntry?.lastModified {
            request.addValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        addCookies(cookies, to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageCacheError.invalidResponse
        }
        if httpResponse.statusCode == 304 {
            throw ImageCacheError.notModified
        }
        guard (200...299).contains(httpResponse.statusCode), !data.isEmpty else {
            throw ImageCacheError.invalidResponse
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "image/jpeg"
        let optimized = Self.optimizedImageData(from: data, fallbackContentType: contentType, maxDimension: maxImageDimension, jpegQuality: jpegQuality)
        return FetchedImage(
            data: optimized.data,
            contentType: optimized.contentType,
            originalByteCount: data.count,
            etag: httpResponse.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    private func store(_ fetchedImage: FetchedImage, for targetURL: URL) async throws -> CachedImage {
        try ensureCacheDirectory()
        let key = cacheKey(for: targetURL.absoluteString)
        let fileName = "\(key).\(Self.fileExtension(for: fetchedImage.contentType))"
        let fileURL = imageDirectory.appendingPathComponent(fileName)
        try fetchedImage.data.write(to: fileURL, options: .atomic)

        let entry = ImageCacheEntry(
            targetURL: targetURL.absoluteString,
            fileName: fileName,
            contentType: fetchedImage.contentType,
            originalByteCount: fetchedImage.originalByteCount,
            optimizedByteCount: fetchedImage.data.count,
            contentHash: cacheKey(for: fetchedImage.data),
            etag: fetchedImage.etag,
            lastModified: fetchedImage.lastModified,
            lastSeenAt: .now,
            lastCheckedAt: .now
        )
        manifest?.entries[key] = entry
        await saveManifest()
        return CachedImage(data: fetchedImage.data, contentType: fetchedImage.contentType)
    }

    private func pruneImages(keeping retainedKeys: Set<String>) async {
        await loadManifestIfNeeded()
        let removedEntries = (manifest?.entries ?? [:]).filter { !retainedKeys.contains($0.key) }
        for (key, entry) in removedEntries {
            let fileURL = imageDirectory.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: fileURL)
            manifest?.entries.removeValue(forKey: key)
        }
    }

    private func loadManifestIfNeeded() async {
        guard manifest == nil else {
            return
        }

        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(ImageCacheManifest.self, from: data)
        else {
            manifest = ImageCacheManifest(entries: [:], librarySignatures: [:], lastLibrarySyncAt: nil)
            return
        }

        manifest = decoded
    }

    private func saveManifest() async {
        do {
            try ensureCacheDirectory()
            let data = try JSONEncoder().encode(manifest ?? ImageCacheManifest(entries: [:], librarySignatures: [:], lastLibrarySyncAt: nil))
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            return
        }
    }

    private func ensureCacheDirectory() throws {
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
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

    private func addCookies(_ cookies: [HTTPCookie], to request: inout URLRequest) {
        guard !cookies.isEmpty else {
            return
        }

        let header = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
        if let header {
            request.addValue(header, forHTTPHeaderField: "Cookie")
        }
    }

    private func cacheKey(for key: String) -> String {
        cacheKey(for: Data(key.utf8))
    }

    private func cacheKey(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private enum ProgressEvent {
        case start
        case update
        case finish
    }

    private func reportProgress(
        _ event: ProgressEvent,
        detail: String,
        completed: Int,
        total: Int?,
        failed: Bool = false
    ) async {
        await MainActor.run {
            switch event {
            case .start:
                TransferProgressStore.shared.start(
                    .images,
                    title: "Artwork cache",
                    detail: detail,
                    completed: completed,
                    total: total
                )
            case .update:
                TransferProgressStore.shared.update(
                    .images,
                    title: "Artwork cache",
                    detail: detail,
                    completed: completed,
                    total: total
                )
            case .finish:
                TransferProgressStore.shared.finish(.images, detail: detail, failed: failed)
            }
        }
    }

    private static func optimizedImageData(
        from data: Data,
        fallbackContentType: String,
        maxDimension: CGFloat,
        jpegQuality: CGFloat
    ) -> (data: Data, contentType: String) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return (data, fallbackContentType)
        }

        let longestSide = max(image.size.width, image.size.height)
        let scaleRatio = min(1, maxDimension / longestSide)
        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scaleRatio)),
            height: max(1, floor(image.size.height * scaleRatio))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resizedImage.jpegData(compressionQuality: jpegQuality) else {
            return (data, fallbackContentType)
        }

        if jpegData.count >= data.count {
            return (data, fallbackContentType)
        }

        return (jpegData, "image/jpeg")
    }

    private static func fileExtension(for contentType: String) -> String {
        if contentType.lowercased().contains("png") {
            return "png"
        }
        if contentType.lowercased().contains("webp") {
            return "webp"
        }
        return "jpg"
    }
}

struct CachedImage {
    let data: Data
    let contentType: String
}

private actor OnDemandArtworkProgressTracker {
    static let shared = OnDemandArtworkProgressTracker()

    private var activeDownloads = 0
    private var completedDownloads = 0
    private var totalDownloads = 0
    private var hasFailure = false
    private var resetTask: Task<Void, Never>?

    func start() async {
        resetTask?.cancel()
        if activeDownloads == 0 {
            completedDownloads = 0
            totalDownloads = 0
            hasFailure = false
        }

        activeDownloads += 1
        totalDownloads += 1
        await report(
            totalDownloads == 1 ? .start : .update,
            detail: "Downloading artwork...",
            completed: completedDownloads,
            total: totalDownloads,
            failed: false
        )
    }

    func finish(failed: Bool) async {
        activeDownloads = max(0, activeDownloads - 1)
        completedDownloads = min(totalDownloads, completedDownloads + 1)
        hasFailure = hasFailure || failed

        if activeDownloads == 0 {
            let detail: String
            if hasFailure {
                detail = totalDownloads == 1 ? "Artwork download failed" : "Some artwork failed"
            } else {
                detail = totalDownloads == 1 ? "Artwork saved" : "Saved \(completedDownloads) images"
            }
            await report(.finish, detail: detail, completed: completedDownloads, total: max(totalDownloads, 1), failed: hasFailure)
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(2.5))
                self.resetIfIdle()
            }
        } else {
            await report(
                .update,
                detail: "Downloading artwork...",
                completed: completedDownloads,
                total: totalDownloads,
                failed: false
            )
        }
    }

    private func resetIfIdle() {
        guard activeDownloads == 0 else {
            return
        }
        completedDownloads = 0
        totalDownloads = 0
        hasFailure = false
        resetTask = nil
    }

    private enum ProgressEvent {
        case start
        case update
        case finish
    }

    private func report(
        _ event: ProgressEvent,
        detail: String,
        completed: Int,
        total: Int,
        failed: Bool
    ) async {
        await MainActor.run {
            switch event {
            case .start:
                TransferProgressStore.shared.start(
                    .images,
                    title: "Artwork cache",
                    detail: detail,
                    completed: completed,
                    total: total
                )
            case .update:
                TransferProgressStore.shared.update(
                    .images,
                    title: "Artwork cache",
                    detail: detail,
                    completed: completed,
                    total: total
                )
            case .finish:
                TransferProgressStore.shared.finish(.images, detail: detail, failed: failed)
            }
        }
    }
}

final class MobilewormImageCacheSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let requestURL = urlSchemeTask.request.url,
            requestURL.scheme == "mobileworm-image-cache",
            let targetURL = Self.targetURL(from: requestURL)
        else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        Task {
            let cookies = await Self.cookies(for: targetURL, in: webView)
            if let cachedImage = await WebImageCache.shared.cachedImage(for: targetURL) {
                Self.finish(urlSchemeTask, requestURL: requestURL, image: cachedImage)
                Task {
                    await WebImageCache.shared.refreshIfNeeded(targetURL: targetURL, cookies: cookies)
                }
                return
            }

            do {
                await OnDemandArtworkProgressTracker.shared.start()
                let image = try await WebImageCache.shared.fetchAndStoreImage(for: targetURL, cookies: cookies)
                Self.finish(urlSchemeTask, requestURL: requestURL, image: image)
                await OnDemandArtworkProgressTracker.shared.finish(failed: false)
            } catch {
                await OnDemandArtworkProgressTracker.shared.finish(failed: true)
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func targetURL(from requestURL: URL) -> URL? {
        guard
            let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
            let encodedURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
            let targetURL = URL(string: encodedURL),
            let scheme = targetURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        return targetURL
    }

    private static func finish(_ urlSchemeTask: WKURLSchemeTask, requestURL: URL, image: CachedImage) {
        let response = URLResponse(
            url: requestURL,
            mimeType: image.contentType,
            expectedContentLength: image.data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(image.data)
        urlSchemeTask.didFinish()
    }

    private static func cookies(for url: URL, in webView: WKWebView) async -> [HTTPCookie] {
        let cookieStore = await MainActor.run {
            webView.configuration.websiteDataStore.httpCookieStore
        }
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return cookies.filter { cookieMatches($0, url: url) }
    }

    private static func cookieMatches(_ cookie: HTTPCookie, url: URL) -> Bool {
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
}

private struct ImageCacheManifest: Codable {
    var entries: [String: ImageCacheEntry]
    var librarySignatures: [String: String]
    var lastLibrarySyncAt: Date?
}

private struct ImageCacheEntry: Codable {
    let targetURL: String
    let fileName: String
    let contentType: String
    let originalByteCount: Int
    let optimizedByteCount: Int
    let contentHash: String
    let etag: String?
    let lastModified: String?
    var lastSeenAt: Date
    var lastCheckedAt: Date
}

private struct FetchedImage {
    let data: Data
    let contentType: String
    let originalByteCount: Int
    let etag: String?
    let lastModified: String?
}

private struct LibraryArtworkEntity: Decodable {
    let id: Int
    let hasCoverArt: Bool?
}

private enum ImageCacheError: Error {
    case invalidResponse
    case notModified
}
