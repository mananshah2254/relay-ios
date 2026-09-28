import Foundation

public enum OutreachValidationError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case invalidSettings(String)
    case invalidTemplate(String)
    case invalidResume(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let message), .invalidSettings(let message),
             .invalidTemplate(let message), .invalidResume(let message): return message
        }
    }
}

public enum OutreachValidation {
    public static let maximumResumeBytes = 10 * 1024 * 1024
    public static let placeholderNames: Set<String> = ["first_name", "company", "job_title", "job_url", "sender_name"]

    public static func validate(settings: OutreachSettings) throws {
        guard (1...20).contains(settings.maxContacts) else {
            throw OutreachValidationError.invalidSettings("Choose between 1 and 20 contacts per job.")
        }
        guard (600...3600).contains(settings.sendIntervalSeconds) else {
            throw OutreachValidationError.invalidSettings("The send interval must be between 10 and 60 minutes.")
        }
        guard (1...100).contains(settings.dailyLimit) else {
            throw OutreachValidationError.invalidSettings("The daily limit must be between 1 and 100 emails.")
        }
        guard settings.senderName.utf16.count <= 120,
              !settings.senderName.contains(where: { $0.isNewline }), !hasUnsupportedControls(settings.senderName) else {
            throw OutreachValidationError.invalidSettings("Use a sender name of up to 120 characters on one line.")
        }
        guard ["relevant", "senior", "executive", "recruiting"].contains(settings.recipientPreference) else {
            throw OutreachValidationError.invalidSettings("Select a supported contact preference.")
        }
        guard ["review", "automatic"].contains(settings.sendingMode) else {
            throw OutreachValidationError.invalidSettings("Select review or automatic sending.")
        }
        guard !settings.subjectTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              settings.subjectTemplate.utf16.count <= 200,
              !settings.subjectTemplate.contains(where: { $0.isNewline }), !hasUnsupportedControls(settings.subjectTemplate) else {
            throw OutreachValidationError.invalidSettings("Add an email subject of up to 200 characters on one line.")
        }
        guard !settings.bodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              settings.bodyTemplate.utf16.count <= 20_000, !hasUnsupportedControls(settings.bodyTemplate) else {
            throw OutreachValidationError.invalidSettings("Add an email body of up to 20,000 characters.")
        }
        try validateTemplate(settings.subjectTemplate)
        try validateTemplate(settings.bodyTemplate)
    }

    public static func validateTemplate(_ template: String) throws {
        _ = try templateTokens(template)
    }

    /// Replaces only documented placeholders. Values are inserted as plain text, not recursively evaluated.
    public static func render(template: String, values: [String: String]) throws -> String {
        let tokens = try templateTokens(template)
        var rendered = template
        for token in tokens.reversed() {
            guard let value = values[token.name] else {
                throw OutreachValidationError.invalidTemplate("Missing a value for {{\(token.name)}}.")
            }
            rendered.replaceSubrange(token.range, with: value)
        }
        return rendered
    }

