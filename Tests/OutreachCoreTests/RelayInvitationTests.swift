import XCTest
@testable import OutreachCore

final class RelayInvitationTests: XCTestCase {
    func testCodeUsesConfiguredServiceAndTrimsWhitespace() throws {
        let code = String(repeating: "aB3_-", count: 8)
        let value = try RelayInvitation.connectionURL(serviceURL: "https://relay.example.com", code: " \n\(code)\n")
        let url = try XCTUnwrap(URLComponents(string: value))
        XCTAssertEqual(url.host, "relay.example.com")
        XCTAssertEqual(url.fragment, code)
        XCTAssertNil(url.query)
    }

    func testRejectsMalformedInvitationsAndUnsafeServices() {
        for code in ["", "short", String(repeating: "a", count: 129), String(repeating: "a", count: 40) + "\r\nHeader: yes", "https://untrusted.example/#" + String(repeating: "a", count: 43)] {
            XCTAssertThrowsError(try RelayInvitation.connectionURL(serviceURL: "https://relay.example.com", code: code))
        }
        for service in ["http://relay.example.com", "https://relay.example.com#key", "https://user:secret@relay.example.com"] {
            XCTAssertThrowsError(try RelayInvitation.connectionURL(serviceURL: service, code: String(repeating: "a", count: 43)))
        }
    }
}
