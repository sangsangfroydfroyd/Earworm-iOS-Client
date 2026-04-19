import AVFoundation
import Foundation
import MediaPlayer
import UIKit

struct WebNowPlayingPayload {
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool

    init?(messageBody: [String: Any]) {
        guard
            let title = messageBody["title"] as? String,
            let artistName = messageBody["artistName"] as? String
        else {
            return nil
        }

        self.title = title
        self.artistName = artistName
        self.albumTitle = messageBody["albumTitle"] as? String
        if
            let artworkURLString = messageBody["artworkUrl"] as? String,
            let url = URL(string: artworkURLString)
        {
            self.artworkURL = url
        } else {
            self.artworkURL = nil
        }
        self.duration = (messageBody["duration"] as? NSNumber)?.doubleValue ?? 0
        self.position = (messageBody["position"] as? NSNumber)?.doubleValue ?? 0
        self.isPlaying = (messageBody["isPlaying"] as? Bool) ?? false
    }
}

@MainActor
final class WebNowPlayingManager {
    static let shared = WebNowPlayingManager()

    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var artworkTask: Task<Void, Never>?
    private var currentArtworkURLString: String?

    func update(payload: WebNowPlayingPayload, cookies: [HTTPCookie]) {
        activateAudioSession()

        var info = baseNowPlayingInfo(for: payload)
        if
            let artworkURLString = payload.artworkURL?.absoluteString,
            let cachedArtwork = artworkCache[artworkURLString]
        {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let artworkURL = payload.artworkURL else {
            currentArtworkURLString = nil
            artworkTask?.cancel()
            return
        }

        let artworkURLString = artworkURL.absoluteString
        currentArtworkURLString = artworkURLString
        guard artworkCache[artworkURLString] == nil else {
            return
        }

        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            do {
                let data = try await Self.fetchArtworkData(from: artworkURL, cookies: cookies)
                guard !Task.isCancelled, let image = UIImage(data: data) else {
                    return
                }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await self?.installArtwork(artwork, for: artworkURLString)
            } catch {
                return
            }
        }
    }

    func clear() {
        artworkTask?.cancel()
        currentArtworkURLString = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func installArtwork(_ artwork: MPMediaItemArtwork, for urlString: String) {
        artworkCache[urlString] = artwork
        guard currentArtworkURLString == urlString else {
            return
        }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func baseNowPlayingInfo(for payload: WebNowPlayingPayload) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: payload.title,
            MPMediaItemPropertyArtist: payload.artistName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, payload.position),
            MPNowPlayingInfoPropertyPlaybackRate: payload.isPlaying ? 1.0 : 0.0,
        ]

        if let albumTitle = payload.albumTitle, !albumTitle.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }

        if payload.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = payload.duration
        }

        return info
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            return
        }
    }

    nonisolated private static func fetchArtworkData(from url: URL, cookies: [HTTPCookie]) async throws -> Data {
        var request = URLRequest(url: url)
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        if let cookieHeader = cookieHeaders["Cookie"] {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
