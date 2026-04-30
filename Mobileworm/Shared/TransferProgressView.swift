import Observation
import SwiftUI

enum TransferProgressKind: String {
    case images
    case songs
}

struct TransferProgressItem: Identifiable, Equatable {
    let id: String
    let kind: TransferProgressKind
    var title: String
    var detail: String
    var completed: Int
    var total: Int?
    var progressFraction: Double?
    var progressLabel: String?
    var isFinished: Bool
    var failed: Bool

    var fraction: Double? {
        if let progressFraction {
            return min(1, max(0, progressFraction))
        }
        guard let total, total > 0 else {
            return nil
        }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

@MainActor
@Observable
final class TransferProgressStore {
    static let shared = TransferProgressStore()

    private(set) var imageProgress: TransferProgressItem?
    private(set) var songProgress: TransferProgressItem?
    private var imageGeneration = 0
    private var songGeneration = 0

    var visibleItems: [TransferProgressItem] {
        [imageProgress, songProgress].compactMap { $0 }
    }

    func start(
        _ kind: TransferProgressKind,
        title: String,
        detail: String,
        completed: Int = 0,
        total: Int? = nil,
        progressFraction: Double? = nil,
        progressLabel: String? = nil
    ) {
        _ = advanceGeneration(for: kind)
        setProgress(TransferProgressItem(
            id: kind.rawValue,
            kind: kind,
            title: title,
            detail: detail,
            completed: completed,
            total: total,
            progressFraction: progressFraction,
            progressLabel: progressLabel,
            isFinished: false,
            failed: false
        ))
    }

    func update(
        _ kind: TransferProgressKind,
        title: String? = nil,
        detail: String,
        completed: Int,
        total: Int? = nil,
        progressFraction: Double? = nil,
        progressLabel: String? = nil
    ) {
        var progress = item(for: kind) ?? TransferProgressItem(
            id: kind.rawValue,
            kind: kind,
            title: title ?? defaultTitle(for: kind),
            detail: detail,
            completed: completed,
            total: total,
            progressFraction: progressFraction,
            progressLabel: progressLabel,
            isFinished: false,
            failed: false
        )
        if let title {
            progress.title = title
        }
        progress.detail = detail
        progress.completed = completed
        progress.total = total ?? progress.total
        progress.progressFraction = progressFraction
        progress.progressLabel = progressLabel
        progress.isFinished = false
        progress.failed = false
        setProgress(progress)
    }

    func finish(_ kind: TransferProgressKind, detail: String, failed: Bool = false) {
        let finishedGeneration = advanceGeneration(for: kind)
        var progress = item(for: kind) ?? TransferProgressItem(
            id: kind.rawValue,
            kind: kind,
            title: defaultTitle(for: kind),
            detail: detail,
            completed: 1,
            total: 1,
            progressFraction: 1,
            progressLabel: nil,
            isFinished: true,
            failed: failed
        )
        progress.detail = detail
        progress.completed = progress.total ?? max(progress.completed, 1)
        progress.progressFraction = failed ? progress.progressFraction : 1
        progress.progressLabel = nil
        progress.isFinished = true
        progress.failed = failed
        setProgress(progress)

        let finishedID = progress.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(failed ? 4 : 2))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard
                    let self,
                    self.currentGeneration(for: kind) == finishedGeneration,
                    self.item(for: kind)?.id == finishedID,
                    self.item(for: kind)?.isFinished == true
                else {
                    return
                }
                self.clear(kind)
            }
        }
    }

    func clear(_ kind: TransferProgressKind) {
        switch kind {
        case .images:
            imageProgress = nil
        case .songs:
            songProgress = nil
        }
    }

    private func advanceGeneration(for kind: TransferProgressKind) -> Int {
        switch kind {
        case .images:
            imageGeneration += 1
            return imageGeneration
        case .songs:
            songGeneration += 1
            return songGeneration
        }
    }

    private func currentGeneration(for kind: TransferProgressKind) -> Int {
        switch kind {
        case .images:
            return imageGeneration
        case .songs:
            return songGeneration
        }
    }

    private func item(for kind: TransferProgressKind) -> TransferProgressItem? {
        switch kind {
        case .images:
            return imageProgress
        case .songs:
            return songProgress
        }
    }

    private func setProgress(_ progress: TransferProgressItem) {
        switch progress.kind {
        case .images:
            imageProgress = progress
        case .songs:
            songProgress = progress
        }
    }

    private func defaultTitle(for kind: TransferProgressKind) -> String {
        switch kind {
        case .images:
            return "Artwork cache"
        case .songs:
            return "Song downloads"
        }
    }
}

struct TransferProgressBanner: View {
    let store: TransferProgressStore

    var body: some View {
        let items = store.visibleItems
        let isVisible = !items.isEmpty
        VStack(spacing: 8) {
            ForEach(items) { item in
                TransferProgressRow(item: item)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -90)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isVisible)
    }
}

private struct TransferProgressRow: View {
    let item: TransferProgressItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !item.isFinished, let label = progressLabel {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .monospacedDigit()
                }
            }

            if let fraction = item.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(iconColor)
                    .frame(height: 4)
                    .animation(.linear(duration: 0.18), value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(iconColor)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 2)
    }

    private var iconName: String {
        if item.failed {
            return "exclamationmark.triangle.fill"
        }
        if item.isFinished {
            return "checkmark.circle.fill"
        }
        switch item.kind {
        case .images:
            return "photo.on.rectangle.angled"
        case .songs:
            return "music.note"
        }
    }

    private var iconColor: Color {
        if item.failed {
            return .red
        }
        if item.isFinished {
            return .green
        }
        switch item.kind {
        case .images:
            return .orange
        case .songs:
            return .cyan
        }
    }

    private var progressLabel: String? {
        if let label = item.progressLabel {
            return label
        }
        guard let total = item.total, total > 0 else {
            return nil
        }
        return "\(item.completed)/\(total)"
    }
}
