import Foundation

struct SavedServer: Codable, Equatable {
    enum ValidationSource: String, Codable {
        case authStatus
        case clientInfo
    }

    let id: String
    let displayName: String
    let baseURL: String
    let lastValidatedAt: Date
    let validationSource: ValidationSource
}
