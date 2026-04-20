import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppDiagnosticsStore {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        let metadata: [String: String]
    }

    static let shared = AppDiagnosticsStore()

    private let maxEntries = 400

    private(set) var entries: [Entry] = []
    var destination = "launching"
    var serverURL: String?
    var isAuthenticated = false
    var currentPageURL: String?
    var currentPageTitle: String?
    var webViewLoading = false
    var webViewEstimatedProgress = 0.0
    var lastLoadFailure: String?
    var lastNowPlayingSummary: String?

    private init() {}

    func clear() {
        entries.removeAll()
        record(
            .info,
            category: "diagnostics",
            message: "Diagnostics log cleared."
        )
    }

    func record(
        _ level: Level,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let entry = Entry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func updateDestination(_ destination: String) {
        self.destination = destination
    }

    func updateServerURL(_ serverURL: String?) {
        self.serverURL = serverURL
    }

    func updateAuthenticationState(_ authenticated: Bool) {
        isAuthenticated = authenticated
    }

    func updateWebViewState(
        url: String?,
        title: String?,
        isLoading: Bool,
        estimatedProgress: Double
    ) {
        currentPageURL = url
        currentPageTitle = title
        webViewLoading = isLoading
        webViewEstimatedProgress = estimatedProgress
    }

    func markLoadFailure(_ message: String) {
        lastLoadFailure = message
    }

    func updateNowPlayingSummary(_ summary: String?) {
        lastNowPlayingSummary = summary
    }

    func exportText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let device = UIDevice.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        lines.append("MobileWorm Diagnostics")
        lines.append("Generated: \(formatter.string(from: Date()))")
        lines.append("App: \(version) (\(build))")
        lines.append("Device: \(device.model)")
        lines.append("System: \(device.systemName) \(device.systemVersion)")
        lines.append("")
        lines.append("Snapshot")
        lines.append("Destination: \(destination)")
        lines.append("Server URL: \(serverURL ?? "nil")")
        lines.append("Authenticated: \(isAuthenticated ? "true" : "false")")
        lines.append("Current Page URL: \(currentPageURL ?? "nil")")
        lines.append("Current Page Title: \(currentPageTitle ?? "nil")")
        lines.append("WebView Loading: \(webViewLoading ? "true" : "false")")
        lines.append(String(format: "WebView Progress: %.3f", webViewEstimatedProgress))
        lines.append("Last Load Failure: \(lastLoadFailure ?? "nil")")
        lines.append("Last Now Playing: \(lastNowPlayingSummary ?? "nil")")
        lines.append("")
        lines.append("Events")

        for entry in entries {
            let timestamp = formatter.string(from: entry.timestamp)
            lines.append("[\(timestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)")
            if !entry.metadata.isEmpty {
                for key in entry.metadata.keys.sorted() {
                    lines.append("  \(key): \(entry.metadata[key] ?? "")")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
