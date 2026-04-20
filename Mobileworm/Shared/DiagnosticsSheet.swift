import SwiftUI
import UIKit

struct DiagnosticsSheet: View {
    @Bindable var diagnostics: AppDiagnosticsStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Capture this report after reproducing the issue, then share or copy it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Snapshot") {
                    snapshotRow("Destination", diagnostics.destination)
                    snapshotRow("Server URL", diagnostics.serverURL ?? "nil")
                    snapshotRow("Authenticated", diagnostics.isAuthenticated ? "true" : "false")
                    snapshotRow("Current Page URL", diagnostics.currentPageURL ?? "nil")
                    snapshotRow("Current Page Title", diagnostics.currentPageTitle ?? "nil")
                    snapshotRow("WebView Loading", diagnostics.webViewLoading ? "true" : "false")
                    snapshotRow("WebView Progress", String(format: "%.3f", diagnostics.webViewEstimatedProgress))
                    snapshotRow("Last Load Failure", diagnostics.lastLoadFailure ?? "nil")
                    snapshotRow("Last Now Playing", diagnostics.lastNowPlayingSummary ?? "nil")
                }

                Section("Recent Events") {
                    if diagnostics.entries.isEmpty {
                        Text("No events captured yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(diagnostics.entries.reversed())) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("[\(entry.level.rawValue)] \(entry.category)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: entry.level))
                                Text(entry.message)
                                    .font(.subheadline)
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if !entry.metadata.isEmpty {
                                    Text(
                                        entry.metadata
                                            .keys
                                            .sorted()
                                            .map { key in
                                                "\(key): \(entry.metadata[key] ?? "")"
                                            }
                                            .joined(separator: "\n")
                                    )
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Copy") {
                        UIPasteboard.general.string = diagnostics.exportText()
                        copied = true
                    }

                    ShareLink(
                        item: diagnostics.exportText(),
                        preview: SharePreview("MobileWorm Diagnostics")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Button("Clear Log", role: .destructive) {
                        diagnostics.clear()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if copied {
                    Text("Diagnostics copied")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copied)
            .onChange(of: copied) { _, newValue in
                guard newValue else { return }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
        }
    }

    @ViewBuilder
    private func snapshotRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func color(for level: AppDiagnosticsStore.Level) -> Color {
        switch level {
        case .debug:
            return .secondary
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
