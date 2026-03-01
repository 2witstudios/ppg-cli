import Testing
import Foundation
@testable import PPGMobile

@Suite("ServerConnection")
struct ServerConnectionTests {

    static func make(
        host: String = "192.168.1.5",
        port: Int = 7700,
        ca: String? = nil,
        token: String = "abc123"
    ) -> ServerConnection {
        ServerConnection(id: UUID(), host: host, port: port, caCertificate: ca, token: token)
    }

    // MARK: - URL Builders

    @Test("baseURL uses http when no CA certificate")
    func baseURLWithoutCA() {
        let conn = Self.make()
        #expect(conn.baseURL?.absoluteString == "http://192.168.1.5:7700")
    }

    @Test("baseURL uses https when CA certificate is present")
    func baseURLWithCA() {
        let conn = Self.make(ca: "FAKECERT")
        #expect(conn.baseURL?.absoluteString == "https://192.168.1.5:7700")
    }

    @Test("restURL appends path to base URL")
    func restURLAppendsPath() {
        let conn = Self.make()
        let url = conn.restURL(for: "/api/status")
        #expect(url?.absoluteString == "http://192.168.1.5:7700/api/status")
    }

    @Test("webSocketURL uses ws scheme without CA")
    func webSocketWithoutCA() {
        let conn = Self.make()
        let url = conn.webSocketURL
        #expect(url?.scheme == "ws")
        #expect(url?.host == "192.168.1.5")
        #expect(url?.port == 7700)
        #expect(url?.path == "/ws")
        #expect(url?.absoluteString.contains("token=abc123") == true)
    }

    @Test("webSocketURL uses wss scheme with CA")
    func webSocketWithCA() {
        let conn = Self.make(ca: "FAKECERT")
        #expect(conn.webSocketURL?.scheme == "wss")
    }

    // MARK: - QR Code Round-trip

    @Test("qrCodeString produces parseable ppg:// URL")
    func qrCodeStringFormat() {
        let conn = Self.make()
        let qr = conn.qrCodeString
        #expect(qr.hasPrefix("ppg://connect?"))
        #expect(qr.contains("host=192.168.1.5"))
        #expect(qr.contains("port=7700"))
        #expect(qr.contains("token=abc123"))
    }

    @Test("fromQRCode round-trips with qrCodeString")
    func qrRoundTrip() {
        let original = Self.make()
        let qr = original.qrCodeString
        let parsed = ServerConnection.fromQRCode(qr)

        #expect(parsed?.host == original.host)
        #expect(parsed?.port == original.port)
        #expect(parsed?.token == original.token)
        #expect(parsed?.caCertificate == original.caCertificate)
    }

    @Test("fromQRCode round-trips with CA certificate")
    func qrRoundTripWithCA() {
        let original = Self.make(ca: "BASE64CERTDATA+/=")
        let qr = original.qrCodeString
        let parsed = ServerConnection.fromQRCode(qr)

        #expect(parsed?.host == original.host)
        #expect(parsed?.caCertificate == original.caCertificate)
    }

    @Test("fromQRCode round-trips with special characters in token")
    func qrRoundTripSpecialChars() {
        let original = Self.make(token: "tok+en/with=special&chars")
        let qr = original.qrCodeString
        let parsed = ServerConnection.fromQRCode(qr)

        #expect(parsed?.token == original.token)
    }

    // MARK: - QR Parsing Edge Cases

    @Test("fromQRCode returns nil for non-ppg scheme")
    func rejectsWrongScheme() {
        #expect(ServerConnection.fromQRCode("https://connect?host=x&port=1&token=t") == nil)
    }

    @Test("fromQRCode returns nil for wrong host")
    func rejectsWrongHost() {
        #expect(ServerConnection.fromQRCode("ppg://wrong?host=x&port=1&token=t") == nil)
    }

    @Test("fromQRCode returns nil when required fields are missing")
    func rejectsMissingFields() {
        #expect(ServerConnection.fromQRCode("ppg://connect?host=x&port=1") == nil)  // no token
        #expect(ServerConnection.fromQRCode("ppg://connect?host=x&token=t") == nil)  // no port
        #expect(ServerConnection.fromQRCode("ppg://connect?port=1&token=t") == nil)  // no host
    }

    @Test("fromQRCode returns nil for non-numeric port")
    func rejectsNonNumericPort() {
        #expect(ServerConnection.fromQRCode("ppg://connect?host=x&port=abc&token=t") == nil)
    }

    @Test("fromQRCode returns nil for empty string")
    func rejectsEmptyString() {
        #expect(ServerConnection.fromQRCode("") == nil)
    }

    @Test("fromQRCode returns nil for garbage input")
    func rejectsGarbage() {
        #expect(ServerConnection.fromQRCode("not a url at all") == nil)
    }

    // MARK: - Auth Header

    @Test("authorizationHeader has Bearer prefix")
    func authHeader() {
        let conn = Self.make(token: "my-secret-token")
        #expect(conn.authorizationHeader == "Bearer my-secret-token")
    }
}
