import Foundation

// MARK: - Error Types

enum PPGClientError: LocalizedError {
    case notConfigured
    case invalidURL(String)
    case network(URLError)
    case unauthorized
    case notFound(String)
    case conflict(String)
    case serverError(Int, String)
    case decodingError(DecodingError)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No server connection configured"
        case .invalidURL(let path):
            return "Invalid URL: \(path)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication failed — check your token"
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .conflict(let msg):
            return "Conflict: \(msg)"
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

// MARK: - TLS Delegate

/// Allows connections to servers using a self-signed certificate
/// by trusting a pinned CA certificate bundled with the app.
private final class PinnedCertDelegate: NSObject, URLSessionDelegate, Sendable {
    private let pinnedCert: SecCertificate?

    init(pinnedCertificateNamed name: String = "ppg-ca") {
        if let url = Bundle.main.url(forResource: name, withExtension: "der"),
           let data = try? Data(contentsOf: url) {
            pinnedCert = SecCertificateCreateWithData(nil, data as CFData)
        } else {
            pinnedCert = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let pinned = pinnedCert else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Set the pinned CA as the sole anchor for evaluation
        SecTrustSetAnchorCertificates(serverTrust, [pinned] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - REST Client

/// Thread-safe REST client for the ppg serve API.
///
/// Covers all 13 endpoints (7 read + 6 write) with async/await,
/// bearer token auth, and optional pinned-CA TLS trust.
actor PPGClient {
    private let session: URLSession
    private var connection: ServerConnection?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let delegate = PinnedCertDelegate()
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func configure(connection: ServerConnection) {
        self.connection = connection
    }

    // MARK: - Connection Test

    /// Verifies reachability and auth by hitting the status endpoint.
    /// Returns `true` on success, throws on failure.
    @discardableResult
    func testConnection() async throws -> Bool {
        let _: Manifest = try await get("/api/status")
        return true
    }

    // MARK: - Read API

    func fetchStatus() async throws -> Manifest {
        return try await get("/api/status")
    }

    func fetchWorktree(id: String) async throws -> WorktreeEntry {
        return try await get("/api/worktrees/\(id)")
    }

    func fetchDiff(worktreeId: String) async throws -> DiffResponse {
        return try await get("/api/worktrees/\(worktreeId)/diff")
    }

    func fetchAgentLogs(agentId: String, lines: Int = 200) async throws -> LogsResponse {
        return try await get("/api/agents/\(agentId)/logs?lines=\(lines)")
    }

    func fetchConfig() async throws -> Config {
        return try await get("/api/config")
    }

    func fetchTemplates() async throws -> TemplatesResponse {
        return try await get("/api/templates")
    }

    func fetchPrompts() async throws -> PromptsResponse {
        return try await get("/api/prompts")
    }

    func fetchSwarms() async throws -> SwarmsResponse {
        return try await get("/api/swarms")
    }

    // MARK: - Write API

    func spawn(
        name: String?,
        agent: String?,
        prompt: String,
        template: String? = nil,
        base: String? = nil,
        count: Int = 1
    ) async throws -> SpawnResponse {
        var body: [String: Any] = ["prompt": prompt, "count": count]
        if let name { body["name"] = name }
        if let agent { body["agent"] = agent }
        if let template { body["template"] = template }
        if let base { body["base"] = base }
        return try await post("/api/spawn", body: body)
    }

    func sendToAgent(agentId: String, text: String, keys: Bool = false) async throws {
        let body: [String: Any] = ["text": text, "keys": keys]
        let _: SuccessResponse = try await post("/api/agents/\(agentId)/send", body: body)
    }

    func killAgent(agentId: String) async throws {
        let body: [String: Any] = [:]
        let _: SuccessResponse = try await post("/api/agents/\(agentId)/kill", body: body)
    }

    func restartAgent(agentId: String, prompt: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let prompt { body["prompt"] = prompt }
        let _: SuccessResponse = try await post("/api/agents/\(agentId)/restart", body: body)
    }

    func mergeWorktree(worktreeId: String, strategy: String = "squash", force: Bool = false) async throws {
        let body: [String: Any] = ["strategy": strategy, "force": force]
        let _: SuccessResponse = try await post("/api/worktrees/\(worktreeId)/merge", body: body)
    }

    func killWorktree(worktreeId: String) async throws {
        let body: [String: Any] = [:]
        let _: SuccessResponse = try await post("/api/worktrees/\(worktreeId)/kill", body: body)
    }

    func createPR(worktreeId: String, title: String? = nil, draft: Bool = false) async throws -> PRResponse {
        var body: [String: Any] = ["draft": draft]
        if let title { body["title"] = title }
        return try await post("/api/worktrees/\(worktreeId)/pr", body: body)
    }

    // MARK: - Private Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try makeRequest(path: path, method: "GET")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decode(data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = try makeRequest(path: path, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decode(data)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let conn = connection else {
            throw PPGClientError.notConfigured
        }
        guard let url = URL(string: path, relativeTo: conn.baseURL) else {
            throw PPGClientError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(conn.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw PPGClientError.network(urlError)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw PPGClientError.decodingError(decodingError)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PPGClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"

            switch http.statusCode {
            case 401:
                throw PPGClientError.unauthorized
            case 404:
                throw PPGClientError.notFound(msg)
            case 409:
                throw PPGClientError.conflict(msg)
            default:
                throw PPGClientError.serverError(http.statusCode, msg)
            }
        }
    }
}

// MARK: - Response Types (used only by PPGClient)

private struct SuccessResponse: Decodable {
    let success: Bool?

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        success = try container?.decodeIfPresent(Bool.self, forKey: .success)
    }

    private enum CodingKeys: String, CodingKey {
        case success
    }
}

struct PRResponse: Codable {
    let url: String?
    let prUrl: String?
    let title: String?
    let draft: Bool?
}
