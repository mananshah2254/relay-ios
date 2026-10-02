import Foundation

/// A public, offline practice workspace. It has no transport or credential access.
/// Provider results and delivery are explicitly simulated using reserved domains.
public struct DemoWorkspace: Sendable {
    public private(set) var snapshot: AppSnapshot
    public private(set) var clock: Date
    private var nextAttempt: Date
    private var attempts: [Date] = []
    private var intervals: [String: Int] = [:]
    private var imports: [String: String] = [:]

    public init(now: Date = Date()) {
        clock = now
        nextAttempt = now
        snapshot = .demo
        snapshot.connections = Connections(gmailEmail: "taylor@example.com", hunterConnected: true)
        snapshot.queuePaused = false
        snapshot.campaigns[0].domainConfirmed = true
        snapshot.campaigns[0].note = "Practice workspace: fictional contacts and simulated delivery. No provider is contacted."
    }

    public static let companies: [CompanySuggestion] = [
        CompanySuggestion(company: "Example Company", domain: "example.com"),
        CompanySuggestion(company: "Example Labs", domain: "labs.example.org"),
        CompanySuggestion(company: "Example Support", domain: "support.example.net")
    ]

    public func searchCompanies(_ query: String) -> [CompanySuggestion] {
        Self.companies.filter { $0.company.localizedCaseInsensitiveContains(query) || $0.domain.localizedCaseInsensitiveContains(query) }
    }

    public mutating func saveSettings(_ settings: OutreachSettings) throws {
        try OutreachValidation.validate(settings: settings)
        snapshot.settings = settings
    }

    public mutating func connectSender(_ connected: Bool) {
        snapshot.connections.gmailEmail = connected ? "taylor@example.com" : nil
        if !connected { cancelAll() }
    }

    public mutating func connectDirectory(_ connected: Bool) {
        snapshot.connections.hunterConnected = connected
    }

    public mutating func setResume(filename: String, data: Data) throws {
        try OutreachValidation.validateResume(filename: filename, data: data)
        // Retain only metadata in memory, never the file contents.
        snapshot.resume = ResumeDocument(id: UUID().uuidString, filename: filename, byteCount: data.count, uploadedAt: clock.ISO8601Format())
    }

    public mutating func removeResume() { snapshot.resume = nil }
    public mutating func pause(_ paused: Bool) { snapshot.queuePaused = paused }

