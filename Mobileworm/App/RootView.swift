import SwiftUI

struct RootView: View {
    @Bindable var appModel: AppModel
    @Environment(\.openURL) private var openURL
    @State private var isShowingDiagnostics = false

    var body: some View {
        NavigationStack {
            switch appModel.destination {
            case .launching, .validating:
                LoadingView()
            case .connect:
                ConnectServerView(
                    serverInput: $appModel.serverInput,
                    errorMessage: appModel.errorMessage,
                    onConnect: {
                        await appModel.connect()
                    }
                )
            case .web:
                if let server = appModel.activeServer {
                    WebContainerView(
                        server: server,
                        onChangeServer: appModel.changeServer,
                        onLoadFailure: { message in
                            appModel.handleWebLoadFailure(message)
                        }
                    )
                    .ignoresSafeArea(.container)
                } else {
                    LoadingView()
                }
            case .recovery(let message):
                RecoveryView(
                    message: message,
                    serverURL: appModel.activeServer?.baseURL,
                    onRetry: {
                        await appModel.reconnect()
                    },
                    onChangeServer: appModel.changeServer,
                    onOpenInSafari: {
                        guard
                            let rawURL = appModel.activeServer?.baseURL,
                            let url = URL(string: rawURL)
                        else {
                            return
                        }
                        openURL(url)
                    }
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(red: 0.039, green: 0.039, blue: 0.039).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                isShowingDiagnostics = true
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Open diagnostics")
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsSheet(diagnostics: AppDiagnosticsStore.shared)
        }
    }
}
