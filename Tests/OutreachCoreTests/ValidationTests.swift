import Foundation
import XCTest
@testable import OutreachCore

final class ValidationTests: XCTestCase {
    func testConservativePacingDefaultsAndLabels() throws {
        var settings = OutreachSettings.default
        XCTAssertEqual(settings.sendIntervalSeconds, 600)
        XCTAssertEqual(settings.pacingSummary, "At least 10 min apart · Up to 6/hour")
        settings.sendIntervalSeconds = 599
        XCTAssertThrowsError(try OutreachValidation.validate(settings: settings))
        settings.sendIntervalSeconds = 900
        try OutreachValidation.validate(settings: settings)
        XCTAssertEqual(settings.pacingSummary, "At least 15 min apart · Up to 4/hour")
        settings.sendIntervalSeconds = 3600
        XCTAssertEqual(settings.pacingSummary, "At least 60 min apart · Up to 1/hour")
    }
    func testLinkedInJobURLsBecomeOneCanonicalImportKey() throws {
        let variants = [
            "https://www.linkedin.com/jobs/view/4281234567/?trackingId=abc&refId=x",
            "https://www.linkedin.com/jobs/view/senior-ios-engineer-at-example-4281234567/",
            "https://www.linkedin.com/jobs/search/?keywords=ios&currentJobId=4281234567",
            "linkedin.com/jobs/view/4281234567#details"
        ]
        for variant in variants {
            XCTAssertEqual(try OutreachValidation.normalizeJobURL(variant).absoluteString,
                           "https://www.linkedin.com/jobs/view/4281234567")
        }
    }

    func testOtherJobURLsPreserveFunctionalQueriesAndRemoveTracking() throws {
        let url = try OutreachValidation.normalizeJobURL("https://jobs.example.com/apply?gh_jid=42&utm_source=linkedin&team=mobile#description")
        XCTAssertEqual(url.absoluteString, "https://jobs.example.com/apply?gh_jid=42&team=mobile")
    }

    func testURLValidationRejectsCredentialsLocalNetworksAndMultipleURLs() {
        let invalid = [
            "https://person:password@example.com/jobs/42", "https://example.com:8787/jobs/42",
            "https://127.0.0.1/job", "https://10.0.0.1/job", "https://[::1]/job",
            "https://localhost/job", "https://intranet/job", "https://jobs.local/job",
            "https://jobs.internal/job", "https://jobs.localhost/job",
            "javascript:alert(1)", "https://example.com/job/1 https://example.com/job/2", ""
        ]
        for value in invalid { XCTAssertThrowsError(try OutreachValidation.normalizeJobURL(value), value) }
    }

    func testLinkedInFeedSharesRemainImportableForDetailsFallback() throws {
        XCTAssertEqual(try OutreachValidation.normalizeJobURL("https://www.linkedin.com/posts/example_hiring-123?utm_source=share").absoluteString,
                       "https://www.linkedin.com/posts/example_hiring-123")
        XCTAssertEqual(try OutreachValidation.normalizeJobURL("https://www.linkedin.com/jobs/search/?currentJobId=unknown").absoluteString,
                       "https://www.linkedin.com/jobs/search?currentJobId=unknown")
    }

    func testCompanyDomainsNormalizeAndRejectJobBoardsEmailProvidersAndLocalTargets() throws {
        XCTAssertEqual(try OutreachValidation.normalizeCompanyDomain(" https://WWW.Example.com/careers "), "example.com")
        XCTAssertEqual(try OutreachValidation.normalizeCompanyDomain("Example.com."), "example.com")
        XCTAssertEqual(try OutreachValidation.normalizeCompanyDomain(""), "")
        for value in ["gmail.com", "jobs.lever.co", "boards.greenhouse.io", "linkedin.com", "company.local", "127.0.0.1", "intranet", "https://example.com:8787"] {
            XCTAssertThrowsError(try OutreachValidation.normalizeCompanyDomain(value), value)
        }
    }

