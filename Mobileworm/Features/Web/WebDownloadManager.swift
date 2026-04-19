import Foundation
import UniformTypeIdentifiers
import WebKit

struct DownloadedTrackFile {
    let trackId: Int?
    let filename: String
    let url: URL
    let localPlaybackURL: String?
}

struct WebPlaylistTrackDownloadRequest {
    let trackId: Int
    let sourceURL: URL
    let filename: String
    let cookies: [HTTPCookie]
}

struct DownloadedPlaylistFolder {
    let playlistId: Int?
    let folderName: String
    let url: URL
    let savedCount: Int
    let skippedCount: Int
}

actor WebDownloadManager {
    static let shared = WebDownloadManager()

    private let folderName = "EarWorm Downloads"
    private let downloadedTracksDefaultsKey = "mobileworm.downloadedTracks.v1"
    private let downloadedPlaylistsDefaultsKey = "mobileworm.downloadedPlaylists.v1"

    func downloadTrack(from sourceURL: URL, filename: String, cookies: [HTTPCookie], trackId: Int?) async throws -> DownloadedTrackFile {
        let downloadsDirectory = try ensureDownloadsDirectory()
        return try await downloadTrack(
            from: sourceURL,
            filename: filename,
            cookies: cookies,
            trackId: trackId,
            destinationDirectory: downloadsDirectory
        )
    }

    func downloadPlaylist(
        named playlistName: String,
        playlistId: Int?,
        tracks: [WebPlaylistTrackDownloadRequest]
    ) async throws -> DownloadedPlaylistFolder {
        let downloadsDirectory = try ensureDownloadsDirectory()
        let folderURL = uniqueDirectoryURL(
            in: downloadsDirectory,
            folderName: sanitizedFolderName(playlistName)
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var savedCount = 0
        var skippedCount = 0
        for track in tracks {
            do {
                _ = try await downloadTrack(
                    from: track.sourceURL,
                    filename: track.filename,
                    cookies: track.cookies,
                    trackId: track.trackId,
                    destinationDirectory: folderURL
                )
                savedCount += 1
            } catch {
                skippedCount += 1
            }
        }

        guard savedCount > 0 || tracks.isEmpty else {
            throw WebDownloadManagerError.noPlaylistTracksSaved
        }
        if let playlistId {
            storeDownloadedPlaylist(playlistId: playlistId, folderURL: folderURL)
        }

        return DownloadedPlaylistFolder(
            playlistId: playlistId,
            folderName: folderURL.lastPathComponent,
            url: folderURL,
            savedCount: savedCount,
            skippedCount: skippedCount
        )
    }

    private func downloadTrack(
        from sourceURL: URL,
        filename: String,
        cookies: [HTTPCookie],
        trackId: Int?,
        destinationDirectory: URL
    ) async throws -> DownloadedTrackFile {
        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        if let cookieHeader = cookieHeaders["Cookie"] {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDownloadManagerError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WebDownloadManagerError.httpStatus(httpResponse.statusCode)
        }

        let destinationURL = uniqueDestinationURL(
            in: destinationDirectory,
            filename: sanitizedFilename(filename)
        )
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        if let trackId {
            storeDownloadedTrack(trackId: trackId, fileURL: destinationURL)
        }

        return DownloadedTrackFile(
            trackId: trackId,
            filename: destinationURL.lastPathComponent,
            url: destinationURL,
            localPlaybackURL: trackId.map { localPlaybackURL(trackId: $0, filename: destinationURL.lastPathComponent) }
        )
    }

    func downloadedTrackIds(from trackIds: [Int]) -> [Int] {
        let requested = Set(trackIds)
        return loadDownloadedTracks()
            .filter { requested.contains($0.trackId) && FileManager.default.fileExists(atPath: $0.path) }
            .map(\.trackId)
    }

    func downloadedPlaylistIds(from playlistIds: [Int]) -> [Int] {
        let requested = Set(playlistIds)
        return loadDownloadedPlaylists()
            .filter { requested.contains($0.playlistId) && FileManager.default.fileExists(atPath: $0.path) }
            .map(\.playlistId)
    }

    func downloadedTrackURL(trackId: Int) -> URL? {
        guard
            let record = loadDownloadedTracks().first(where: { $0.trackId == trackId }),
            FileManager.default.fileExists(atPath: record.path)
        else {
            return nil
        }

        return URL(fileURLWithPath: record.path)
    }

    func localPlaybackURLString(trackId: Int) -> String? {
        guard let fileURL = downloadedTrackURL(trackId: trackId) else {
            return nil
        }

        return localPlaybackURL(trackId: trackId, filename: fileURL.lastPathComponent)
    }

    private func ensureDownloadsDirectory() throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Documents", isDirectory: true)
        let downloadsDirectory = documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        return downloadsDirectory
    }

    private func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let cleanedFilename = filename.isEmpty ? "Track.audio" : filename
        let base = (cleanedFilename as NSString).deletingPathExtension
        let ext = (cleanedFilename as NSString).pathExtension

        var candidate = directory.appendingPathComponent(cleanedFilename, isDirectory: false)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numberedName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(numberedName, isDirectory: false)
            index += 1
        }
        return candidate
    }

    private func uniqueDirectoryURL(in directory: URL, folderName: String) -> URL {
        let cleanedFolderName = folderName.isEmpty ? "Playlist" : folderName

        var candidate = directory.appendingPathComponent(cleanedFolderName, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(cleanedFolderName) \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:\u{0}")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = filename
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let cleaned = parts.joined(separator: " ")
        return String(cleaned.prefix(180))
    }

    private func sanitizedFolderName(_ folderName: String) -> String {
        let cleaned = sanitizedFilename(folderName)
        return cleaned.isEmpty ? "Playlist" : cleaned
    }

    private func storeDownloadedTrack(trackId: Int, fileURL: URL) {
        var records = loadDownloadedTracks().filter { $0.trackId != trackId }
        records.append(DownloadedTrackRecord(
            trackId: trackId,
            path: fileURL.path,
            filename: fileURL.lastPathComponent,
            downloadedAt: Date()
        ))
        saveDownloadedTracks(records)
    }

    private func loadDownloadedTracks() -> [DownloadedTrackRecord] {
        guard let data = UserDefaults.standard.data(forKey: downloadedTracksDefaultsKey) else {
            return []
        }

        return (try? JSONDecoder().decode([DownloadedTrackRecord].self, from: data)) ?? []
    }

    private func saveDownloadedTracks(_ records: [DownloadedTrackRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        UserDefaults.standard.set(data, forKey: downloadedTracksDefaultsKey)
    }

    private func storeDownloadedPlaylist(playlistId: Int, folderURL: URL) {
        var records = loadDownloadedPlaylists().filter { $0.playlistId != playlistId }
        records.append(DownloadedPlaylistRecord(
            playlistId: playlistId,
            path: folderURL.path,
            folderName: folderURL.lastPathComponent,
            downloadedAt: Date()
        ))
        saveDownloadedPlaylists(records)
    }

    private func loadDownloadedPlaylists() -> [DownloadedPlaylistRecord] {
        guard let data = UserDefaults.standard.data(forKey: downloadedPlaylistsDefaultsKey) else {
            return []
        }

        return (try? JSONDecoder().decode([DownloadedPlaylistRecord].self, from: data)) ?? []
    }

    private func saveDownloadedPlaylists(_ records: [DownloadedPlaylistRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        UserDefaults.standard.set(data, forKey: downloadedPlaylistsDefaultsKey)
    }

    private func localPlaybackURL(trackId: Int, filename: String) -> String {
        let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "track"
        return "mobileworm-download://track/\(trackId)/\(encodedFilename)"
    }
}

private struct DownloadedTrackRecord: Codable {
    let trackId: Int
    let path: String
    let filename: String
    let downloadedAt: Date
}

private struct DownloadedPlaylistRecord: Codable {
    let playlistId: Int
    let path: String
    let folderName: String
    let downloadedAt: Date
}

final class MobilewormDownloadSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let url = urlSchemeTask.request.url,
            url.scheme == "mobileworm-download",
            url.host == "track",
            let trackIdComponent = url.pathComponents.dropFirst().first,
            let trackId = Int(trackIdComponent)
        else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        Task {
            guard let fileURL = await WebDownloadManager.shared.downloadedTrackURL(trackId: trackId) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }

            do {
                let metadata = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = (metadata[.size] as? NSNumber)?.uint64Value ?? 0
                let byteRange = Self.byteRange(
                    from: urlSchemeTask.request.value(forHTTPHeaderField: "Range"),
                    fileSize: fileSize
                )
                let data = try Self.readData(from: fileURL, range: byteRange)
                let response = Self.response(
                    url: url,
                    fileURL: fileURL,
                    fileSize: fileSize,
                    range: byteRange,
                    dataLength: data.count
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(for fileURL: URL) -> String {
        guard
            let type = UTType(filenameExtension: fileURL.pathExtension),
            let mimeType = type.preferredMIMEType
        else {
            return "application/octet-stream"
        }

        return mimeType
    }

    private static func byteRange(from rangeHeader: String?, fileSize: UInt64) -> ClosedRange<UInt64>? {
        guard
            let rangeHeader,
            rangeHeader.hasPrefix("bytes="),
            fileSize > 0
        else {
            return nil
        }

        let spec = rangeHeader.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        if parts[0].isEmpty, let suffixLength = UInt64(parts[1]) {
            let start = suffixLength >= fileSize ? 0 : fileSize - suffixLength
            return start...(fileSize - 1)
        }

        guard let start = UInt64(parts[0]), start < fileSize else {
            return nil
        }

        let end = parts[1].isEmpty ? fileSize - 1 : min(UInt64(parts[1]) ?? fileSize - 1, fileSize - 1)
        guard end >= start else {
            return nil
        }

        return start...end
    }

    private static func readData(from fileURL: URL, range: ClosedRange<UInt64>?) throws -> Data {
        guard let range else {
            return try Data(contentsOf: fileURL)
        }

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        try fileHandle.seek(toOffset: range.lowerBound)
        let length = Int(range.upperBound - range.lowerBound + 1)
        let data = fileHandle.readData(ofLength: length)
        try fileHandle.close()
        return data
    }

    private static func response(
        url: URL,
        fileURL: URL,
        fileSize: UInt64,
        range: ClosedRange<UInt64>?,
        dataLength: Int
    ) -> URLResponse {
        var headers: [String: String] = [
            "Accept-Ranges": "bytes",
            "Content-Type": mimeType(for: fileURL),
            "Content-Length": "\(dataLength)",
        ]
        let statusCode: Int
        if let range {
            statusCode = 206
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound)/\(fileSize)"
        } else {
            statusCode = 200
        }

        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) ?? URLResponse(
            url: url,
            mimeType: mimeType(for: fileURL),
            expectedContentLength: dataLength,
            textEncodingName: nil
        )
    }
}

private enum WebDownloadManagerError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case noPlaylistTracksSaved

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The EarWorm server did not return a valid download response."
        case .httpStatus(let status):
            return "The EarWorm server returned HTTP \(status)."
        case .noPlaylistTracksSaved:
            return "EarWorm could not save any tracks from that playlist."
        }
    }
}
