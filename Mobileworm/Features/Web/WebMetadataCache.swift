import CryptoKit
import Foundation

actor WebMetadataCache {
    static let shared = WebMetadataCache()

    private let cacheDirectory: URL
    private let maxEntryBytes = 1_000_000

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
