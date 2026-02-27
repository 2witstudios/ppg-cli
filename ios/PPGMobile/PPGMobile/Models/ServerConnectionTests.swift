import XCTest
@testable import PPGMobile

final class ServerConnectionTests: XCTestCase {

    // MARK: - fromQRCode

    func testValidQRCodeParsesCorrectly() {
        let qr = "ppg://connect?host=192.168.1.10&port=7700&token=abc123"
        let conn = ServerConnection.fromQRCode(qr)

        XCTAssertNotNil(conn)
        XCTAssertEqual(conn?.host, "192.168.1.10")
        XCTAssertEqual(conn?.port, 7700)
        XCTAssertEqual(conn?.token, "abc123")
        XCTAssertNil(conn?.ca)
    }

    func testValidQRCodeWithCAParsesCorrectly() {
        // "dGVzdA==" is base64 for "test"
        let qr = "ppg://connect?host=myhost&port=8080&token=secret&ca=dGVzdA=="
        let conn = ServerConnection.fromQRCode(qr)

        XCTAssertNotNil(conn)
        XCTAssertEqual(conn?.host, "myhost")
        XCTAssertEqual(conn?.port, 8080)
        XCTAssertEqual(conn?.token, "secret")
        XCTAssertEqual(conn?.ca, "dGVzdA==")
    }

    func testMissingHostReturnsNil() {
        let qr = "ppg://connect?port=7700&token=abc123"
        XCTAssertNil(ServerConnection.fromQRCode(qr))
    }

    func testEmptyHostReturnsNil() {
        let qr = "ppg://connect?host=&port=7700&token=abc123"
        XCTAssertNil(ServerConnection.fromQRCode(qr))
    }

    func testMissingTokenReturnsNil() {
        let qr = "ppg://connect?host=myhost&port=7700"
        XCTAssertNil(ServerConnection.fromQRCode(qr))
    }

    func testEmptyTokenReturnsNil() {
        let qr = "ppg://connect?host=myhost&port=7700&token="
        XCTAssertNil(ServerConnection.fromQRCode(qr))
    }

    func testMissingPortDefaultsTo7700() {
        let qr = "ppg://connect?host=myhost&token=abc123"
        let conn = ServerConnection.fromQRCode(qr)

        XCTAssertNotNil(conn)
        XCTAssertEqual(conn?.port, 7700)
    }

    func testInvalidPortReturnsNil() {
        XCTAssertNil(ServerConnection.fromQRCode("ppg://connect?host=myhost&port=0&token=abc123"))
        XCTAssertNil(ServerConnection.fromQRCode("ppg://connect?host=myhost&port=70000&token=abc123"))
    }

    func testInvalidHostReturnsNil() {
        let qr = "ppg://connect?host=my%20host&port=7700&token=abc123"
        XCTAssertNil(ServerConnection.fromQRCode(qr))
    }

    func testWrongSchemeReturnsNil() {
        let qr = "http://connect?host=myhost&port=7700&token=abc123"
        XCTAssertNil(ServerConnection.fromQRCode(qr))
    }

    func testWrongHostReturnsNil() {
        let qr = "ppg://pair?host=myhost&port=7700&token=abc123"
        XCTAssertNil(ServerConnection.fromQRCode(qr))
    }

    func testNonPPGStringReturnsNil() {
        XCTAssertNil(ServerConnection.fromQRCode("https://example.com"))
        XCTAssertNil(ServerConnection.fromQRCode("just some text"))
        XCTAssertNil(ServerConnection.fromQRCode(""))
    }

    func testDuplicateQueryParamsDoNotCrash() {
        let qr = "ppg://connect?host=myhost&token=first&token=second&port=7700"
        let conn = ServerConnection.fromQRCode(qr)

        XCTAssertNotNil(conn)
        // Last value wins per uniquingKeysWith
        XCTAssertEqual(conn?.token, "second")
    }

    func testInvalidBase64CAIsDiscarded() {
        let qr = "ppg://connect?host=myhost&port=7700&token=abc&ca=not-valid-base64!!!"
        let conn = ServerConnection.fromQRCode(qr)

        XCTAssertNotNil(conn)
        XCTAssertNil(conn?.ca)
    }

    func testLocalhostNameMapping() {
        let qr = "ppg://connect?host=0.0.0.0&port=7700&token=abc123"
        let conn = ServerConnection.fromQRCode(qr)

        XCTAssertEqual(conn?.name, "Local Mac")
    }

    func testNonLocalhostUsesHostAsName() {
        let qr = "ppg://connect?host=workstation.local&port=7700&token=abc123"
        let conn = ServerConnection.fromQRCode(qr)

        XCTAssertEqual(conn?.name, "workstation.local")
    }

    // MARK: - URL construction

    func testBaseURLUsesHTTPWithoutCA() {
        let conn = ServerConnection(host: "myhost", port: 7700, token: "abc")
        XCTAssertEqual(conn.baseURL?.absoluteString, "http://myhost:7700")
    }

    func testBaseURLUsesHTTPSWithCA() {
        let conn = ServerConnection(host: "myhost", port: 7700, token: "abc", ca: "dGVzdA==")
        XCTAssertEqual(conn.baseURL?.absoluteString, "https://myhost:7700")
    }

    func testWsURLUsesWSSWithCA() {
        let conn = ServerConnection(host: "myhost", port: 7700, token: "abc", ca: "dGVzdA==")
        XCTAssertEqual(conn.wsURL?.scheme, "wss")
    }

    func testWsURLPercentEncodesToken() {
        let conn = ServerConnection(host: "myhost", port: 7700, token: "abc+def&ghi=jkl")
        guard let url = conn.wsURL else {
            XCTFail("Expected wsURL to be generated")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let tokenValue = components?.queryItems?.first(where: { $0.name == "token" })?.value
        XCTAssertEqual(tokenValue, "abc+def&ghi=jkl")
        XCTAssertEqual(components?.queryItems?.count, 1)
    }

    func testInvalidHostDoesNotCrashURLBuilding() {
        let conn = ServerConnection(host: "bad host", port: 7700, token: "abc")
        XCTAssertNil(conn.baseURL)
        XCTAssertNil(conn.wsURL)
    }
}
