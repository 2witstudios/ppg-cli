import Foundation

/// Connection configuration for a ppg server instance.
///
/// Stores the host, port, TLS CA certificate, and auth token needed to
/// communicate with a ppg server over REST and WebSocket.
struct ServerConnection: Codable, Identifiable, Hashable {
    let id: UUID
    var host: String
    var port: Int
    var caCertificate: String?
    var token: String

    /// Human-readable label (e.g. "192.168.1.5:7700").
    var displayName: String {
        "\(host):\(port)"
    }

    // MARK: - URL Builders

    private var scheme: String {
        caCertificate != nil ? "https" : "http"
    }

    private var wsScheme: String {
        caCertificate != nil ? "wss" : "ws"
    }

    /// Base URL for REST API requests (e.g. `http://192.168.1.5:7700`).
    var baseURL: URL {
        URL(string: "\(scheme)://\(host):\(port)")!
    }

    /// URL for a specific REST API endpoint.
    ///
    ///     connection.restURL(for: "/api/status")
    func restURL(for path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    /// WebSocket URL with auth token in query string.
    ///
    ///     connection.webSocketURL  // ws://192.168.1.5:7700/ws?token=abc123
    var webSocketURL: URL {
        var components = URLComponents()
        components.scheme = wsScheme
        components.host = host
        components.port = port
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url!
    }

    // MARK: - QR Code

    /// Generates the QR code string for this connection.
    ///
    ///     ppg://connect?host=192.168.1.5&port=7700&token=abc123
    ///     ppg://connect?host=192.168.1.5&port=7700&ca=BASE64...&token=abc123
    var qrCodeString: String {
        var parts = "ppg://connect?host=\(host)&port=\(port)"
        if let ca = caCertificate {
            let encoded = ca.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ca
            parts += "&ca=\(encoded)"
        }
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        parts += "&token=\(encodedToken)"
        return parts
    }

    /// Parse a `ppg://connect?host=...&port=...&token=...` QR code string.
    ///
    /// Returns `nil` if the string doesn't match the expected scheme.
    static func fromQRCode(_ content: String) -> ServerConnection? {
        guard let components = URLComponents(string: content),
              components.scheme == "ppg",
              components.host == "connect" else {
            return nil
        }

        let items = components.queryItems ?? []
        guard let host = items.first(where: { $0.name == "host" })?.value,
              let portString = items.first(where: { $0.name == "port" })?.value,
              let port = Int(portString),
              let token = items.first(where: { $0.name == "token" })?.value else {
            return nil
        }

        let ca = items.first(where: { $0.name == "ca" })?.value

        return ServerConnection(
            id: UUID(),
            host: host,
            port: port,
            caCertificate: ca,
            token: token
        )
    }

    // MARK: - Auth Header

    /// Authorization header value for REST requests.
    var authorizationHeader: String {
        "Bearer \(token)"
    }
}
