import SwiftUI

struct AppSettingsSheet: View {
    let serverURL: String?
    let onChangeServer: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDiagnostics = false
    @State private var isConfirmingServerReset = false

    var body: some View {
        NavigationStack {
            List {
                Section("EarWorm Server") {
                    LabeledContent("Connected URL") {
                        Text(serverURL ?? "Not connected")
                            .font(.footnote.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }

                    Button("Change EarWorm Server", role: .destructive) {
                        isConfirmingServerReset = true
                    }
                }

                Section("Developer") {
                    Button {
                        isShowingDiagnostics = true
                    } label: {
                        Label("Open Diagnostics", systemImage: "ladybug.fill")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Change EarWorm Server",
                isPresented: $isConfirmingServerReset,
                titleVisibility: .visible
            ) {
                Button("Change Server", role: .destructive) {
                    dismiss()
                    onChangeServer()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the saved EarWorm host and returns MobileWorm to the connection screen.")
            }
            .sheet(isPresented: $isShowingDiagnostics) {
                DiagnosticsSheet(diagnostics: AppDiagnosticsStore.shared)
            }
        }
    }
}
