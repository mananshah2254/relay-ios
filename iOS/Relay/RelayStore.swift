import AuthenticationServices
import Foundation
import OutreachCore
import SwiftUI
import UIKit

enum RelayTab: Hashable {
    case jobs, outreach, templates, settings
}

@MainActor
final class RelayStore: ObservableObject {
    @Published var selectedTab: RelayTab = .jobs
    @Published private(set) var snapshot: AppSnapshot?
    @Published var settings: OutreachSettings = .default
    @Published private(set) var isDemo = false
    @Published private(set) var isBusy = false
    @Published private(set) var activityTitle = "Updating Relay"
    @Published private(set) var activityDetail = "Saving your changes securely."
    @Published private(set) var pendingShares: [PendingShare] = []
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var connectedServiceURL: String = AppEnvironment.backendURL

    private let browser = GoogleConnectionBrowser()
    private var isRefreshing = false
    private var demoWorkspace: DemoWorkspace?
    var simulatedCount: Int { allMessages.filter { $0.status == "simulated" }.count }

    var isConnected: Bool { !isDemo && SharedCredentials.token != nil && !connectedServiceURL.isEmpty }
    var campaigns: [Campaign] { snapshot?.campaigns ?? [] }
    var resume: ResumeDocument? { snapshot?.resume }
    var gmailEmail: String? { snapshot?.connections.gmailEmail }
    var hunterConnected: Bool { snapshot?.connections.hunterConnected ?? false }
    var queuePaused: Bool { snapshot?.queuePaused ?? false }
    var hasUnsavedSettings: Bool {
        guard let saved = snapshot?.settings else { return false }
        return saved != settings
    }
    var activeCampaigns: [Campaign] {
        campaigns.filter { ["researching", "queued", "sending"].contains($0.status) }
    }
    var allMessages: [OutboundMessage] { campaigns.flatMap(\.messages) }
    var submittedCount: Int { allMessages.filter { $0.status == "submitted" }.count }
    var queuedCount: Int { allMessages.filter { ["queued", "sending"].contains($0.status) }.count }

    func campaign(id: String) -> Campaign? { campaigns.first { $0.id == id } }

