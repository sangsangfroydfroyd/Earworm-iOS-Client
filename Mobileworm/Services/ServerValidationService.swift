import Foundation

struct ServerValidationService {
    func validateServer(from rawInput: String) async throws -> SavedServer {
        let normalizedBaseURL = try normalizeBaseURL(from: rawInput)
        let statusURL = normalizedBaseURL.appending(path: "api/auth/status")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: statusURL)
        } catch let error as URLError {
            throw mapNetworkError(error)
        } catch {
            throw ValidationError.networkFailure("EarWorm could not reach that server.")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ValidationError.networkFailure("EarWorm returned HTTP \(httpResponse.statusCode).")
        }

        let authStatus = try decodeAuthStatus(from: data)

        guard authStatus.serverName == "EarWorm" else {
            throw ValidationError.notEarWorm
        }

        let resolvedBaseURL = canonicalBaseURL(from: httpResponse.url, fallback: normalizedBaseURL)

        guard resolvedBaseURL.scheme?.lowercased() == "https" else {
            throw ValidationError.insecureURL
        }

        return SavedServer(
            id: resolvedBaseURL.absoluteString,
            displayName: authStatus.serverName,
            baseURL: resolvedBaseURL.absoluteString,
            lastValidatedAt: .now,
            validationSource: .authStatus
        )
    }

    private func normalizeBaseURL(from rawInput: String) throws -> URL {
        var trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyInput
        }

        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }

        guard let url = URL(string: trimmed) else {
            throw ValidationError.invalidURL
        }

        guard url.scheme?.lowercased() == "https" else {
            throw ValidationError.insecureURL
        }

        guard url.host?.isEmpty == false else {
            throw ValidationError.invalidURL
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil

        guard let normalizedURL = components?.url else {
            throw ValidationError.invalidURL
        }

        return normalizedURL
    }

    private func decodeAuthStatus(from data: Data) throws -> EarwormAuthStatus {
        do {
            return try JSONDecoder().decode(EarwormAuthStatus.self, from: data)
        } catch {
            throw ValidationError.notEarWorm
        }
    }

    private func mapNetworkError(_ error: URLError) -> ValidationError {
        switch error.code {
        case .serverCertificateHasBadDate,
                .serverCertificateUntrusted,
                .serverCertificateHasUnknownRoot,
                .serverCertificateNotYetValid,
                .clientCertificateRejected,
                .clientCertificateRequired,
                .secureConnectionFailed:
            return .tlsFailure
        default:
            return .networkFailure(error.localizedDescription)
        }
    }

    private func canonicalBaseURL(from responseURL: URL?, fallback: URL) -> URL {
        guard let responseURL else { return fallback }

        var components = URLComponents(url: responseURL, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil

        return components?.url ?? fallback
    }
}

private struct EarwormAuthStatus: Decodable {
    let serverName: String
}

enum ValidationError: LocalizedError {
    case emptyInput
    case invalidURL
    case insecureURL
    case invalidResponse
    case networkFailure(String)
    case notEarWorm
    case tlsFailure

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter your EarWorm server URL to continue."
        case .invalidURL:
            return "Enter a valid EarWorm server URL."
        case .insecureURL:
            return "EarWorm for iOS only supports HTTPS EarWorm servers in v1."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .networkFailure(let message):
            return message
        case .notEarWorm:
            return "This server is reachable, but it does not appear to be EarWorm."
        case .tlsFailure:
            return "EarWorm could not establish a trusted HTTPS connection to that server."
        }
    }
}
