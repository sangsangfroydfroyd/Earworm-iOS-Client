import SwiftUI

struct WebContainerView: View {
    let server: SavedServer
    let onChangeServer: () -> Void
    let onLoadFailure: (String) -> Void

    @State private var isShowingChangeServerDialog = false
    @State private var isAuthenticated = false

    var body: some View {
        Group {
            if let url = URL(string: server.baseURL) {
                ZStack(alignment: .bottom) {
                    EarwormWebView(
                        url: url,
                        onAuthenticationStateChanged: { isAuthenticated = $0 },
                        onLoadFailure: onLoadFailure
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isAuthenticated {
                        Button {
                            isShowingChangeServerDialog = true
                        } label: {
                            Text("Change EarWorm Server")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(red: 0.055, green: 0.055, blue: 0.075))
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                        .background(.clear)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Invalid Server URL",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The saved EarWorm server URL is invalid. Change the server to continue.")
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Change Server",
            isPresented: $isShowingChangeServerDialog,
            titleVisibility: .visible
        ) {
            Button("Change Server", role: .destructive, action: onChangeServer)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isAuthenticated
                ? "This clears the saved EarWorm server and returns you to the connection screen."
                : "This clears the saved server before you sign in so you can enter a different EarWorm URL.")
        }
    }
}
