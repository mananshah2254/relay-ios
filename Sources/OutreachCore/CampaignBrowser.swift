import Foundation

public enum CampaignFilter: String, CaseIterable, Sendable {
    case all, ready, active, attention
    public var title: String {
        switch self { case .all: "All"; case .ready: "Review"; case .active: "Active"; case .attention: "Attention" }
    }
    public func includes(_ campaign: Campaign) -> Bool {
        switch self {
        case .all: return true
        case .ready: return campaign.status == "ready"
        case .active: return ["researching", "queued", "sending"].contains(campaign.status)
        case .attention: return ["needs_details", "failed", "partial", "uncertain"].contains(campaign.status)
        }
    }
}

public enum CampaignSort: String, CaseIterable, Sendable {
    case newest, oldest, company
    public var title: String {
        switch self { case .newest: "Newest first"; case .oldest: "Oldest first"; case .company: "Company name" }
    }
}

public enum MessageFilter: String, CaseIterable, Sendable {
    case all, drafts, queued, attention
    public var title: String {
        switch self { case .all: "All"; case .drafts: "Drafts"; case .queued: "Queued"; case .attention: "Attention" }
    }
    public func includes(_ message: OutboundMessage) -> Bool {
        switch self {
        case .all: true
        case .drafts: message.status == "draft"
        case .queued: ["queued", "sending"].contains(message.status)
        case .attention: ["failed", "uncertain"].contains(message.status)
        }
    }
}

public enum CampaignBrowser {
    public static func results(_ campaigns: [Campaign], query: String, filter: CampaignFilter, sort: CampaignSort) -> [Campaign] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return campaigns.filter {
            filter.includes($0) && (term.isEmpty || [$0.company, $0.title, $0.domain].contains { $0.localizedCaseInsensitiveContains(term) })
        }.sorted {
            let comparison: ComparisonResult
            switch sort {
            case .company: comparison = $0.company.localizedStandardCompare($1.company)
            case .newest: comparison = $1.createdAt.compare($0.createdAt)
            case .oldest: comparison = $0.createdAt.compare($1.createdAt)
            }
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
}