    func activate() async {
        #if DEBUG
        // Offline visual QA. Never reads credentials or contacts a provider.
        if let preview = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--relay-preview=") }) {
            if !isDemo {
                enterDemo()
                if preview == "--relay-preview=templates" { selectedTab = .templates }
                if preview == "--relay-preview=activity" {
                    activityTitle = "Finding relevant people"
                    activityDetail = "Design preview only. No lookup or email is being sent."
                    isBusy = true
                }
            }
            return
        }
        #endif
        pendingShares = SharedInbox.load()
        guard isConnected else { return }
        await refresh(silently: true)
        await importPendingShares()
    }

    func pollIfNeeded() async {
        guard isConnected, !isBusy, !activeCampaigns.isEmpty else { return }
        await refresh(silently: true)
    }

    func enterDemo() {
        demoWorkspace = DemoWorkspace()
        isDemo = true
        snapshot = demoWorkspace?.snapshot
        settings = snapshot?.settings ?? .default
        notice = nil
        selectedTab = .jobs
    }

    func leaveDemo() async {
        demoWorkspace = nil
        isDemo = false
        snapshot = nil
        settings = .default
        await activate()
    }

    func joinRelay(inviteCode: String) async -> Bool {
        do {
            let url = try RelayInvitation.connectionURL(serviceURL: AppEnvironment.defaultBackendURL, code: inviteCode)
            let connected = await connectService(url: url)
            if !connected, errorMessage?.contains("private Relay setup link") == true {
                errorMessage = "That invite code was not accepted. Check that you copied the complete code, or ask your Relay administrator for a new one."
            }
            return connected
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func connectService(url rawURL: String) async -> Bool {
        let previousURL = AppEnvironment.backendURL
        let previousToken = SharedCredentials.token
        let succeeded = await perform {
            let normalized = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard var components = URLComponents(string: normalized), !normalized.isEmpty else {
                throw RelayError.message("Enter the address of your Relay service.")
            }
            let enrollmentKey = components.fragment
            components.fragment = nil
            guard let url = components.url else { throw RelayError.message("Enter a valid Relay service address.") }
            let unauthenticated = try APIClient(baseURL: url, enrollmentKey: enrollmentKey)
            let canonicalURL = url.absoluteString
            var token: String
            if canonicalURL == previousURL, let previousToken {
                token = previousToken
                do {
                    let authenticated = try APIClient(baseURL: url, token: token)
                    let state = try await authenticated.fetchState()
                    try SharedCredentials.saveToken(token)
                    AppEnvironment.backendURL = canonicalURL
                    self.connectedServiceURL = canonicalURL
                    self.isDemo = false
                    self.apply(state, replaceSettings: true)
                    self.notice = "Your Relay service is connected."
                    return
                } catch let error as APIClientError {
                    guard case let .server(status, _, _) = error, status == 401 else { throw error }
                }
            }
            let session = try await unauthenticated.createSession()
            token = session.token
            let authenticated = try APIClient(baseURL: url, token: token)
            let state = try await authenticated.fetchState()
            // Do not replace a working connection until the new origin and
            // session have both answered successfully.
            try SharedCredentials.saveToken(token)
            AppEnvironment.backendURL = canonicalURL
            self.connectedServiceURL = canonicalURL
            self.isDemo = false
            self.apply(state, replaceSettings: true)
            self.notice = "Your Relay service is connected."
        }
        if succeeded { await importPendingShares() }
        return succeeded
    }

    func refresh(silently: Bool = false) async {
        if isDemo { return }
        guard isConnected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await client().fetchState()
            apply(fresh, replaceSettings: !hasUnsavedSettings)
        } catch {
            if !silently { errorMessage = error.localizedDescription }
        }
    }

    func saveSettings() async -> Bool {
        if isDemo {
            settings.rememberActiveTemplate()
            let edited = settings
            return await performDemo { try $0.saveSettings(edited) }
        }
        return await perform(title: "Saving your preferences", detail: "Updating your template and outreach settings.") {
            self.settings.rememberActiveTemplate()
            try OutreachValidation.validate(settings: self.settings)
            let saved = try await self.client().updateSettings(self.settings)
            self.settings = saved
            await self.refresh()
            self.updateSharePreview()
            self.notice = "Your outreach preferences are saved."
        }
    }

    func searchCompanies(query: String) async throws -> [CompanySuggestion] {
        if isDemo { return demoWorkspace?.searchCompanies(query) ?? [] }
        return try await client().searchCompanies(query: query)
    }
    func diagnoseJob(id: String) async -> String {
        if isDemo { return "Practice mode uses fictional contacts at example.com. No Hunter request or credit was used. Live coverage and verification require a connected provider account." }
        do { return try await client().diagnoseJob(id: id) }
        catch { return error.localizedDescription }
    }

    func previewJob(url: String, sharedText: String? = nil) async -> JobPreview? {
        if isDemo {
            notice = "Practice mode does not fetch websites. Enter a sample role and company, such as Example Company."
            return nil
        }
        do { return try await client().previewJob(ImportRequest(url: url, sharedText: sharedText)) }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func discardSettingsChanges() {
        if let saved = snapshot?.settings { settings = saved }
    }

    func connectHunter(apiKey: String) async -> Bool {
        if isDemo { return await performDemo { $0.connectDirectory(true) } }
        return await perform(title: "Connecting Hunter", detail: "Checking your API key with Hunter. Your key stays private.") {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw RelayError.message("Paste your Hunter API key first.") }
            _ = try await self.client().connectHunter(apiKey: key)
            await self.refresh()
            guard self.hunterConnected else { throw RelayError.message("Hunter has not confirmed the connection yet. Refresh and try again.") }
            self.notice = "Hunter is connected."
        }
    }

    func disconnectHunter() async {
        if isDemo { _ = await performDemo { $0.connectDirectory(false) }; return }
        _ = await perform {
            try await self.client().disconnectHunter()
            await self.refresh()
        }
    }

    func connectGoogle() async {
        if isDemo { _ = await performDemo { $0.connectSender(true) }; return }
        _ = await perform(title: "Connecting Gmail", detail: "Complete Google’s sign-in window to connect your account.") {
            let url = try await self.client().startGoogleConnection()
            try await self.browser.open(url: url)
            await self.refresh()
            guard self.gmailEmail != nil else {
                throw RelayError.message("Gmail has not confirmed the connection. Refresh your account status or try connecting again.")
            }
            self.notice = "Gmail is connected."
        }
    }

    func disconnectGoogle() async {
        if isDemo { _ = await performDemo { $0.connectSender(false) }; return }
        _ = await perform {
            try await self.client().disconnectGoogle()
            await self.refresh()
        }
    }

    func uploadResume(url: URL) async -> Bool {
        return await perform(title: "Saving your résumé", detail: isDemo ? "Checking your PDF locally for practice. Nothing is uploaded." : "Checking and securely uploading your PDF.") {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 10 * 1_024 * 1_024 else {
                throw RelayError.message("Choose a PDF smaller than 10 MB.")
            }
            let data = try Data(contentsOf: url)
            try OutreachValidation.validateResume(filename: url.lastPathComponent, data: data)
            if self.isDemo {
                try self.editDemo { try $0.setResume(filename: url.lastPathComponent, data: data) }
                self.notice = "Practice attachment saved in memory. Nothing uploaded."
                return
            }
            _ = try await self.client().uploadResume(filename: url.lastPathComponent, data: data)
            await self.refresh()
            self.notice = "Your résumé is ready to attach."
        }
    }

    func deleteResume() async {
        if isDemo { _ = await performDemo { $0.removeResume() }; return }
        _ = await perform {
            try await self.client().deleteResume()
            await self.refresh()
        }
    }

    func addJob(
        url: String,
        title: String,
        company: String,
        clientRequestID: String,
        domain: String? = nil,
        description: String? = nil,
        sharedText: String? = nil
    ) async -> String? {
        var importedID: String?
        if isDemo {
            _ = await performDemo { demo in
                importedID = try demo.importJob(ImportRequest(url: url, sharedText: sharedText, title: title, company: company, domain: domain, description: description, clientRequestID: clientRequestID))
            }
            return importedID
        }
        _ = await perform(title: "Preparing your opportunity", detail: "Saving the job and checking available contacts. Hunter can take up to a minute.") {
            let campaign = try await self.client().importJob(ImportRequest(
                url: url,
                sharedText: sharedText,
                title: title,
                company: company,
                domain: domain,
                description: description,
                clientRequestID: clientRequestID
            ))
            importedID = campaign.id
            self.remember(campaign)
            await self.refresh()
        }
        return importedID
    }

    func updateJob(id: String, request: ImportRequest) async -> Bool {
        if isDemo { return await performDemo { try $0.updateJob(id: id, request: request) } }
        return await perform(title: "Updating the opportunity", detail: "Saving company details and checking the lookup result.") {
            let campaign = try await self.client().updateJob(id: id, request: request)
            self.remember(campaign)
            await self.refresh()
        }
    }

    func researchJob(id: String, confirmedDomain: String? = nil, broadenSearch: Bool? = nil, retryLookup: Bool? = nil) async {
        if isDemo { _ = await performDemo { try $0.research(id: id, confirmedDomain: confirmedDomain) }; return }
        _ = await perform(title: "Finding relevant people", detail: "Waiting for Hunter’s response. This can take up to a minute.") {
            let campaign = try await self.client().researchJob(id: id, confirmedDomain: confirmedDomain, broadenSearch: broadenSearch, retryLookup: retryLookup)
            self.remember(campaign)
            await self.refresh()
        }
    }

    func approveJob(id: String) async {
        if isDemo { _ = await performDemo { try $0.approve(id: id) }; return }
        _ = await perform(title: "Scheduling your introduction", detail: "Confirming the email queue. Gmail submission status appears in Outreach.") {
            let campaign = try await self.client().approveJob(id: id)
            self.remember(campaign)
            await self.refresh()
        }
    }

    func cancelJob(id: String) async {
        if isDemo { _ = await performDemo { try $0.cancel(id: id) }; return }
        _ = await perform {
            _ = try await self.client().cancelJob(id: id)
            await self.refresh()
        }
    }

    func setQueuePaused(_ paused: Bool) async {
        if isDemo { _ = await performDemo { $0.pause(paused) }; return }
        _ = await perform {
            if paused { _ = try await self.client().pauseQueue() }
            else { _ = try await self.client().resumeQueue() }
            await self.refresh()
        }
    }

    func importPendingShares() async {
        pendingShares = SharedInbox.load()
        guard isConnected, !isBusy, !pendingShares.isEmpty else { return }
        _ = await perform {
            for share in self.pendingShares {
                _ = try await self.client().importJob(ImportRequest(
                    url: share.url,
                    sharedText: share.sharedText,
                    title: share.title,
                    company: share.company,
                    domain: share.domain
                ))
                try SharedInbox.remove(id: share.id)
            }
            self.pendingShares = SharedInbox.load()
            await self.refresh()
        }
        pendingShares = SharedInbox.load()
    }

    func removePendingShare(id: String) {
        do {
            try SharedInbox.remove(id: id)
            pendingShares = SharedInbox.load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteAccount() async -> Bool {
        if isDemo {
            await leaveDemo()
            notice = "Practice data cleared. Your live account was not changed."
            return true
        }
        return await perform {
            try await self.client().deleteAccount()
            try SharedCredentials.saveToken(nil)
            try? SharedInbox.clear()
            AppEnvironment.reset()
            self.connectedServiceURL = ""
            self.snapshot = nil
            self.settings = .default
            self.pendingShares = []
            self.isDemo = false
            self.notice = "Your account and stored data have been deleted."
            self.selectedTab = .jobs
        }
    }

    private func client() throws -> APIClient {
        guard !isDemo else { throw RelayError.message("You’re exploring sample data. Exit the demo and connect your accounts to use live outreach.") }
        guard let url = URL(string: connectedServiceURL), let token = SharedCredentials.token else {
            throw RelayError.message("Connect your Relay service in Settings first.")
        }
        return try APIClient(baseURL: url, token: token)
    }

    func simulateNextDelivery() async {
        _ = await performDemo { try $0.simulateNextDelivery() }
    }

    private func editDemo(_ operation: (inout DemoWorkspace) throws -> Void) throws {
        guard isDemo, var demo = demoWorkspace else { throw RelayError.message("Open the practice workspace first.") }
        try operation(&demo)
        demoWorkspace = demo
        apply(demo.snapshot, replaceSettings: false)
    }

    private func performDemo(_ operation: (inout DemoWorkspace) throws -> Void) async -> Bool {
        await perform(title: "Updating practice workspace", detail: "Simulating the workflow locally. No provider request or real email.") {
            try self.editDemo(operation)
            self.notice = "Practice updated. No real email sent."
        }
    }

    private func remember(_ campaign: Campaign) {
        guard var state = snapshot else { return }
        if let index = state.campaigns.firstIndex(where: { $0.id == campaign.id }) { state.campaigns[index] = campaign }
        else { state.campaigns.insert(campaign, at: 0) }
        snapshot = state
    }

    private func perform(title: String = "Updating Relay", detail: String = "Waiting for confirmation from your service.", _ operation: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        activityTitle = title
        activityDetail = detail
        notice = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(_ state: AppSnapshot, replaceSettings: Bool) {
        snapshot = state
        if replaceSettings { settings = state.settings }
        updateSharePreview()
    }

    private func updateSharePreview() {
        guard let saved = snapshot?.settings, !isDemo else { return }
        let mode = saved.sendingMode == "automatic" ? "Automatic" : "Review first"
        AppEnvironment.settingsPreview = "\(mode) · Up to \(saved.maxContacts) contacts · \(saved.attachResume ? "Résumé attached" : "No attachment")"
    }
}

enum RelayError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

@MainActor
private final class GoogleConnectionBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func open(url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "relayreferrals") { callback, error in
                Task { @MainActor in
                    self.session = nil
                    if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if let error { continuation.resume(throwing: error); return }
                    guard let callback, callback.scheme == "relayreferrals", callback.host == "oauth", callback.path == "/complete" else {
                        continuation.resume(throwing: RelayError.message("Gmail returned an unexpected connection response."))
                        return
                    }
                    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    if let failure = items.first(where: { $0.name == "error" })?.value {
                        continuation.resume(throwing: RelayError.message("Gmail connection was not completed: \(failure)"))
                        return
                    }
                    continuation.resume()
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: RelayError.message("The Google sign-in window could not open. Try again."))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