    @discardableResult public mutating func importJob(_ request: ImportRequest) throws -> String {
        if let key = request.clientRequestID, let id = imports[key] { return id }
        let title = (request.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let company = (request.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !company.isEmpty else { throw DemoError.message("Enter a job title and company for this practice opportunity.") }
        let url = request.url.isEmpty ? "" : try OutreachValidation.normalizeJobURL(request.url).absoluteString
        let domain = try OutreachValidation.normalizeCompanyDomain(request.domain ?? "")
        let id = UUID().uuidString
        snapshot.campaigns.insert(Campaign(id: id, url: url, title: title, company: company, domain: domain.isEmpty ? "example.com" : domain,
            description: request.description ?? "", createdAt: clock.ISO8601Format(),
            note: "Practice opportunity. Contacts are fictional and delivery is simulated.", domainConfirmed: !domain.isEmpty || snapshot.settings.autoConfirmCompany == true), at: 0)
        if let key = request.clientRequestID { imports[key] = id }
        if snapshot.campaigns[0].domainConfirmed == true, snapshot.connections.hunterConnected {
            try research(id: id, confirmedDomain: snapshot.campaigns[0].domain)
        }
        return id
    }

    public mutating func updateJob(id: String, request: ImportRequest) throws {
        let index = try index(id)
        guard snapshot.campaigns[index].messages.allSatisfy({ $0.status == "draft" || $0.status == "canceled" }) else {
            throw DemoError.message("Cancel pending practice outreach before editing this opportunity.")
        }
        let title = (request.title ?? snapshot.campaigns[index].title).trimmingCharacters(in: .whitespacesAndNewlines)
        let company = (request.company ?? snapshot.campaigns[index].company).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !company.isEmpty else { throw DemoError.message("Enter the job title and company.") }
        let domain = try OutreachValidation.normalizeCompanyDomain(request.domain ?? "")
        snapshot.campaigns[index].title = title
        snapshot.campaigns[index].company = company
        snapshot.campaigns[index].domain = domain.isEmpty ? "example.com" : domain
        snapshot.campaigns[index].url = request.url.isEmpty ? "" : try OutreachValidation.normalizeJobURL(request.url).absoluteString
        snapshot.campaigns[index].description = request.description ?? ""
        snapshot.campaigns[index].contacts = []
        snapshot.campaigns[index].messages = []
        snapshot.campaigns[index].status = "needs_details"
        snapshot.campaigns[index].domainConfirmed = false
    }

    public mutating func research(id: String, confirmedDomain: String?) throws {
        let index = try index(id)
        guard snapshot.connections.hunterConnected else { throw DemoError.message("Enable the sample directory in Settings → Connected accounts.") }
        guard snapshot.campaigns[index].messages.isEmpty else { return }
        guard let confirmedDomain, !confirmedDomain.isEmpty else {
            snapshot.campaigns[index].note = "The practice directory suggests example.com. Confirm it to generate fictional contacts."
            return
        }
        snapshot.campaigns[index].domain = try OutreachValidation.normalizeCompanyDomain(confirmedDomain)
        snapshot.campaigns[index].domainConfirmed = true
        var campaign = snapshot.campaigns[index]
        let settings = snapshot.settings
        try OutreachValidation.validate(settings: settings)
        let names = [("Alex", "Morgan"), ("Jordan", "Lee"), ("Sam", "Rivera"), ("Casey", "Taylor"), ("Robin", "Chen")]
        campaign.contacts = (0..<min(settings.maxContacts, names.count)).map { number in
            let name = names[number]
            return Contact(id: UUID().uuidString, email: "\(name.0.lowercased())@example.com", firstName: name.0, lastName: name.1,
                position: settings.recipientPreference == "recruiting" ? "Sample Recruiter" : "Sample Engineering Manager",
                department: "Sample team", verification: "sample", reason: "Fictional practice contact. This is not a verified employee of \(campaign.company).")
        }
        campaign.messages = try campaign.contacts.map { contact in
            let values = ["first_name": contact.firstName, "company": campaign.company, "job_title": campaign.title, "job_url": campaign.url, "sender_name": settings.senderName]
            return OutboundMessage(id: UUID().uuidString, contactId: contact.id, to: contact.email,
                subject: try OutreachValidation.render(template: settings.subjectTemplate, values: values),
                body: try OutreachValidation.render(template: settings.bodyTemplate, values: values))
        }
        campaign.status = "ready"
        campaign.note = "Simulated lookup: \(campaign.contacts.count) fictional contacts. No Hunter credits used. " +
            (settings.attachResume && snapshot.resume != nil ? "Practice attachment: \(snapshot.resume!.filename)." : "No attachment selected.")
        snapshot.campaigns[index] = campaign
        intervals[id] = settings.sendIntervalSeconds
        if settings.sendingMode == "automatic", snapshot.connections.gmailEmail != nil { try approve(id: id) }
    }

    public mutating func approve(id: String) throws {
        let index = try index(id)
        guard snapshot.connections.gmailEmail != nil else { throw DemoError.message("Enable the sample sender in Settings → Connected accounts.") }
        guard !snapshot.settings.senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DemoError.message("Save your sender name in Templates first.") }
        for message in snapshot.campaigns[index].messages.indices where snapshot.campaigns[index].messages[message].status == "draft" {
            snapshot.campaigns[index].messages[message].status = "queued"
        }
        updateStatus(index)
    }

    public mutating func cancel(id: String) throws {
        let index = try index(id)
        for message in snapshot.campaigns[index].messages.indices where ["draft", "queued"].contains(snapshot.campaigns[index].messages[message].status) {
            snapshot.campaigns[index].messages[message].status = "canceled"
        }
        updateStatus(index)
    }

    /// Advances a simulated clock, respecting pause, spacing, and the rolling daily cap.
    /// Nothing is sent or scheduled outside this in-memory workspace.
    public mutating func simulateNextDelivery() throws {
        guard snapshot.queuePaused != true else { throw DemoError.message("Resume the practice queue before simulating delivery.") }
        guard snapshot.connections.gmailEmail != nil else { throw DemoError.message("Enable the sample sender first.") }
        guard let index = snapshot.campaigns.indices.reversed().first(where: { snapshot.campaigns[$0].messages.contains { $0.status == "queued" } }),
              let message = snapshot.campaigns[index].messages.firstIndex(where: { $0.status == "queued" }) else {
            throw DemoError.message("Approve a practice draft first, then simulate its delivery here.")
        }
        let interval = max(600, snapshot.settings.sendIntervalSeconds, intervals[snapshot.campaigns[index].id] ?? 600)
        clock = max(clock, nextAttempt, attempts.last?.addingTimeInterval(TimeInterval(interval)) ?? clock)
        attempts.removeAll { clock.timeIntervalSince($0) >= 86400 }
        if attempts.count >= snapshot.settings.dailyLimit {
            clock = max(clock, attempts[attempts.count - snapshot.settings.dailyLimit].addingTimeInterval(86401))
            attempts.removeAll { clock.timeIntervalSince($0) >= 86400 }
        }
        snapshot.campaigns[index].messages[message].status = "simulated"
        snapshot.campaigns[index].messages[message].error = "Practice only: no email sent. Simulated time: \(clock.ISO8601Format())."
        attempts.append(clock)
        nextAttempt = clock.addingTimeInterval(TimeInterval(interval))
        updateStatus(index)
    }

    private func index(_ id: String) throws -> Int {
        guard let index = snapshot.campaigns.firstIndex(where: { $0.id == id }) else { throw DemoError.message("This practice opportunity is no longer available.") }
        return index
    }

    private mutating func cancelAll() {
        for id in snapshot.campaigns.map(\.id) { try? cancel(id: id) }
    }

    private mutating func updateStatus(_ index: Int) {
        let messages = snapshot.campaigns[index].messages
        if messages.contains(where: { $0.status == "queued" }) { snapshot.campaigns[index].status = "queued" }
        else if messages.contains(where: { $0.status == "draft" }) { snapshot.campaigns[index].status = "ready" }
        else { snapshot.campaigns[index].status = messages.contains(where: { $0.status == "simulated" }) ? "completed" : "canceled" }
    }
}

public enum DemoError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
