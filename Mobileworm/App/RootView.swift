import SwiftUI

struct RootView: View {
    @Bindable var appModel: AppModel
    @Environment(\.openURL) private var openURL

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
                        onOpenInSafari: {
                            guard let url = URL(string: server.baseURL) else { return }
                            openURL(url)
                        },
                        onLoadFailure: { message in
                            appModel.handleWebLoadFailure(message)
                        }
                    )
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
    }
}
