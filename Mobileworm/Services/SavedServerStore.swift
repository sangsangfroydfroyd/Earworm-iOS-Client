import Foundation

struct SavedServerStore {
    private let defaults: UserDefaults
    private let key = "saved_earworm_server"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SavedServer? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedServer.self, from: data)
    }

    func save(_ server: SavedServer) {
        guard let data = try? JSONEncoder().encode(server) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
