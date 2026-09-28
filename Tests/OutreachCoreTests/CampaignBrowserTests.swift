import XCTest
@testable import OutreachCore

final class CampaignBrowserTests: XCTestCase {
    private let jobs = [
        Campaign(id: "a", url: "", title: "Software Engineer", company: "Acme", domain: "acme.ai", status: "ready", createdAt: "2026-09-01T00:00:00.000Z"),
        Campaign(id: "b", url: "", title: "Support Engineer", company: "Beta", status: "failed", createdAt: "2026-09-02T00:00:00.000Z"),
        Campaign(id: "c", url: "", company: "Acme", status: "queued", createdAt: "2026-09-03T00:00:00.000Z")
    ]
    func testSearchUsesNameRoleAndActualDomain() {
        XCTAssertEqual(CampaignBrowser.results(jobs, query: " ACME.AI ", filter: .all, sort: .newest).map(\.id), ["a"])
        XCTAssertEqual(CampaignBrowser.results(jobs, query: "support", filter: .attention, sort: .newest).map(\.id), ["b"])
    }
    func testFiltersDistinguishReviewActiveAndAttention() {
        XCTAssertEqual(jobs.filter(CampaignFilter.ready.includes).map(\.id), ["a"])
        XCTAssertEqual(jobs.filter(CampaignFilter.active.includes).map(\.id), ["c"])
        XCTAssertEqual(jobs.filter(CampaignFilter.attention.includes).map(\.id), ["b"])
        XCTAssertTrue(CampaignBrowser.results(jobs, query: "Beta", filter: .ready, sort: .newest).isEmpty)
    }
    func testStableSortOrders() {
        XCTAssertEqual(CampaignBrowser.results(jobs, query: "", filter: .all, sort: .newest).map(\.id), ["c", "b", "a"])
        XCTAssertEqual(CampaignBrowser.results(jobs, query: "", filter: .all, sort: .oldest).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(CampaignBrowser.results(jobs, query: "", filter: .all, sort: .company).map(\.id), ["a", "c", "b"])
    }
    func testUnknownStatusIsStillVisibleInAll() {
        let job = Campaign(id: "future", url: "", status: "new_future_state", createdAt: "")
        XCTAssertTrue(CampaignFilter.all.includes(job))
        XCTAssertFalse(CampaignFilter.active.includes(job))
    }
    func testMessageFiltersDoNotShowSubmittedEmailsAsQueued() {
        let draft = OutboundMessage(id: "d", contactId: "c", to: "sample@example.com", subject: "Sample", body: "Sample", status: "draft")
        var submitted = draft
        submitted.status = "submitted"
        XCTAssertTrue(MessageFilter.drafts.includes(draft))
        XCTAssertFalse(MessageFilter.queued.includes(submitted))
        XCTAssertFalse(MessageFilter.attention.includes(submitted))
        XCTAssertTrue(MessageFilter.all.includes(submitted))
    }
}