    private static func templateTokens(_ template: String) throws -> [(name: String, range: Range<String.Index>)] {
        var tokens: [(name: String, range: Range<String.Index>)] = []
        var cursor = template.startIndex
        while cursor < template.endIndex {
            let tail = template[cursor...]
            let opening = tail.range(of: "{{")
            let closing = tail.range(of: "}}")
            if let closing, opening == nil || closing.lowerBound < opening!.lowerBound {
                throw OutreachValidationError.invalidTemplate("A template placeholder has an unmatched closing brace.")
            }
            guard let opening else { break }
            guard let ending = template[opening.upperBound...].range(of: "}}") else {
                throw OutreachValidationError.invalidTemplate("Close each template placeholder with }}.")
            }
            let name = String(template[opening.upperBound..<ending.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard placeholderNames.contains(name) else {
                throw OutreachValidationError.invalidTemplate("Use only these placeholders: first_name, company, job_title, job_url, sender_name.")
            }
            tokens.append((name, opening.lowerBound..<ending.upperBound))
            cursor = ending.upperBound
        }
        return tokens
    }

    public static func validateResume(filename: String, data: Data) throws {
        guard !filename.isEmpty, filename.utf16.count <= 180,
              !filename.contains("/"), !filename.contains("\\"),
              !filename.contains(where: { $0.isNewline }), !hasUnsupportedControls(filename), filename.lowercased().hasSuffix(".pdf") else {
            throw OutreachValidationError.invalidResume("Choose a PDF résumé with a valid filename.")
        }
        guard !data.isEmpty, data.count <= maximumResumeBytes else {
            throw OutreachValidationError.invalidResume("The PDF must be nonempty and no larger than 10 MiB.")
        }
        guard data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil else {
            throw OutreachValidationError.invalidResume("This file does not have a PDF header.")
        }
    }

    /// Normalizes a shared job URL without accessing the network or claiming to have read the job.
    public static func normalizeJobURL(_ rawValue: String) throws -> URL {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf16.count <= 4096,
              !value.contains(where: { $0.isWhitespace }), !hasUnsupportedControls(value) else {
            throw OutreachValidationError.invalidURL("Paste a single job URL.")
        }
        if !value.contains("://") { value = "https://" + value }
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https", let rawHost = components.host,
              !rawHost.isEmpty, components.user == nil, components.password == nil,
              components.port == nil else {
            throw OutreachValidationError.invalidURL("Use a public HTTPS job URL without embedded credentials or a custom port.")
        }
        let host = rawHost.lowercased()
        guard isPublicHostname(host), !["localhost", "local", "internal"].contains(host.split(separator: ".").last.map(String.init) ?? "") else {
            throw OutreachValidationError.invalidURL("Use a public job website, not an IP address or local network URL.")
        }
        components.scheme = components.scheme?.lowercased()
        components.host = host
        components.fragment = nil
        if host == "linkedin.com" || host.hasSuffix(".linkedin.com") {
            let segments = components.path.split(separator: "/").map(String.init)
            var jobID: String?
            if segments.count == 3, segments[0] == "jobs", segments[1] == "view" {
                let candidate = segments[2].split(separator: "-").last.map(String.init) ?? ""
                if candidate.range(of: "^[0-9]+$", options: .regularExpression) != nil { jobID = candidate }
            }
            if jobID == nil {
                jobID = components.queryItems?.first(where: {
                    $0.name == "currentJobId" && ($0.value?.range(of: "^[0-9]+$", options: .regularExpression) != nil)
                })?.value
            }
            if let jobID {
                guard let canonical = URL(string: "https://www.linkedin.com/jobs/view/\(jobID)") else {
                    throw OutreachValidationError.invalidURL("This LinkedIn job URL could not be read.")
                }
                return canonical
            }
        }
        // Feed posts and URLs without structured job IDs remain importable for the details fallback.
        let trackingKeys = Set(["trk", "trackingid", "refid", "ref", "source", "sourceid"])
        components.queryItems = components.queryItems?.filter {
            !$0.name.lowercased().hasPrefix("utm_") && !trackingKeys.contains($0.name.lowercased())
        }.enumerated().sorted { lhs, rhs in
            lhs.element.name == rhs.element.name ? lhs.offset < rhs.offset : lhs.element.name < rhs.element.name
        }.map(\.element)
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        if components.path.count > 1, components.path.hasSuffix("/") { components.path.removeLast() }
        if components.path.isEmpty { components.path = "/" }
        guard let url = components.url else {
            throw OutreachValidationError.invalidURL("This job URL could not be read.")
        }
        return url
    }

    /// Accepts an employer domain or website and rejects email providers and hosted job-board domains.
    public static func normalizeCompanyDomain(_ input: String) throws -> String {
        guard input.utf16.count <= 253, !hasUnsupportedControls(input) else {
            throw OutreachValidationError.invalidSettings("Enter a company website domain of up to 253 characters.")
        }
        var domain = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.isEmpty { return "" }
        if domain.contains("://") {
            guard let components = URLComponents(string: domain),
                  ["http", "https"].contains(components.scheme ?? ""),
                  components.user == nil, components.password == nil, components.port == nil,
                  let host = components.host else {
                throw OutreachValidationError.invalidSettings("Enter the employer’s website domain.")
            }
            domain = host
        }
        if domain.hasPrefix("www.") { domain.removeFirst(4) }
        if domain.hasSuffix(".") { domain.removeLast() }
        guard isPublicHostname(domain), !["local", "localhost", "internal", "test", "invalid"].contains(domain.split(separator: ".").last.map(String.init) ?? "") else {
            throw OutreachValidationError.invalidSettings("Enter a public employer website domain, such as company.com.")
        }
        let providers = ["linkedin.com", "lnkd.in", "lever.co", "gmail.com", "yahoo.com", "outlook.com", "hotmail.com"]
        guard !domain.hasSuffix(".greenhouse.io"), !providers.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) else {
            throw OutreachValidationError.invalidSettings("Use the employer’s own website domain.")
        }
        return domain
    }

    private static func isPublicHostname(_ hostname: String) -> Bool {
        hostname.range(of: "^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", options: .regularExpression) != nil
    }

    private static func hasUnsupportedControls(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value < 32 && ![9, 10, 13].contains(scalar.value) || scalar.value == 127
        }
    }
}
