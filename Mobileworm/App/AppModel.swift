import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Destination: Equatable {
        case launching
        case connect
        case validating
        case web
        case recovery(String)
    }

    var destination: Destination = .launching
    var serverInput = ""
    var errorMessage: String?
    var activeServer: SavedServer?

    private let savedServerStore: SavedServerStore
    private let validationService: ServerValidationService
    private let diagnostics = AppDiagnosticsStore.shared

    init(
        savedServerStore: SavedServerStore = SavedServerStore(),
        validationService: ServerValidationService = ServerValidationService()
    ) {
        self.savedServerStore = savedServerStore
        self.validationService = validationService
        diagnostics.updateDestination(Self.describeDestination(.launching))
        diagnostics.record(.info, category: "app", message: "MobileWorm launched.")
    }

    func bootstrap() async {
        diagnostics.record(.info, category: "bootstrap", message: "Bootstrapping saved server state.")
        if let savedServer = savedServerStore.load() {
            serverInput = savedServer.baseURL
            activeServer = savedServer
            diagnostics.updateServerURL(savedServer.baseURL)
            diagnostics.record(
                .info,
                category: "bootstrap",
                message: "Found saved EarWorm server.",
                metadata: ["serverURL": savedServer.baseURL]
            )
            await reconnect(using: savedServer.baseURL)
        } else {
            destination = .connect
            diagnostics.updateDestination(Self.describeDestination(.connect))
            diagnostics.record(.info, category: "bootstrap", message: "No saved server found.")
        }
    }

    func connect() async {
        errorMessage = nil
        destination = .validating
        diagnostics.updateDestination(Self.describeDestination(.validating))
        diagnostics.record(
            .info,
            category: "connect",
            message: "Validating EarWorm server from connect screen.",
            metadata: ["serverURL": serverInput]
        )

        do {
            let server = try await validationService.validateServer(from: serverInput)
            savedServerStore.save(server)
            activeServer = server
            serverInput = server.baseURL
            destination = .web
            diagnostics.updateDestination(Self.describeDestination(.web))
            diagnostics.updateServerURL(server.baseURL)
            diagnostics.record(
                .info,
                category: "connect",
                message: "EarWorm server validated successfully.",
                metadata: ["serverURL": server.baseURL]
            )
        } catch {
            destination = .connect
            errorMessage = Self.message(for: error)
            diagnostics.updateDestination(Self.describeDestination(.connect))
            diagnostics.record(
                .error,
                category: "connect",
                message: "EarWorm server validation failed.",
                metadata: [
                    "serverURL": serverInput,
                    "error": errorMessage ?? error.localizedDescription,
                ]
            )
        }
    }

    func reconnect() async {
        guard let baseURL = activeServer?.baseURL ?? savedServerStore.load()?.baseURL else {
            changeServer()
            return
        }

        await reconnect(using: baseURL)
    }

    func changeServer() {
        savedServerStore.clear()
        activeServer = nil
        errorMessage = nil
        serverInput = ""
        destination = .connect
        diagnostics.updateDestination(Self.describeDestination(.connect))
        diagnostics.updateServerURL(nil)
        diagnostics.updateAuthenticationState(false)
        diagnostics.record(.warning, category: "server", message: "Cleared saved EarWorm server.")
    }

    func handleWebLoadFailure(_ message: String) {
        destination = .recovery(message)
        diagnostics.updateDestination(Self.describeDestination(.recovery(message)))
        diagnostics.markLoadFailure(message)
        diagnostics.record(
            .error,
            category: "webview",
            message: "Embedded EarWorm web view failed to load.",
            metadata: ["error": message]
        )
    }

    private func reconnect(using baseURL: String) async {
        errorMessage = nil
        destination = .validating
        diagnostics.updateDestination(Self.describeDestination(.validating))
        diagnostics.record(
            .info,
            category: "reconnect",
            message: "Revalidating saved EarWorm server.",
            metadata: ["serverURL": baseURL]
        )

        do {
            let server = try await validationService.validateServer(from: baseURL)
            savedServerStore.save(server)
            activeServer = server
            serverInput = server.baseURL
            destination = .web
            diagnostics.updateDestination(Self.describeDestination(.web))
            diagnostics.updateServerURL(server.baseURL)
            diagnostics.record(
                .info,
                category: "reconnect",
                message: "Saved EarWorm server revalidated.",
                metadata: ["serverURL": server.baseURL]
            )
        } catch {
            let message = Self.message(for: error)
            if let savedServer = savedServerStore.load() {
                activeServer = savedServer
                serverInput = savedServer.baseURL
                destination = .web
                diagnostics.updateDestination(Self.describeDestination(.web))
                diagnostics.updateServerURL(savedServer.baseURL)
                diagnostics.record(
                    .warning,
                    category: "reconnect",
                    message: "Saved EarWorm server revalidation failed; opening cached web UI.",
                    metadata: [
                        "serverURL": baseURL,
                        "error": message,
                    ]
                )
                return
            }

            destination = .recovery(message)
            diagnostics.updateDestination(Self.describeDestination(.recovery(message)))
            diagnostics.markLoadFailure(message)
            diagnostics.record(
                .error,
                category: "reconnect",
                message: "Saved EarWorm server revalidation failed.",
                metadata: [
                    "serverURL": baseURL,
                    "error": message,
                ]
            )
        }
    }

    private static func describeDestination(_ destination: Destination) -> String {
        switch destination {
        case .launching:
            return "launching"
        case .connect:
            return "connect"
        case .validating:
            return "validating"
        case .web:
            return "web"
        case .recovery:
            return "recovery"
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
