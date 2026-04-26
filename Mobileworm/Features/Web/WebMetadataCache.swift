import CryptoKit
import Foundation

actor WebMetadataCache {
    static let shared = WebMetadataCache()

    private let cacheDirectory: URL
    private let maxEntryBytes = 10_000_000

    init(fileManager: FileManager = .default) {
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectory = cachesRoot.appendingPathComponent("EarwormMetadataCache", isDirectory: true)
    }

    func cachedBody(for key: String) async -> String? {
        let fileURL = entryFileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(CacheEntry.self, from: data).body
    }

    func store(body: String, for key: String) async {
        guard body.utf8.count <= maxEntryBytes else {
            return
        }

        do {
            try ensureCacheDirectory()
            let entry = CacheEntry(body: body, updatedAt: .now)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: entryFileURL(for: key), options: .atomic)
        } catch {
            return
        }
    }

    private func ensureCacheDirectory() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func entryFileURL(for key: String) -> URL {
        cacheDirectory
            .appendingPathComponent(cacheKey(for: key))
            .appendingPathExtension("json")
    }

    private func cacheKey(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct CacheEntry: Codable {
        let body: String
        let updatedAt: Date
    }
}

actor WebAppShellCache {
    static let shared = WebAppShellCache()

    private let cacheDirectory: URL
    private let maxHTMLBytes = 2_000_000
    private let maxAssetBytes = 12_000_000

    init(fileManager: FileManager = .default) {
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectory = cachesRoot.appendingPathComponent("EarwormAppShellCache", isDirectory: true)
    }

    func refresh(from url: URL) async {
        guard let rootURL = rootURL(for: url) else {
            return
        }

        do {
            let html = try await fetchText(from: rootURL, maxBytes: maxHTMLBytes)
            let inlinedHTML = try await inlineStaticAssets(in: html, rootURL: rootURL)
            try ensureCacheDirectory()
            let entry = ShellEntry(html: inlinedHTML, updatedAt: .now)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: entryFileURL(for: rootURL), options: .atomic)
        } catch {
            return
        }
    }

    func cachedHTML(for url: URL) async -> String? {
        guard let rootURL = rootURL(for: url) else {
            return nil
        }

        let fileURL = entryFileURL(for: rootURL)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(ShellEntry.self, from: data).html
    }

    private func inlineStaticAssets(in html: String, rootURL: URL) async throws -> String {
        var result = html
        let scriptReferences = assetReferences(
            in: html,
            pattern: #"<script\b([^>]*)\bsrc=["']([^"']+)["']([^>]*)></script>"#
        )
        for reference in scriptReferences.reversed() {
            guard let assetURL = sameOriginURL(for: reference.url, rootURL: rootURL) else {
                continue
            }

            let script = try await fetchText(from: assetURL, maxBytes: maxAssetBytes)
                .replacingOccurrences(of: "</script", with: "<\\/script")
            let replacement = "<script\(reference.leadingAttributes)\(reference.trailingAttributes)>\n\(script)\n</script>"
            result.replaceSubrange(reference.range, with: replacement)
        }

        let styleReferences = assetReferences(
            in: result,
            pattern: #"<link\b([^>]*)\bhref=["']([^"']+\.css[^"']*)["']([^>]*)>"#
        )
        for reference in styleReferences.reversed() {
            guard let assetURL = sameOriginURL(for: reference.url, rootURL: rootURL) else {
                continue
            }

            let style = try await fetchText(from: assetURL, maxBytes: maxAssetBytes)
            result.replaceSubrange(reference.range, with: "<style>\n\(style)\n</style>")
        }

        return result
    }

    private func assetReferences(in html: String, pattern: String) -> [AssetReference] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: fullRange).compactMap { match in
            guard
                match.numberOfRanges >= 4,
                let range = Range(match.range(at: 0), in: html),
                let leadingRange = Range(match.range(at: 1), in: html),
                let urlRange = Range(match.range(at: 2), in: html),
                let trailingRange = Range(match.range(at: 3), in: html)
            else {
                return nil
            }

            return AssetReference(
                range: range,
                leadingAttributes: String(html[leadingRange]),
                url: String(html[urlRange]),
                trailingAttributes: String(html[trailingRange])
            )
        }
    }

    private func fetchText(from url: URL, maxBytes: Int) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            data.count <= maxBytes,
            let text = String(data: data, encoding: .utf8)
        else {
            throw ShellCacheError.invalidResponse
        }

        return text
    }

    private func sameOriginURL(for rawURL: String, rootURL: URL) -> URL? {
        guard let url = URL(string: rawURL, relativeTo: rootURL)?.absoluteURL else {
            return nil
        }

        guard
            url.scheme?.lowercased() == rootURL.scheme?.lowercased(),
            url.host?.lowercased() == rootURL.host?.lowercased(),
            url.port == rootURL.port
        else {
            return nil
        }

        return url
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

    private func ensureCacheDirectory() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func entryFileURL(for rootURL: URL) -> URL {
        cacheDirectory
            .appendingPathComponent(cacheKey(for: rootURL.absoluteString))
            .appendingPathExtension("json")
    }

    private func cacheKey(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct AssetReference {
        let range: Range<String.Index>
        let leadingAttributes: String
        let url: String
        let trailingAttributes: String
    }

    private struct ShellEntry: Codable {
        let html: String
        let updatedAt: Date
    }

    private enum ShellCacheError: Error {
        case invalidResponse
    }
}
