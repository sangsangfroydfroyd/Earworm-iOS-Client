import Foundation

struct DownloadedTrackFile {
    let filename: String
    let url: URL
}

actor WebDownloadManager {
    static let shared = WebDownloadManager()

    private let folderName = "EarWorm Downloads"

    func downloadTrack(from sourceURL: URL, filename: String, cookies: [HTTPCookie]) async throws -> DownloadedTrackFile {
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

        let downloadsDirectory = try ensureDownloadsDirectory()
        let destinationURL = uniqueDestinationURL(
            in: downloadsDirectory,
            filename: sanitizedFilename(filename)
        )
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

        return DownloadedTrackFile(filename: destinationURL.lastPathComponent, url: destinationURL)
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
}

private enum WebDownloadManagerError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The EarWorm server did not return a valid download response."
        case .httpStatus(let status):
            return "The EarWorm server returned HTTP \(status)."
        }
    }
}
