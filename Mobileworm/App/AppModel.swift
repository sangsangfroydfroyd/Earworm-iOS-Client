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

    init(
        savedServerStore: SavedServerStore = SavedServerStore(),
        validationService: ServerValidationService = ServerValidationService()
    ) {
        self.savedServerStore = savedServerStore
        self.validationService = validationService
    }

    func bootstrap() async {
        if let savedServer = savedServerStore.load() {
            serverInput = savedServer.baseURL
            activeServer = savedServer
            await reconnect(using: savedServer.baseURL)
        } else {
            destination = .connect
        }
    }

    func connect() async {
        errorMessage = nil
        destination = .validating

        do {
            let server = try await validationService.validateServer(from: serverInput)
            savedServerStore.save(server)
            activeServer = server
            serverInput = server.baseURL
            destination = .web
        } catch {
            destination = .connect
            errorMessage = Self.message(for: error)
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
    }

    func handleWebLoadFailure(_ message: String) {
        destination = .recovery(message)
    }

    private func reconnect(using baseURL: String) async {
        errorMessage = nil
        destination = .validating

        do {
            let server = try await validationService.validateServer(from: baseURL)
            savedServerStore.save(server)
            activeServer = server
            serverInput = server.baseURL
            destination = .web
        } catch {
            destination = .recovery(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
