import Foundation

/// Represents a saved connection to a ppg serve instance.
struct ServerConnection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var token: String
    var ca: String?
    var isDefault: Bool

    init(name: String = "My Mac", host: String, port: Int = 7700, token: String, ca: String? = nil, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.token = token
        self.ca = ca
        self.isDefault = isDefault
    }

    private var usesTLS: Bool {
        ca != nil
    }

    var baseURL: URL? {
        makeURL(scheme: usesTLS ? "https" : "http")
    }

    var wsURL: URL? {
        makeURL(
            scheme: usesTLS ? "wss" : "ws",
            path: "/ws",
            queryItems: [URLQueryItem(name: "token", value: token)]
        )
    }

    var apiURL: URL? {
        baseURL?.appendingPathComponent("api")
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

        let port = params["port"].flatMap(Int.init) ?? 7700
        guard (1...65_535).contains(port) else { return nil }
        let ca = params["ca"].flatMap { Data(base64Encoded: $0) != nil ? $0 : nil }

        return ServerConnection(
            name: host == "0.0.0.0" ? "Local Mac" : host,
            host: host,
            port: port,
            token: token,
            ca: ca
        )
    }

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
