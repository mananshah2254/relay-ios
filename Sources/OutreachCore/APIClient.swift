import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: RejectRedirectsDelegate(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        return (data, response)
    }
}

private final class RejectRedirectsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // The configured API origin is authoritative; a redirect must never carry credentials elsewhere.
        completionHandler(nil)
    }
}

public enum APIClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidBaseURL
    case invalidEndpoint
    case invalidResponse
    case server(status: Int, code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "Use an HTTPS server URL. HTTP is supported only for localhost or 127.0.0.1 development."
        case .invalidEndpoint: return "The request could not be created."
        case .invalidResponse: return "The server returned an unreadable response."
        case .server(_, _, let message): return message
        }
    }
}

public struct APIClient: Sendable {
    public let baseURL: URL
    public let token: String?
    private let enrollmentKey: String?
    private let transport: any HTTPTransport

    public init(baseURL: URL, token: String? = nil, enrollmentKey: String? = nil, transport: any HTTPTransport = URLSessionTransport()) throws {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.scheme?.lowercased() == "https" ||
                (components.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1"].contains(host)) else {
            throw APIClientError.invalidBaseURL
        }
        guard token?.contains(where: { $0.isNewline }) != true else { throw APIClientError.invalidBaseURL }
        if let enrollmentKey {
            guard (32...128).contains(enrollmentKey.count), enrollmentKey.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }) else {
                throw APIClientError.invalidBaseURL
            }
        }
        self.baseURL = baseURL
        self.token = token
        self.enrollmentKey = enrollmentKey
        self.transport = transport
    }

    public func createSession() async throws -> Session {
        try await request("POST", ["session"], body: EmptyBody(), authenticated: false)
    }

    public func fetchState() async throws -> AppSnapshot {
        try await request("GET", ["state"])
    }

    public func updateSettings(_ settings: OutreachSettings) async throws -> OutreachSettings {
        try OutreachValidation.validate(settings: settings)
        return try await request("PUT", ["settings"], body: settings)
    }

    @discardableResult
    public func connectHunter(apiKey: String) async throws -> Bool {
        let response: ConnectedResponse = try await request("POST", ["hunter"], body: HunterRequest(apiKey: apiKey))
        return response.connected
    }

    public func disconnectHunter() async throws { try await requestVoid("DELETE", ["hunter"]) }

    public func startGoogleConnection() async throws -> URL {
        let response: GoogleConnectionResponse = try await request("POST", ["google", "connect"], body: EmptyBody())
        guard let url = URL(string: response.authorizationURL),
              url.scheme?.lowercased() == "https", url.host?.lowercased() == "accounts.google.com",
              url.user == nil, url.password == nil else { throw APIClientError.invalidResponse }
        return url
    }

    public func disconnectGoogle() async throws { try await requestVoid("DELETE", ["google"]) }

    public func uploadResume(filename: String, data: Data) async throws -> ResumeDocument {
        try OutreachValidation.validateResume(filename: filename, data: data)
        return try await request("POST", ["resume"], body: ResumeRequest(filename: filename, dataBase64: data.base64EncodedString()))
    }

    public func deleteResume() async throws { try await requestVoid("DELETE", ["resume"]) }

    public func searchCompanies(query: String) async throws -> [CompanySuggestion] {
        try await request("POST", ["companies", "search"], body: ["query": query])
    }
    public func diagnoseJob(id: String) async throws -> String {
        let result: [String: String] = try await request("POST", ["jobs", id, "diagnose"], body: [String: String]())
        return result["message"] ?? "No diagnostic result."
    }

    public func previewJob(_ imported: ImportRequest) async throws -> JobPreview {
        var normalized = imported
        normalized.url = try normalizeOptionalJobURL(imported)
        return try await request("POST", ["jobs", "preview"], body: normalized)
    }

    public func importJob(_ imported: ImportRequest) async throws -> Campaign {
        var normalized = imported
        normalized.url = try normalizeOptionalJobURL(imported)
        if normalized.url.isEmpty, UUID(uuidString: imported.clientRequestID ?? "") == nil {
            throw OutreachValidationError.invalidSettings("A manual job needs a stable import identifier.")
        }
        if let domain = imported.domain { normalized.domain = try OutreachValidation.normalizeCompanyDomain(domain) }
        return try await request("POST", ["jobs"], body: normalized)
    }

    public func updateJob(id: String, request imported: ImportRequest) async throws -> Campaign {
        var normalized = imported
        normalized.url = try normalizeOptionalJobURL(imported)
        if let domain = imported.domain { normalized.domain = try OutreachValidation.normalizeCompanyDomain(domain) }
        return try await request("PATCH", ["jobs", id], body: normalized)
    }

    public func researchJob(id: String, confirmedDomain: String? = nil, broadenSearch: Bool? = nil, retryLookup: Bool? = nil) async throws -> Campaign {
        try await request("POST", ["jobs", id, "research"], body: ResearchRequest(confirmedDomain: confirmedDomain, broadenSearch: broadenSearch, retryLookup: retryLookup))
    }

    private func normalizeOptionalJobURL(_ imported: ImportRequest) throws -> String {
        if imported.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !(imported.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !(imported.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OutreachValidationError.invalidSettings("Enter the job title and company.")
            }
            return ""
        }
        return try OutreachValidation.normalizeJobURL(imported.url).absoluteString
    }

    public func approveJob(id: String) async throws -> Campaign {
        try await request("POST", ["jobs", id, "approve"], body: EmptyBody())
    }

    public func cancelJob(id: String) async throws -> Campaign {
        try await request("POST", ["jobs", id, "cancel"], body: EmptyBody())
    }

    public func deleteAccount() async throws { try await requestVoid("DELETE", ["account"]) }

    @discardableResult
    public func pauseQueue() async throws -> Bool {
        let response: QueueResponse = try await request("POST", ["queue", "pause"], body: EmptyBody())
        return response.queuePaused
    }

    @discardableResult
    public func resumeQueue() async throws -> Bool {
        let response: QueueResponse = try await request("POST", ["queue", "resume"], body: EmptyBody())
        return response.queuePaused
    }

    private func request<Response: Decodable>(_ method: String, _ path: [String]) async throws -> Response {
        let data = try await perform(method, path, body: nil)
        return try decode(data)
    }

    private func request<Response: Decodable, Body: Encodable>(
        _ method: String, _ path: [String], body: Body, authenticated: Bool = true
    ) async throws -> Response {
        let encoded = try JSONEncoder().encode(body)
        let data = try await perform(method, path, body: encoded, authenticated: authenticated)
        return try decode(data)
    }

    private func requestVoid(_ method: String, _ path: [String]) async throws {
        _ = try await perform(method, path, body: nil)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw APIClientError.invalidResponse }
    }

    private func perform(_ method: String, _ path: [String], body: Data?, authenticated: Bool = true) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidEndpoint
        }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = try (["v1"] + path).map { value -> String in
            guard !value.isEmpty, value != ".", value != "..", let value = value.addingPercentEncoding(withAllowedCharacters: safe) else {
                throw APIClientError.invalidEndpoint
            }
            return value
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + ([basePath].filter { !$0.isEmpty } + encoded).joined(separator: "/")
        guard let url = components.url else { throw APIClientError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if !authenticated, path == ["session"], let enrollmentKey {
            request.setValue(enrollmentKey, forHTTPHeaderField: "X-Relay-Enrollment")
        }
        let (data, response) = try await transport.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw APIClientError.server(
                status: response.statusCode,
                code: error?.error.code ?? "http_\(response.statusCode)",
                message: error?.error.message ?? "The server could not complete the request (HTTP \(response.statusCode))."
            )
        }
        return data
    }
}

private struct EmptyBody: Encodable {}
private struct ResearchRequest: Encodable { let confirmedDomain: String?; let broadenSearch: Bool?; let retryLookup: Bool? }
private struct HunterRequest: Encodable { let apiKey: String }
private struct ResumeRequest: Encodable { let filename: String; let dataBase64: String }
private struct ConnectedResponse: Decodable { let connected: Bool }
private struct GoogleConnectionResponse: Decodable { let authorizationURL: String }
private struct QueueResponse: Decodable { let queuePaused: Bool }
private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable { let code: String; let message: String }
    let error: Detail
}
