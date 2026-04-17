import SwiftUI

@main
struct MobilewormApp: App {
    @State private var appModel = AppModel()
    @State private var hasBootstrapped = false

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel)
                .task {
                    guard !hasBootstrapped else { return }
                    hasBootstrapped = true
                    await appModel.bootstrap()
                }
        }
    }
}
