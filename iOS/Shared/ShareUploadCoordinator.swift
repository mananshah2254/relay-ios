import Foundation
import OutreachCore

final class ShareUploadCoordinator: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = ShareUploadCoordinator()
    static var sessionIdentifier: String { AppEnvironment.appGroupID + ".share-upload" }

    private let lock = NSLock()
    private var responseBodies: [Int: Data] = [:]
    private var completions: [Int: @Sendable (Bool) -> Void] = [:]
    private var systemCompletion: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sharedContainerIdentifier = AppEnvironment.appGroupID
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func reconnect(completion: @escaping () -> Void) {
        lock.lock()
        systemCompletion = completion
        lock.unlock()
        _ = session
    }

    func submit(_ pending: PendingShare, completion: @escaping @Sendable (Bool) -> Void) throws {
        guard pending.belongsToCurrentConnection,
              let token = SharedCredentials.token,
              let baseURL = URL(string: AppEnvironment.backendURL) else { throw UploadError.notConnected }
        // Reuse the same URL validation policy as the containing app.
        _ = try APIClient(baseURL: baseURL, token: token)
        let endpoint = baseURL.appendingPathComponent("v1/jobs")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(pending.id, forHTTPHeaderField: "Idempotency-Key")
        let payload = ImportRequest(
            url: pending.url,
            sharedText: pending.sharedText,
            title: pending.title,
            company: pending.company,
            domain: pending.domain
        )
        let file = try AppEnvironment.sharedDirectory(named: "ShareTransfers")
            .appendingPathComponent(pending.id).appendingPathExtension("json")
        try JSONEncoder().encode(payload).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = pending.id
        lock.lock()
        completions[task.taskIdentifier] = completion
        lock.unlock()
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let current = responseBodies[dataTask.taskIdentifier] ?? Data()
        // A campaign is small. Bound accumulation if the service misbehaves.
        if current.count + data.count <= 2_000_000 { responseBodies[dataTask.taskIdentifier] = current + data }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let data = responseBodies.removeValue(forKey: task.taskIdentifier)
        let completion = completions.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        let response = task.response as? HTTPURLResponse
        let code = response?.statusCode ?? 0
        let campaign = data.flatMap { try? JSONDecoder().decode(Campaign.self, from: $0) }
        // Background URLSession uploads may follow redirects without invoking the
        // redirect delegate. Never treat a response from another origin as an
        // accepted import; keep the local pending record for a safe retry.
        let originMatches: Bool
        if let configured = URL(string: AppEnvironment.backendURL), let actual = response?.url {
            let configuredPort = configured.port ?? (configured.scheme?.lowercased() == "https" ? 443 : 80)
            let actualPort = actual.port ?? (actual.scheme?.lowercased() == "https" ? 443 : 80)
            originMatches = configured.scheme?.lowercased() == actual.scheme?.lowercased()
                && configured.host?.lowercased() == actual.host?.lowercased()
                && configuredPort == actualPort
        } else {
            originMatches = false
        }
        let accepted = error == nil && (200..<300).contains(code) && originMatches && campaign != nil
        if let id = task.taskDescription, UUID(uuidString: id) != nil {
            if accepted { try? SharedInbox.remove(id: id) }
            if let file = try? AppEnvironment.sharedDirectory(named: "ShareTransfers")
                .appendingPathComponent(id).appendingPathExtension("json") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        completion?(accepted)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let completion = systemCompletion
        systemCompletion = nil
        lock.unlock()
        DispatchQueue.main.async { completion?() }
    }

    // This delegate protects default/ephemeral sessions. Apple's background
    // URLSession can follow redirects without calling this method; didComplete
    // therefore checks the final response origin before acknowledging an import.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    enum UploadError: LocalizedError {
        case notConnected
        var errorDescription: String? { "Open Relay and connect your service before importing this job." }
    }
}
