import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import OutreachCore

private actor StubTransport: HTTPTransport {
    private let data: Data
    private let status: Int
    private var requests: [URLRequest] = []

    init(json: String, status: Int = 200) {
        self.data = Data(json.utf8)
        self.status = status
    }
    init<T: Encodable>(value: T, status: Int = 200) throws {
        self.data = try JSONEncoder().encode(value)
        self.status = status
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
    func recordedRequests() -> [URLRequest] { requests }
}

final class APIClientTests: XCTestCase {
    private let server = URL(string: "https://api.example.com")!

    func testEnrollmentKeyOnlySentWhenCreatingSession() async throws {
        let key = String(repeating: "a", count: 43)
        let transport = StubTransport(json: "{\"token\":\"new-token\",\"userId\":\"user-1\"}")
        let client = try APIClient(baseURL: server, token: "existing", enrollmentKey: key, transport: transport)
        _ = try await client.createSession()
        _ = try? await client.fetchState()
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-Relay-Enrollment"), key)
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "X-Relay-Enrollment"))
        XCTAssertNil(requests[0].url?.fragment)
        XCTAssertThrowsError(try APIClient(baseURL: server, enrollmentKey: key + "\r\nInjected: yes"))
    }

    func testTransportRequiresHTTPSExceptExplicitLocalDevelopmentHosts() throws {
        for url in ["https://api.example.com", "http://localhost:8787", "http://127.0.0.1:8787"] {
            XCTAssertNoThrow(try APIClient(baseURL: URL(string: url)!))
        }
        for url in ["http://api.example.com", "http://localhost.example.com", "http://192.168.1.8:8787",
                    "https://user:password@api.example.com", "https://api.example.com?token=secret",
                    "https://api.example.com#fragment", "ftp://api.example.com"] {
            XCTAssertThrowsError(try APIClient(baseURL: URL(string: url)!))
        }
    }

    func testCreateSessionOmitsBearerTokenAndEncodesEmptyObject() async throws {
        let transport = StubTransport(json: "{\"token\":\"new-token\",\"userId\":\"user-1\"}")
        let client = try APIClient(baseURL: server, token: "old-token", transport: transport)
        let session = try await client.createSession()
        XCTAssertEqual(session.userId, "user-1")
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/session")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "{}")
    }

    func testStateFetchUsesBearerAndDecodesContract() async throws {
        let transport = try StubTransport(value: AppSnapshot.demo)
        let client = try APIClient(baseURL: server, token: "test-token", transport: transport)
        let state = try await client.fetchState()
        XCTAssertEqual(state, .demo)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(requests.first?.httpBody)
        XCTAssertEqual(requests.first?.httpMethod, "GET")
    }

    func testImportSendsCanonicalURLAndKeepsSuppliedDetails() async throws {
        let transport = try StubTransport(value: AppSnapshot.demo.campaigns[0])
        let client = try APIClient(baseURL: server, token: "test-token", transport: transport)
        _ = try await client.importJob(ImportRequest(
            url: "https://linkedin.com/jobs/view/ios-engineer-42/?trk=feed", sharedText: "Original shared text",
            title: "iOS Engineer", company: "Example Company"
        ))
        let requests = await transport.recordedRequests()
        let body = try JSONDecoder().decode(ImportRequest.self, from: XCTUnwrap(requests.first?.httpBody))
        XCTAssertEqual(body.url, "https://www.linkedin.com/jobs/view/42")
        XCTAssertEqual(body.sharedText, "Original shared text")
        XCTAssertEqual(body.company, "Example Company")
    }

    func testValidationFailureMakesNoNetworkRequest() async throws {
        let transport = StubTransport(json: "{}")
        let client = try APIClient(baseURL: server, transport: transport)
        var settings = OutreachSettings.default
        settings.maxContacts = 0
        do {
            _ = try await client.updateSettings(settings)
            XCTFail("Expected settings validation to fail")
        } catch is OutreachValidationError {}
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testManualImportKeepsItsRetryIdentifierAndAllowsNoLink() async throws {
        let transport = try StubTransport(value: AppSnapshot.demo.campaigns[0])
        let client = try APIClient(baseURL: server, transport: transport)
        let requestID = UUID().uuidString
        let input = ImportRequest(title: "Engineer", company: "Example", clientRequestID: requestID)
        _ = try await client.importJob(input)
        _ = try await client.importJob(input)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            let body = try JSONDecoder().decode(ImportRequest.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.url, "")
            XCTAssertEqual(body.clientRequestID, requestID)
        }
        do {
            _ = try await client.importJob(ImportRequest(title: "Engineer", company: "Example"))
            XCTFail("Manual imports must be safely retryable")
        } catch is OutreachValidationError {}
        let after = await transport.recordedRequests()
        XCTAssertEqual(after.count, 2)
    }

    func testCompanyConfirmationSendsTheWebsiteTheUserReviewed() async throws {
        let transport = try StubTransport(value: AppSnapshot.demo.campaigns[0])
        let client = try APIClient(baseURL: server, transport: transport)
        _ = try await client.researchJob(id: "job-1", confirmedDomain: "example.com")
        let requests = await transport.recordedRequests()
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: String]
        XCTAssertEqual(body?["confirmedDomain"], "example.com")
        XCTAssertEqual(requests.first?.url?.path, "/v1/jobs/job-1/research")
    }

    func testServerErrorsPreserveStatusCodeAndActionableMessage() async throws {
        let transport = StubTransport(json: "{\"error\":{\"code\":\"gmail_required\",\"message\":\"Connect Gmail before sending.\"}}", status: 409)
        let client = try APIClient(baseURL: server, transport: transport)
        do {
            _ = try await client.approveJob(id: "job-1")
            XCTFail("Expected structured error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .server(status: 409, code: "gmail_required", message: "Connect Gmail before sending."))
        }
    }

    func testUnreadableResponseAndHTMLErrorsDoNotEchoRawData() async throws {
        let successTransport = StubTransport(json: "<html>secret diagnostic details</html>")
        let client = try APIClient(baseURL: server, transport: successTransport)
        do {
            _ = try await client.fetchState()
            XCTFail("Expected unreadable response")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
        let errorTransport = StubTransport(json: "<html>secret diagnostic details</html>", status: 503)
        let failedClient = try APIClient(baseURL: server, transport: errorTransport)
        do {
            _ = try await failedClient.fetchState()
            XCTFail("Expected HTTP error")
        } catch let error as APIClientError {
            XCTAssertEqual(error, .server(status: 503, code: "http_503", message: "The server could not complete the request (HTTP 503)."))
        }
    }

    func testDeletesAcceptEmptyResponsesAndQueueActionsDecodeState() async throws {
        let deleteTransport = StubTransport(json: "", status: 204)
        let client = try APIClient(baseURL: server, token: "test-token", transport: deleteTransport)
        try await client.deleteAccount()
        let requests = await deleteTransport.recordedRequests()
        XCTAssertEqual(requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(requests.first?.url?.path, "/v1/account")

        let pauseTransport = StubTransport(json: "{\"queuePaused\":true}")
        let queueClient = try APIClient(baseURL: server, transport: pauseTransport)
        let paused = try await queueClient.pauseQueue()
        XCTAssertTrue(paused)
    }

    func testGoogleConnectionAcceptsOnlyGoogleHTTPSAuthorizationURLs() async throws {
        let transport = StubTransport(json: "{\"authorizationURL\":\"https://accounts.google.com/o/oauth2/v2/auth?state=test\"}")
        let client = try APIClient(baseURL: server, transport: transport)
        let url = try await client.startGoogleConnection()
        XCTAssertEqual(url.host, "accounts.google.com")
        for invalid in ["https://accounts.google.com.example.com/auth", "http://accounts.google.com/auth", "javascript:alert(1)"] {
            let invalidTransport = StubTransport(json: "{\"authorizationURL\":\"\(invalid)\"}")
            let invalidClient = try APIClient(baseURL: server, transport: invalidTransport)
            do {
                _ = try await invalidClient.startGoogleConnection()
                XCTFail("Expected invalid authorization URL to fail")
            } catch let error as APIClientError { XCTAssertEqual(error, .invalidResponse) }
        }
    }

    func testIdentifiersCannotEscapeEndpointPath() async throws {
        let transport = try StubTransport(value: AppSnapshot.demo.campaigns[0])
        let client = try APIClient(baseURL: server, transport: transport)
        _ = try await client.cancelJob(id: "job/other?unsafe=yes")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.example.com/v1/jobs/job%2Fother%3Funsafe%3Dyes/cancel")
        do {
            _ = try await client.cancelJob(id: "..")
            XCTFail("Expected traversal path to fail")
        } catch let error as APIClientError { XCTAssertEqual(error, .invalidEndpoint) }
    }
}
