import Foundation

/// Connection configuration for a ppg server instance.
///
/// Stores the host, port, TLS CA certificate, and auth token needed to
/// communicate with a ppg server over REST and WebSocket.
struct ServerConnection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var token: String
    var caCertificate: String?
    var isDefault: Bool

    init(id: UUID = UUID(), name: String = "My Mac", host: String, port: Int = 3100, token: String, caCertificate: String? = nil, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.token = token
        self.caCertificate = caCertificate
        self.isDefault = isDefault
    }

    /// Human-readable label (e.g. "192.168.1.5:3100").
    var displayName: String {
        "\(host):\(port)"
    }

    // MARK: - URL Builders

    private var usesTLS: Bool {
        caCertificate != nil
    }

    private var scheme: String {
        usesTLS ? "https" : "http"
    }

    private var wsScheme: String {
        usesTLS ? "wss" : "ws"
    }

    /// Base URL for REST API requests (e.g. `http://192.168.1.5:3100`).
    /// Returns `nil` if the host is malformed.
    var baseURL: URL? {
        makeURL(scheme: scheme)
    }

    /// URL for the API root.
    var apiURL: URL? {
        baseURL?.appendingPathComponent("api")
    }

    /// URL for a specific REST API endpoint.
    /// Returns `nil` if the base URL cannot be constructed.
    ///
    ///     connection.restURL(for: "/api/status")
    func restURL(for path: String) -> URL? {
        guard let base = baseURL else { return nil }
        return base.appending(path: path)
    }

    /// WebSocket URL with auth token in query string.
    /// Returns `nil` if the host is malformed.
    ///
    ///     connection.webSocketURL  // ws://192.168.1.5:3100/ws?token=abc123
    var webSocketURL: URL? {
        makeURL(
            scheme: wsScheme,
            path: "/ws",
            queryItems: [URLQueryItem(name: "token", value: token)]
        )
    }

    // MARK: - QR Code

    /// Generates the QR code string for this connection.
    ///
    ///     ppg://connect?host=192.168.1.5&port=3100&token=abc123
    ///     ppg://connect?host=192.168.1.5&port=3100&ca=BASE64...&token=abc123
    var qrCodeString: String {
        var components = URLComponents()
        components.scheme = "ppg"
        components.host = "connect"
        var items = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
        ]
        if let ca = caCertificate {
            items.append(URLQueryItem(name: "ca", value: ca))
        }
        items.append(URLQueryItem(name: "token", value: token))
        components.queryItems = items
        return components.string ?? "ppg://connect"
    }

    /// Parse a ppg serve QR code payload.
    /// Format: ppg://connect?host=<host>&port=<port>&token=<token>[&ca=<base64>]
    static func fromQRCode(_ payload: String) -> ServerConnection? {
        guard let components = URLComponents(string: payload),
              components.scheme?.lowercased() == "ppg",
              components.host?.lowercased() == "connect"
        else {
            return nil
        }

        let params = Dictionary(
            (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            },
            uniquingKeysWith: { _, last in last }
        )

        guard let host = params["host"], isValidHost(host),
              let token = params["token"], !token.isEmpty
        else {
            return nil
        }

        let port = params["port"].flatMap(Int.init) ?? 3100
        guard (1...65_535).contains(port) else { return nil }
        let ca = params["ca"].flatMap { Data(base64Encoded: $0) != nil ? $0 : nil }

        return ServerConnection(
            name: host == "0.0.0.0" ? "Local Mac" : host,
            host: host,
            port: port,
            token: token,
            caCertificate: ca
        )
    }

    // MARK: - Auth Header

    /// Authorization header value for REST requests.
    var authorizationHeader: String {
        "Bearer \(token)"
    }

    // MARK: - Private Helpers

    private func makeURL(
        scheme: String,
        path: String = "",
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return false
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        return components.url != nil
    }
}
