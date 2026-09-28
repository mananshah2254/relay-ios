import Foundation

public struct RoleTemplate: Codable, Sendable, Equatable {
    public var subject: String
    public var body: String
    public init(subject: String, body: String) { self.subject = subject; self.body = body }
    public static let roles = ["general", "software", "support", "ai"]
    public static func name(_ role: String) -> String {
        switch role {
        case "software": return "Software Engineer"
        case "support": return "Support Engineer"
        case "ai": return "AI Engineer"
        default: return "General"
        }
    }
    public static func starter(_ role: String) -> RoleTemplate {
        let interest: String
        switch role {
        case "software": interest = "I’m interested in building reliable software and solving practical engineering problems."
        case "support": interest = "I’m interested in troubleshooting technical issues and helping customers succeed."
        case "ai": interest = "I’m interested in building useful AI systems and evaluating their real-world impact."
        default: interest = "I’d welcome the chance to discuss how my background could contribute to your team."
        }
        return RoleTemplate(subject: "Referral request — {{job_title}} at {{company}}", body: "Hi {{first_name}},\n\nMy name is {{sender_name}}, and I’m interested in the {{job_title}} role at {{company}}. \(interest)\n\nIf you think my background could be a fit, would you be open to referring me or pointing me toward the right person? I’d be happy to share more about my experience.\n\nJob: {{job_url}}\n\nThank you for your time,\n{{sender_name}}")
    }
}

extension OutreachSettings {
    public mutating func rememberActiveTemplate() {
        var templates = roleTemplates ?? [:]
        templates[selectedTemplate ?? "general"] = RoleTemplate(subject: subjectTemplate, body: bodyTemplate)
        roleTemplates = templates
    }
    public mutating func selectTemplate(_ role: String) {
        guard RoleTemplate.roles.contains(role) else { return }
        rememberActiveTemplate()
        let template = roleTemplates?[role] ?? RoleTemplate.starter(role)
        selectedTemplate = role
        subjectTemplate = template.subject
        bodyTemplate = template.body
    }
}

public struct JobPreview: Codable, Sendable {
    public var title: String
    public var company: String
    public var description: String
}
