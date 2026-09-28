import Foundation

public struct CompanySuggestion: Codable, Identifiable, Sendable {
    public var company: String
    public var domain: String
    public var id: String { domain }
}

public struct Session: Codable, Sendable, Equatable {
    public var token: String
    public var userId: String
    public init(token: String, userId: String) {
        self.token = token
        self.userId = userId
    }
}

public struct OutreachSettings: Codable, Sendable, Equatable {
    public var senderName: String
    public var subjectTemplate: String
    public var bodyTemplate: String
    public var maxContacts: Int
    public var sendIntervalSeconds: Int
    public var dailyLimit: Int
    public var recipientPreference: String
    public var sendingMode: String
    public var attachResume: Bool
    public var autoConfirmCompany: Bool?
    public var selectedTemplate: String?
    public var roleTemplates: [String: RoleTemplate]?

    public init(
        senderName: String = "",
        subjectTemplate: String = "Referral request — {{job_title}} at {{company}}",
        bodyTemplate: String = RoleTemplate.starter("general").body,
        maxContacts: Int = 5,
        sendIntervalSeconds: Int = 600,
        dailyLimit: Int = 10,
        recipientPreference: String = "relevant",
        sendingMode: String = "review",
        attachResume: Bool = false
    ) {
        self.senderName = senderName
        self.subjectTemplate = subjectTemplate
        self.bodyTemplate = bodyTemplate
        self.maxContacts = maxContacts
        self.sendIntervalSeconds = sendIntervalSeconds
        self.dailyLimit = dailyLimit
        self.recipientPreference = recipientPreference
        self.sendingMode = sendingMode
        self.attachResume = attachResume
    }

    public static let `default` = OutreachSettings()

    public var pacingSummary: String {
        let seconds = max(600, sendIntervalSeconds)
        let minutes = seconds % 60 == 0 ? "\(seconds / 60)" : String(format: "%.1f", Double(seconds) / 60)
        let hourlyMaximum = (3600 + seconds - 1) / seconds
        return "At least \(minutes) min apart · Up to \(hourlyMaximum)/hour"
    }
}

public struct Connections: Codable, Sendable, Equatable {
    public var gmailEmail: String?
    public var hunterConnected: Bool
    public init(gmailEmail: String? = nil, hunterConnected: Bool = false) {
        self.gmailEmail = gmailEmail
        self.hunterConnected = hunterConnected
    }
}

public struct ResumeDocument: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var filename: String
    public var byteCount: Int
    public var uploadedAt: String
    public init(id: String, filename: String, byteCount: Int, uploadedAt: String) {
        self.id = id
        self.filename = filename
        self.byteCount = byteCount
        self.uploadedAt = uploadedAt
    }
}

public struct ImportRequest: Codable, Sendable, Equatable {
    public var url: String
    public var sharedText: String?
    public var title: String?
    public var company: String?
    public var domain: String?
    public var description: String?
    public var clientRequestID: String?
    public init(url: String = "", sharedText: String? = nil, title: String? = nil,
                company: String? = nil, domain: String? = nil, description: String? = nil, clientRequestID: String? = nil) {
        self.url = url
        self.sharedText = sharedText
        self.title = title
        self.company = company
        self.domain = domain
        self.description = description
        self.clientRequestID = clientRequestID
    }
}

public struct Contact: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var email: String
    public var firstName: String
    public var lastName: String
    public var position: String
    public var department: String
    public var verification: String
    public var reason: String
    public init(id: String, email: String, firstName: String = "", lastName: String = "",
                position: String = "", department: String = "", verification: String = "unknown", reason: String = "") {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.position = position
        self.department = department
        self.verification = verification
        self.reason = reason
    }
}

public struct OutboundMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var contactId: String
    public var to: String
    public var subject: String
    public var body: String
    public var status: String
    public var gmailMessageId: String?
    public var error: String?
    public init(id: String, contactId: String, to: String, subject: String, body: String,
                status: String = "draft", gmailMessageId: String? = nil, error: String? = nil) {
        self.id = id
        self.contactId = contactId
        self.to = to
        self.subject = subject
        self.body = body
        self.status = status
        self.gmailMessageId = gmailMessageId
        self.error = error
    }
}

public struct Campaign: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var url: String
    public var title: String
    public var company: String
    public var domain: String
    public var description: String
    public var status: String
    public var createdAt: String
    public var contacts: [Contact]
    public var messages: [OutboundMessage]
    public var note: String?
    public var domainConfirmed: Bool?
    public var canBroadenSearch: Bool?
    public var canRetryLookup: Bool?
    public init(id: String, url: String, title: String = "", company: String = "", domain: String = "",
                description: String = "", status: String = "needs_details", createdAt: String,
                contacts: [Contact] = [], messages: [OutboundMessage] = [], note: String? = nil, domainConfirmed: Bool? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.company = company
        self.domain = domain
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.contacts = contacts
        self.messages = messages
        self.note = note
        self.domainConfirmed = domainConfirmed
    }
}

public struct AppSnapshot: Codable, Sendable, Equatable {
    public var settings: OutreachSettings
    public var connections: Connections
    public var resume: ResumeDocument?
    public var campaigns: [Campaign]
    public var queuePaused: Bool?
    public init(settings: OutreachSettings = .default, connections: Connections = Connections(),
                resume: ResumeDocument? = nil, campaigns: [Campaign] = [], queuePaused: Bool? = false) {
        self.settings = settings
        self.connections = connections
        self.resume = resume
        self.campaigns = campaigns
        self.queuePaused = queuePaused
    }

    /// Synthetic preview data. No credentials, connected accounts, or outgoing requests.
    public static let demo: AppSnapshot = {
        let contact = Contact(
            id: "demo-contact", email: "alex@example.com", firstName: "Alex", lastName: "Morgan",
            position: "Engineering Manager", department: "Engineering", verification: "demo",
            reason: "Synthetic example: a manager in the same department as the role."
        )
        let message = OutboundMessage(
            id: "demo-message", contactId: contact.id, to: contact.email,
            subject: "Referral request — iOS Engineer at Example Company",
            body: "Hi Alex,\n\nI’m interested in the iOS Engineer role at Example Company. Would you be open to a referral conversation?\n\nhttps://example.com/jobs/ios-engineer\n\nThank you,\nTaylor",
            status: "draft"
        )
        let campaign = Campaign(
            id: "demo-campaign", url: "https://example.com/jobs/ios-engineer", title: "iOS Engineer",
            company: "Example Company", domain: "example.com",
            description: "A fictional role used to preview the app. No job was researched and no email will be sent.",
            status: "ready", createdAt: "2026-09-14T12:00:00Z", contacts: [contact], messages: [message],
            note: "Demo only — fictional job and contact. Connect your accounts to create real outreach."
        )
        var settings = OutreachSettings.default
        settings.senderName = "Taylor"
        return AppSnapshot(settings: settings, campaigns: [campaign], queuePaused: true)
    }()
}
