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

    var baseURL: URL {
        let scheme = ca != nil ? "https" : "http"
        return URL(string: "\(scheme)://\(host):\(port)")!
    }

    var wsURL: URL {
        let scheme = ca != nil ? "wss" : "ws"
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        return URL(string: "\(scheme)://\(host):\(port)/ws?token=\(encodedToken)")!
    }

    var apiURL: URL {
        baseURL.appendingPathComponent("api")
    }

    /// Parse a ppg serve QR code payload.
    /// Format: ppg://connect?host=<host>&port=<port>&token=<token>[&ca=<base64>]
    static func fromQRCode(_ payload: String) -> ServerConnection? {
        guard let components = URLComponents(string: payload),
              components.scheme == "ppg",
              components.host == "connect"
        else {
            return nil
        }

        let params = Dictionary(
            (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            },
            uniquingKeysWith: { _, last in last }
        )

        guard let host = params["host"], !host.isEmpty,
              let token = params["token"], !token.isEmpty
        else {
            return nil
        }

        let port = params["port"].flatMap(Int.init) ?? 7700
        let ca = params["ca"].flatMap { Data(base64Encoded: $0) != nil ? $0 : nil }

        return ServerConnection(
            name: host == "0.0.0.0" ? "Local Mac" : host,
            host: host,
            port: port,
            token: token,
            ca: ca
        )
    }
}
