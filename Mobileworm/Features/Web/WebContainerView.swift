import SwiftUI

struct WebContainerView: View {
    let server: SavedServer
    let onChangeServer: () -> Void
    let onOpenInSafari: () -> Void
    let onLoadFailure: (String) -> Void

    @State private var isShowingChangeServerDialog = false

    var body: some View {
        Group {
            if let url = URL(string: server.baseURL) {
                EarwormWebView(url: url, onLoadFailure: onLoadFailure)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    "Invalid Server URL",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The saved EarWorm server URL is invalid. Change the server to continue.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Open in Safari", action: onOpenInSafari)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Change Server") {
                    isShowingChangeServerDialog = true
                }
            }
        }
        .navigationTitle(server.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Change Server",
            isPresented: $isShowingChangeServerDialog,
            titleVisibility: .visible
        ) {
            Button("Change Server", role: .destructive, action: onChangeServer)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the saved EarWorm server and returns you to the connection screen.")
        }
    }
}
