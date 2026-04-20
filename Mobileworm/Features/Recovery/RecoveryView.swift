import SwiftUI

struct RecoveryView: View {
    let message: String
    let serverURL: String?
    let onRetry: () async -> Void
    let onChangeServer: () -> Void
    let onOpenInSafari: () -> Void
    @State private var isShowingDiagnostics = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)

                Text("Couldn't reconnect to EarWorm")
                    .font(.title2.bold())

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let serverURL {
                Text(serverURL)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        await onRetry()
                    }
                } label: {
                    Text("Retry")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Change Server", action: onChangeServer)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)

                Button("Open in Safari", action: onOpenInSafari)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)

                Button("View Diagnostics") {
                    isShowingDiagnostics = true
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Spacer()
        }
        .padding(24)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsSheet(diagnostics: AppDiagnosticsStore.shared)
        }
    }
}