    func testLookalikeLinkedInDomainIsNeverRewrittenAsLinkedIn() throws {
        let url = try OutreachValidation.normalizeJobURL("https://linkedin.com.example.com/jobs/view/42")
        XCTAssertEqual(url.host, "linkedin.com.example.com")
    }

    func testTemplateValidationDetectsUnknownAndMalformedTokens() throws {
        try OutreachValidation.validateTemplate("Hi {{ first_name }}, about {{job_title}} at {{company}}.")
        for template in ["Hi {{name}}", "Hi {{first_name}", "Hi first_name}}", "{{{{company}}}}"] {
            XCTAssertThrowsError(try OutreachValidation.validateTemplate(template), template)
        }
        try OutreachValidation.validateTemplate("{{ company\n}}")
    }

    func testTemplateRenderingHandlesUnicodeAndDoesNotEvaluateReplacementText() throws {
        let template = "👋 {{first_name}} — {{job_title}} at {{company}}. {{first_name}}!"
        let result = try OutreachValidation.render(template: template, values: [
            "first_name": "Zoë", "job_title": "iOS Engineer", "company": "{{sender_name}}"
        ])
        XCTAssertEqual(result, "👋 Zoë — iOS Engineer at {{sender_name}}. Zoë!")
        XCTAssertThrowsError(try OutreachValidation.render(template: "{{company}}", values: [:]))
    }

    func testSettingsRejectUnsafeHeadersAndInvalidLimits() throws {
        try OutreachValidation.validate(settings: .default)
        var settings = OutreachSettings.default
        settings.subjectTemplate = "A role\r\nBcc: other@example.com"
        XCTAssertThrowsError(try OutreachValidation.validate(settings: settings))
        settings = .default
        settings.maxContacts = 0
        XCTAssertThrowsError(try OutreachValidation.validate(settings: settings))
        settings.maxContacts = 21
        XCTAssertThrowsError(try OutreachValidation.validate(settings: settings))
        settings = .default
        settings.sendIntervalSeconds = 4
        XCTAssertThrowsError(try OutreachValidation.validate(settings: settings))
        settings = .default
        settings.dailyLimit = 101
        XCTAssertThrowsError(try OutreachValidation.validate(settings: settings))
        settings = .default
        settings.sendingMode = "unrecognized"
        XCTAssertThrowsError(try OutreachValidation.validate(settings: settings))
    }

    func testResumeSanityCheckRejectsRenamedImagesPathNamesAndOversizeFiles() throws {
        let header = Data("%PDF-1.7\n".utf8)
        try OutreachValidation.validateResume(filename: "Résumé.PDF", data: header)
        XCTAssertThrowsError(try OutreachValidation.validateResume(filename: "resume.pdf", data: Data("PNG".utf8)))
        XCTAssertThrowsError(try OutreachValidation.validateResume(filename: "../resume.pdf", data: header))
        XCTAssertThrowsError(try OutreachValidation.validateResume(filename: "resume.pdf\r\nX: injected", data: header))
        XCTAssertThrowsError(try OutreachValidation.validateResume(filename: "resume.pdf", data: Data()))
        var oversized = header
        oversized.append(Data(repeating: 0, count: OutreachValidation.maximumResumeBytes))
        XCTAssertThrowsError(try OutreachValidation.validateResume(filename: "resume.pdf", data: oversized))
    }

    func testDemoFixtureIsSyntheticDisconnectedAndOnlyContainsDrafts() throws {
        let snapshot = AppSnapshot.demo
        XCTAssertFalse(snapshot.connections.hunterConnected)
        XCTAssertNil(snapshot.connections.gmailEmail)
        XCTAssertNil(snapshot.resume)
        XCTAssertEqual(snapshot.queuePaused, true)
        XCTAssertTrue(snapshot.campaigns.flatMap(\.contacts).allSatisfy { $0.email.hasSuffix("@example.com") })
        XCTAssertTrue(snapshot.campaigns.flatMap(\.messages).allSatisfy { $0.status == "draft" && $0.gmailMessageId == nil })
        let roundTrip = try JSONDecoder().decode(AppSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(snapshot, roundTrip)
    }
}
