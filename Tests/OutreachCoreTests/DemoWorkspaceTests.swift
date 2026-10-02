import XCTest
@testable import OutreachCore

final class DemoWorkspaceTests: XCTestCase {
    func testPracticeDraftApprovalAndDeliveryAreExplicitlySimulated() throws {
        var demo = DemoWorkspace(now: Date(timeIntervalSince1970: 1_800_000_000))
        let id = demo.snapshot.campaigns[0].id
        XCTAssertNil(demo.snapshot.campaigns[0].messages[0].gmailMessageId)
        try demo.approve(id: id)
        XCTAssertEqual(demo.snapshot.campaigns[0].messages[0].status, "queued")
        demo.pause(true)
        XCTAssertThrowsError(try demo.simulateNextDelivery())
        XCTAssertEqual(demo.snapshot.campaigns[0].messages[0].status, "queued")
        demo.pause(false)
        try demo.simulateNextDelivery()
        let message = demo.snapshot.campaigns[0].messages[0]
        XCTAssertEqual(message.status, "simulated")
        XCTAssertNil(message.gmailMessageId)
        XCTAssertTrue(message.error?.contains("no email sent") == true)
    }

    func testCompanySearchAndContactsCannotFabricateRealEmployeeAddresses() throws {
        var demo = DemoWorkspace()
        XCTAssertEqual(demo.searchCompanies("Example").count, 3)
        XCTAssertTrue(demo.searchCompanies("Amazon").isEmpty)
        let id = try demo.importJob(ImportRequest(title: "Engineer", company: "Amazon", domain: "amazon.com", clientRequestID: "same"))
        let campaign = try XCTUnwrap(demo.snapshot.campaigns.first { $0.id == id })
        XCTAssertEqual(campaign.contacts.count, 5)
        XCTAssertTrue(campaign.contacts.allSatisfy { $0.email.hasSuffix("@example.com") && $0.verification == "sample" })
        XCTAssertTrue(campaign.contacts.allSatisfy { $0.reason.contains("not a verified employee") })
        XCTAssertEqual(try demo.importJob(ImportRequest(clientRequestID: "same")), id)
        XCTAssertEqual(demo.snapshot.campaigns.count, 2)
    }

    func testAutomaticApprovalStillRequiresConfirmedCompanyAndConnectedSender() throws {
        var demo = DemoWorkspace()
        var settings = demo.snapshot.settings
        settings.sendingMode = "automatic"
        try demo.saveSettings(settings)
        let id = try demo.importJob(ImportRequest(title: "Engineer", company: "Example Company"))
        XCTAssertEqual(demo.snapshot.campaigns[0].status, "needs_details")
        try demo.research(id: id, confirmedDomain: "example.com")
        XCTAssertEqual(demo.snapshot.campaigns[0].status, "queued")
        XCTAssertTrue(demo.snapshot.campaigns[0].messages.allSatisfy { $0.status == "queued" })
        demo.connectSender(false)
        XCTAssertTrue(demo.snapshot.campaigns.flatMap(\.messages).allSatisfy { $0.status == "canceled" })
        XCTAssertThrowsError(try demo.approve(id: id))
    }

    func testSettingsChangeDoesNotRewriteExistingDrafts() throws {
        var demo = DemoWorkspace()
        let previous = demo.snapshot.campaigns[0].messages[0]
        var settings = demo.snapshot.settings
        settings.subjectTemplate = "Hello {{first_name}} about {{job_title}}"
        settings.maxContacts = 2
        try demo.saveSettings(settings)
        _ = try demo.importJob(ImportRequest(title: "Support Engineer", company: "Example Support", domain: "support.example.net"))
        XCTAssertEqual(demo.snapshot.campaigns[0].messages.count, 2)
        XCTAssertEqual(demo.snapshot.campaigns[0].messages[0].subject, "Hello Alex about Support Engineer")
        XCTAssertEqual(demo.snapshot.campaigns[1].messages[0], previous)
        settings.sendIntervalSeconds = 10
        XCTAssertThrowsError(try demo.saveSettings(settings))
    }

    func testSimulatedClockRespectsSpacingAndDailyCapAcrossJobs() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var demo = DemoWorkspace(now: start)
        var settings = demo.snapshot.settings
        settings.dailyLimit = 2
        settings.sendIntervalSeconds = 900
        try demo.saveSettings(settings)
        try demo.cancel(id: demo.snapshot.campaigns[0].id)
        let id = try demo.importJob(ImportRequest(title: "Engineer", company: "Example", domain: "example.com"))
        try demo.approve(id: id)
        try demo.simulateNextDelivery()
        XCTAssertEqual(demo.clock, start)
        try demo.simulateNextDelivery()
        XCTAssertEqual(demo.clock.timeIntervalSince(start), 900)
        try demo.simulateNextDelivery()
        XCTAssertGreaterThan(demo.clock.timeIntervalSince(start), 86400)
        XCTAssertEqual(demo.snapshot.campaigns[0].messages.filter { $0.status == "simulated" }.count, 3)
        try demo.cancel(id: id)
        XCTAssertEqual(demo.snapshot.campaigns[0].messages.filter { $0.status == "canceled" }.count, 2)
    }

    func testLongerCurrentPacingSlowsAlreadyQueuedPracticeMail() throws {
        var demo = DemoWorkspace()
        let id = try demo.importJob(ImportRequest(title: "Engineer", company: "Example", domain: "example.com"))
        try demo.approve(id: id)
        try demo.simulateNextDelivery()
        let first = demo.clock
        var settings = demo.snapshot.settings
        settings.sendIntervalSeconds = 1800
        try demo.saveSettings(settings)
        try demo.simulateNextDelivery()
        XCTAssertEqual(demo.clock.timeIntervalSince(first), 1800)
    }

    func testResumeValidationAndSnapshotAreLocalAndIndependent() throws {
        var first = DemoWorkspace()
        let second = DemoWorkspace()
        XCTAssertThrowsError(try first.setResume(filename: "not-a-pdf.pdf", data: Data("invalid".utf8)))
        try first.setResume(filename: "practice.pdf", data: Data("%PDF-1.7\npractice".utf8))
        XCTAssertEqual(first.snapshot.resume?.filename, "practice.pdf")
        XCTAssertNil(second.snapshot.resume)
        first.removeResume()
        XCTAssertNil(first.snapshot.resume)
        first.connectDirectory(false)
        let id = try first.importJob(ImportRequest(title: "Engineer", company: "Example", domain: "example.com"))
        XCTAssertThrowsError(try first.research(id: id, confirmedDomain: "example.com"))
        first.connectDirectory(true)
        try first.research(id: id, confirmedDomain: "example.com")
        XCTAssertEqual(first.snapshot.campaigns[0].status, "ready")
    }
}
