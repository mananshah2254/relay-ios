import OutreachCore
import SwiftUI

private struct CompanySearchPicker: View {
    @EnvironmentObject private var store: RelayStore
    @Binding var company: String
    @Binding var domain: String
    @State private var results: [CompanySuggestion] = []
    @State private var searching = false
    @State private var note: String?
    @State private var selected: CompanySuggestion?
    @State private var requestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                let query = company.trimmingCharacters(in: .whitespacesAndNewlines)
                let token = UUID()
                requestID = token
                searching = true
                results = []
                note = nil
                Task {
                    do {
                        let matches = try await store.searchCompanies(query: query)
                        guard requestID == token else { return }
                        results = matches
                        note = matches.isEmpty ? "No company matches. Enter the employer’s website below instead." : "Choose the employer by its website. Results are suggestions, not a complete company directory."
                    } catch {
                        guard requestID == token else { return }
                        note = error.localizedDescription
                    }
                    if requestID == token { searching = false }
                }
            } label: {
                Label(searching ? "Searching companies…" : "Find company website", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(searching || company.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || store.isDemo)
            if searching {
                HStack(spacing: 10) {
                    RelayActivityMark(compact: true)
                    Text("Matching names and websites").font(.caption).foregroundStyle(RelayTheme.secondary)
                }.accessibilityElement(children: .combine)
            }
            if let note { Text(note).font(.footnote).foregroundStyle(RelayTheme.secondary) }
            ForEach(results) { match in
                Button {
                    company = match.company
                    domain = match.domain
                    selected = match
                    results = []
                    note = "Selected \(match.domain). Contacts are searched when you save, not when you browse companies."
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.company).font(.subheadline.weight(.semibold))
                            Text(match.domain).font(.footnote).foregroundStyle(RelayTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.left.circle")
                    }.padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
        }
        .onChange(of: company) { _, value in
            requestID = UUID()
            searching = false
            results = []
            if let selected, value == selected.company { return }
            if let selected, domain == selected.domain { domain = "" }
            selected = nil
            note = nil
        }
        .onDisappear { requestID = UUID(); searching = false }
    }
}

struct JobsView: View {
    @EnvironmentObject private var store: RelayStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddJob = false
    @State private var path: [String] = []
    @State private var searchText = ""
    @State private var filter: CampaignFilter = .all
    @State private var sort: CampaignSort = .newest
    private var visibleCampaigns: [Campaign] {
        CampaignBrowser.results(store.campaigns, query: searchText, filter: filter, sort: sort)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                    if !store.isConnected && !store.isDemo {
                        WelcomeView().listRowBackground(Color.clear).listRowSeparator(.hidden)
                    } else {
                        Section {
                            HStack(spacing: 10) {
                                overview(.ready, symbol: "tray", color: RelayTheme.accent)
                                overview(.active, symbol: "paperplane", color: RelayTheme.green)
                                overview(.attention, symbol: "exclamationmark.circle", color: RelayTheme.amber)
                            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                        }
                        if !store.isDemo && (store.gmailEmail == nil || !store.hunterConnected) {
                            Section { Button { store.selectedTab = .settings } label: { Label("Finish account setup", systemImage: "link") } }
                        }
                        Section {
                            Picker("Job status", selection: $filter) {
                                ForEach(CampaignFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                        Section {
                            if store.campaigns.isEmpty {
                                RelayEmptyState(symbol: "briefcase", title: "Start with an opportunity", detail: "Add a company and role, or share a job from another app.")
                                Button("Add your first job") { showAddJob = true }.disabled(store.isDemo)
                            } else if visibleCampaigns.isEmpty {
                                ContentUnavailableView("No matching jobs", systemImage: "line.3.horizontal.decrease", description: Text("Try another status or search term."))
                                Button("Clear filters") { searchText = ""; filter = .all }
                            } else {
                                ForEach(visibleCampaigns, id: \.id) { campaign in
                                    NavigationLink(value: campaign.id) { CampaignListRow(campaign: campaign) }
                                        .contextMenu {
                                            if let url = URL(string: campaign.url), ["http", "https"].contains(url.scheme ?? "") { ShareLink(item: url) { Label("Share job link", systemImage: "square.and.arrow.up") } }
                                        }
                                }
                            }
                        } header: { Text("\(visibleCampaigns.count) \(visibleCampaigns.count == 1 ? "opportunity" : "opportunities")") }
                    }
                    if !store.pendingShares.isEmpty { Section { PendingSharesCard().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) } }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(RelayTheme.background)
            .navigationTitle("Jobs")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Company or job title")
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: filter)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: sort)
            .toolbar {
                if store.isConnected || store.isDemo {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort jobs", selection: $sort) { ForEach(CampaignSort.allCases, id: \.self) { Text($0.title).tag($0) } }
                        } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Sort jobs")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddJob = true } label: { Image(systemName: "plus").fontWeight(.semibold) }
                            .accessibilityLabel("Add a job")
                            .disabled(store.isDemo || store.isBusy)
                    }
                }
            }
            .navigationDestination(for: String.self) { CampaignDetailView(id: $0) }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showAddJob) {
                AddJobSheet { id in path.append(id) }
            }
        }
    }

    private func overview(_ value: CampaignFilter, symbol: String, color: Color) -> some View {
        Button { filter = filter == value ? .all : value } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(color)
                    Spacer(minLength: 0)
                    Text("\(store.campaigns.filter(value.includes).count)").font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
                }
                Text(value.title).font(.caption.weight(.medium)).foregroundStyle(RelayTheme.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(filter == value ? color : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).foregroundStyle(RelayTheme.ink)
            .accessibilityLabel("\(store.campaigns.filter(value.includes).count) jobs, \(value.title)")
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }

    private var shareTip: some View {
        RelayCard {
            HStack(alignment: .top, spacing: 14) {
                RelayAvatar(name: "", symbol: "square.and.arrow.up")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start with a role and company.").font(.headline)
                    Text("Enter them here, or share a job from another app. Confirm the company website, then find people to contact.")
                        .font(.footnote).foregroundStyle(RelayTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CampaignListRow: View {
    let campaign: Campaign
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RelayAvatar(name: campaign.company)
            VStack(alignment: .leading, spacing: 5) {
                Text(campaign.company.isEmpty ? "Company needed" : campaign.company).font(.headline)
                Text(campaign.title.isEmpty ? "Add job details" : campaign.title).font(.subheadline).foregroundStyle(RelayTheme.secondary).lineLimit(2)
                RelayStatusPill(status: campaign.status).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 7)
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var store: RelayStore
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 34).fill(RelayTheme.accent.opacity(0.055)).frame(height: 176)
                Image(systemName: "envelope.open").font(.system(size: 66, weight: .ultraLight)).foregroundStyle(RelayTheme.accent)
                    .rotationEffect(.degrees(-8))
                Image(systemName: "arrow.up.right").font(.system(size: 22, weight: .medium)).foregroundStyle(RelayTheme.accent)
                    .offset(x: 62, y: -42)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("Your next role.\nA real connection.")
                    .font(.largeTitle.bold()).foregroundStyle(RelayTheme.ink)
                Text("Share a job. Find people at the company. Reach out from your own Gmail, in your own words.")
                    .font(.body).foregroundStyle(RelayTheme.secondary)
            }
            VStack(spacing: 19) {
                welcomeStep("1", title: "Bring the opportunity", detail: "A LinkedIn job or a company careers link.")
                welcomeStep("2", title: "Find relevant people", detail: "Choose a bounded set of verified contacts with Hunter.")
                welcomeStep("3", title: "Make the introduction", detail: "Your template, your Gmail, and an optional résumé.")
            }
            VStack(spacing: 13) {
                Button("Set up Relay") { store.selectedTab = .settings }.buttonStyle(RelayPrimaryButtonStyle())
                Button("Explore the demo") { store.enterDemo() }.font(.subheadline.weight(.semibold)).padding(10)
            }
        }
    }
    private func welcomeStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.accent)
                .frame(width: 27, height: 27).background(RelayTheme.accent.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(RelayTheme.ink)
                Text(detail).font(.footnote).foregroundStyle(RelayTheme.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct CampaignCard: View {
    let campaign: Campaign
    var body: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    RelayAvatar(name: campaign.company.isEmpty ? "?" : campaign.company)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(campaign.company.isEmpty ? "Confirm company" : campaign.company).font(.subheadline.weight(.semibold)).foregroundStyle(RelayTheme.secondary)
                        Text(campaign.title.isEmpty ? "Job details needed" : campaign.title).font(.headline).foregroundStyle(RelayTheme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.secondary).padding(.top, 5)
                }
                HStack {
                    RelayStatusPill(status: campaign.status)
                    Spacer(minLength: 6)
                    if !campaign.contacts.isEmpty {
                        Label("\(campaign.contacts.count)", systemImage: "person.2").font(.caption).foregroundStyle(RelayTheme.secondary)
                    }
                }
            }
        }
    }
}

private struct PendingSharesCard: View {
    @EnvironmentObject private var store: RelayStore
    var body: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Saved from your share sheet", systemImage: "tray.and.arrow.down").font(.headline)
                Text("\(store.pendingShares.count) \(store.pendingShares.count == 1 ? "job is" : "jobs are") waiting to import\(store.isConnected ? "." : " once you connect Relay.")")
                    .font(.footnote).foregroundStyle(RelayTheme.secondary)
                ForEach(store.pendingShares.prefix(3), id: \.id) { share in
                    HStack {
                        Text(share.url).font(.caption).lineLimit(2)
                        Spacer(minLength: 8)
                        Button(role: .destructive) { store.removePendingShare(id: share.id) } label: { Image(systemName: "trash").padding(8) }
                            .accessibilityLabel("Remove saved job \(share.url)")
                    }
                }
                if store.isConnected {
                    Button("Retry import") { Task { await store.importPendingShares() } }
                        .buttonStyle(RelaySecondaryButtonStyle()).disabled(store.isBusy)
                }
            }
        }
    }
}

private struct AddJobSheet: View {
    @EnvironmentObject private var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @State private var company = ""
    @State private var domain = ""
    @State private var jobDescription = ""
    @State private var clientRequestID = UUID().uuidString
    @State private var isPrefilling = false
    @State private var prefillNote: String?
    let onAdded: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RelaySectionHeading(title: "Add the opportunity", detail: "All you need is the job title and company.")
                    if let error = store.errorMessage { RelayNotice(text: error, symbol: "exclamationmark.circle", color: RelayTheme.amber) }
                    RelayCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Job title").font(.subheadline.weight(.semibold))
                            TextField("iOS Engineer", text: $title)
                                .textInputAutocapitalization(.words).relayField()
                            Text("Company").font(.subheadline.weight(.semibold)).padding(.top, 6)
                            TextField("Example Company", text: $company)
                                .textInputAutocapitalization(.words).relayField()
                            CompanySearchPicker(company: $company, domain: $domain)
                            Text("Job link · optional").font(.subheadline.weight(.semibold)).padding(.top, 6)
                            TextField("https://www.linkedin.com/jobs/view/…", text: $url)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().relayField()
                            Button(isPrefilling ? "Looking up job…" : "Fill from link") {
                                let requestedURL = url
                                isPrefilling = true
                                Task {
                                    defer { isPrefilling = false }
                                    if let details = await store.previewJob(url: requestedURL, sharedText: jobDescription), url == requestedURL {
                                        if title.isEmpty { title = details.title }
                                        if company.isEmpty { company = details.company }
                                        if jobDescription.isEmpty { jobDescription = details.description }
                                        prefillNote = title.isEmpty || company.isEmpty ? "This link did not provide all details. Enter the missing fields, or paste the job’s shared text below and try again." : "Job details filled. Please check the company and role."
                                    }
                                }
                            }.buttonStyle(RelaySecondaryButtonStyle()).disabled(url.isEmpty || isPrefilling || store.isBusy)
                            if isPrefilling {
                                HStack { RelayActivityMark(compact: true); Text("Reading available job details").font(.caption).foregroundStyle(RelayTheme.secondary) }
                            }
                            if let prefillNote { Text(prefillNote).font(.footnote).foregroundStyle(RelayTheme.secondary) }
                        }
                    }
                    RelayCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Company website · optional").font(.subheadline.weight(.semibold))
                            TextField("example.com", text: $domain)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().relayField()
                            Text(store.settings.autoConfirmCompany == true ? "Leave this blank to look up the website. Automatic company confirmation is enabled; check the company name carefully." : "Leave this blank to look up the company website. You’ll confirm the match before finding contacts.")
                                .font(.footnote).foregroundStyle(RelayTheme.secondary)
                            Text("Job description · optional").font(.subheadline.weight(.semibold)).padding(.top, 6)
                            TextEditor(text: $jobDescription).frame(minHeight: 110).scrollContentBackground(.hidden).relayField()
                                .accessibilityLabel("Optional job description")
                        }
                    }
                    Button("Save & find contacts") {
                        Task {
                            if let id = await store.addJob(
                                url: url,
                                title: title,
                                company: company,
                                clientRequestID: clientRequestID,
                                domain: domain.isEmpty ? nil : domain,
                                description: jobDescription.isEmpty ? nil : jobDescription
                            ) {
                                dismiss()
                                onAdded(id)
                            }
                        }
                    }.buttonStyle(RelayPrimaryButtonStyle()).disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        store.isBusy || store.isDemo || isPrefilling
                    )
                }.padding(20)
            }
            .background(RelayTheme.background)
            .navigationTitle("Add a job").navigationBarTitleDisplayMode(.inline)
            .relayKeyboardDismissal()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isBusy) } }
            .interactiveDismissDisabled(store.isBusy)
            .relayActivityOverlay()
        }
    }
}

struct CampaignDetailView: View {
    @EnvironmentObject private var store: RelayStore
    let id: String
    @State private var showEdit = false
    @State private var showCancel = false
    @State private var showBroaden = false
    @State private var showRetryLookup = false
    @State private var showDiagnostic = false
    @State private var diagnostic: String?
    @State private var diagnosing = false
    @State private var preview: MessageSelection?

    var body: some View {
        ScrollView {
            if let campaign = store.campaign(id: id) {
                VStack(alignment: .leading, spacing: 22) {
                    header(campaign)
                    if campaign.canRetryLookup == true {
                        RelayCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Lookup interrupted", systemImage: "wifi.exclamationmark").font(.headline)
                                Text("No results were received. Retry with a longer wait; any recovered emails stay in review.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                                Button(store.isBusy ? "Waiting for Hunter…" : "Retry lookup") { showRetryLookup = true }
                                    .buttonStyle(RelayPrimaryButtonStyle()).disabled(store.isBusy || store.isDemo)
                            }
                        }
                    }
                    if campaign.canBroadenSearch == true {
                        RelayCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("No matching contacts yet", systemImage: "person.crop.circle.badge.questionmark").font(.headline)
                                Text("The last filters returned no matches. This isn’t proof that \(campaign.company) has no verified email addresses.")
                                    .font(.subheadline).foregroundStyle(RelayTheme.secondary)
                                Button("Broaden verified search") { showBroaden = true }
                                    .buttonStyle(RelayPrimaryButtonStyle()).disabled(store.isBusy || store.isDemo)
                                Text("Same company · verified personal emails · review before sending")
                                    .font(.caption).foregroundStyle(RelayTheme.secondary)
                                DisclosureGroup("Search details") {
                                    Text(campaign.note ?? "No results for the previous filters.").font(.footnote).foregroundStyle(RelayTheme.secondary)
                                }.font(.footnote)
                            }
                        }
                    } else if let note = campaign.note, !note.isEmpty { RelayNotice(text: note, color: RelayStatus.color(campaign.status)) }
                    if campaign.status == "uncertain" {
                        RelayNotice(text: "Gmail’s response was interrupted. Check your Sent folder before trying again; this email has not been automatically retried.", symbol: "questionmark.circle", color: RelayTheme.amber)
                    }
                    if campaign.title.isEmpty || campaign.company.isEmpty || campaign.domain.isEmpty || (campaign.status == "needs_details" && campaign.domainConfirmed != true) {
                        RelayCard {
                            VStack(alignment: .leading, spacing: 13) {
                                RelaySectionHeading(title: "Confirm the company", detail: campaign.domain.isEmpty ? "Add the employer website or let Relay look it up from the company name." : "Make sure \(campaign.domain) belongs to \(campaign.company).")
                                Button("Edit job details") { showEdit = true }.buttonStyle(RelaySecondaryButtonStyle())
                            }
                        }
                    }
                    if !campaign.description.isEmpty {
                        RelayCard {
                            DisclosureGroup("About this role") {
                                Text(campaign.description).font(.subheadline).foregroundStyle(RelayTheme.secondary)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                            }.font(.headline)
                        }
                    }
                    contactSection(campaign)
                    actionSection(campaign)
                }.padding(20).padding(.bottom, 20)
            } else {
                RelayEmptyState(symbol: "briefcase", title: "Job unavailable", detail: "Refresh your jobs to load this opportunity.").padding(20)
            }
        }
        .background(RelayTheme.background)
        .navigationTitle("Opportunity").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit job details", systemImage: "pencil") { showEdit = true }.disabled(store.isDemo || store.isBusy)
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isDemo)
                    Button("Diagnose contact lookup", systemImage: "stethoscope") { showDiagnostic = true }.disabled(store.isDemo || diagnosing)
                    if let campaign = store.campaign(id: id), !campaign.url.isEmpty, let url = URL(string: campaign.url) { Link(destination: url) { Label("Open original job", systemImage: "arrow.up.right.square") } }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Job actions")
            }
        }
        .refreshable { await store.refresh() }
        .confirmationDialog("Retry the interrupted lookup?", isPresented: $showRetryLookup, titleVisibility: .visible) {
            Button("Retry once · review results") { Task { await store.researchJob(id: id, retryLookup: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hunter may have charged for the previous attempt. This makes one new request up to your saved contact limit and waits up to 60 seconds. Additional credits may apply. It will not automatically send emails.")
        }
        .confirmationDialog("Check Hunter’s contact data?", isPresented: $showDiagnostic, titleVisibility: .visible) {
            Button("Run diagnostic · up to 5 contacts") {
                diagnosing = true
                Task { diagnostic = await store.diagnoseJob(id: id); diagnosing = false }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One lookup samples up to 5 personal addresses without verification or role filters. Hunter credits may apply. Only counts are shown; no emails are drafted, queued or sent. Reopening shows the saved diagnostic without another lookup.")
        }
        .alert("Hunter diagnostic", isPresented: Binding(get: { diagnostic != nil }, set: { if !$0 { diagnostic = nil } })) {
            Button("OK") { diagnostic = nil }
        } message: { Text(diagnostic ?? "") }
        .confirmationDialog("Search more broadly?", isPresented: $showBroaden, titleVisibility: .visible) {
            Button("Search verified company colleagues") { Task { await store.researchJob(id: id, broadenSearch: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This makes one new Hunter lookup, up to your saved contact limit. It removes department, seniority, and job-title requirements, but keeps verified personal emails and names. Credits may apply. You must review any results before sending.")
        }
        .sheet(isPresented: $showEdit) { if let campaign = store.campaign(id: id) { EditJobSheet(campaign: campaign) } }
        .sheet(item: $preview) { selection in MessagePreviewSheet(message: selection.message) }
        .confirmationDialog("Cancel unsent outreach for this job?", isPresented: $showCancel, titleVisibility: .visible) {
            Button("Cancel remaining emails", role: .destructive) { Task { await store.cancelJob(id: id) } }
            Button("Keep outreach", role: .cancel) {}
        } message: { Text("Emails already submitted to Gmail cannot be recalled.") }
    }

    private func header(_ campaign: Campaign) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RelayAvatar(name: campaign.company.isEmpty ? "?" : campaign.company)
                VStack(alignment: .leading, spacing: 3) {
                    Text(campaign.company.isEmpty ? "Company to confirm" : campaign.company).font(.headline)
                    if !campaign.domain.isEmpty { Text(campaign.domain).font(.footnote).foregroundStyle(RelayTheme.secondary) }
                }
            }
            Text(campaign.title.isEmpty ? "Let’s fill in this role" : campaign.title).font(.title2.bold()).foregroundStyle(RelayTheme.ink)
            RelayStatusPill(status: campaign.status)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contactSection(_ campaign: Campaign) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RelaySectionHeading(title: "People to reach", detail: campaign.contacts.isEmpty ? "Contacts will appear here after research." : "\(campaign.contacts.count) \(campaign.contacts.count == 1 ? "person" : "people") matched to this opportunity")
            if campaign.status == "researching" {
                RelayCard {
                    HStack(spacing: 14) {
                        RelayActivityMark(compact: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Finding relevant people…").font(.subheadline.weight(.semibold))
                            Text("You can leave this screen. Your research continues.").font(.footnote).foregroundStyle(RelayTheme.secondary)
                        }
                    }
                }
            }
            ForEach(campaign.contacts, id: \.id) { contact in
                RelayCard {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .top, spacing: 12) {
                            RelayAvatar(name: contact.firstName.isEmpty ? contact.email : contact.firstName)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contactName(contact)).font(.headline)
                                Text(contact.position.isEmpty ? "Company contact" : contact.position).font(.footnote).foregroundStyle(RelayTheme.secondary)
                            }
                        }
                        Text(contact.email).font(.subheadline).textSelection(.enabled)
                        if !contact.reason.isEmpty { Text(contact.reason).font(.footnote).foregroundStyle(RelayTheme.secondary) }
                        HStack {
                            Label(contact.verification.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "checkmark.shield")
                                .font(.caption).foregroundStyle(RelayTheme.secondary)
                            Spacer(minLength: 0)
                            if let message = campaign.messages.first(where: { $0.contactId == contact.id }) {
                                Button("View email") { preview = MessageSelection(message: message) }.font(.footnote.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func actionSection(_ campaign: Campaign) -> some View {
        if campaign.status == "ready" && !campaign.messages.isEmpty {
            RelayNotice(text: "Each person receives a separate email from your connected Gmail. Review their message before approving.", symbol: "envelope")
            Button("Approve \(campaign.messages.filter { $0.status == "draft" }.count) emails") {
                Task { await store.approveJob(id: id) }
            }.buttonStyle(RelayPrimaryButtonStyle()).disabled(store.isBusy || store.isDemo || store.gmailEmail == nil)
        } else if campaign.status == "needs_details" && campaign.contacts.isEmpty {
            Button(campaign.domain.isEmpty ? "Look up company website" : (campaign.domainConfirmed == true ? "Find referral contacts" : "Confirm company and find contacts")) {
                Task { await store.researchJob(id: id, confirmedDomain: campaign.domain.isEmpty ? nil : campaign.domain) }
            }
                .buttonStyle(RelayPrimaryButtonStyle())
                .disabled(store.isBusy || store.isDemo || !store.hunterConnected || campaign.title.isEmpty || campaign.company.isEmpty)
        }
        if ["researching", "ready", "queued", "sending", "partial"].contains(campaign.status) {
            Button("Cancel remaining outreach", role: .destructive) { showCancel = true }
                .font(.subheadline).frame(maxWidth: .infinity).padding(8).disabled(store.isBusy || store.isDemo)
        }
    }

    private func contactName(_ contact: Contact) -> String {
        let fullName = "\(contact.firstName) \(contact.lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? contact.email : fullName
    }
}

private struct EditJobSheet: View {
    @EnvironmentObject private var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    let campaign: Campaign
    @State private var title: String
    @State private var company: String
    @State private var domain: String
    @State private var jobDescription: String
    @State private var jobURL: String

    init(campaign: Campaign) {
        self.campaign = campaign
        _title = State(initialValue: campaign.title)
        _company = State(initialValue: campaign.company)
        _domain = State(initialValue: campaign.domain)
        _jobDescription = State(initialValue: campaign.description)
        _jobURL = State(initialValue: campaign.url)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(RelayTheme.amber) }
                }
                Section("The opportunity") {
                    TextField("Job title", text: $title)
                    TextField("Company name", text: $company)
                    CompanySearchPicker(company: $company, domain: $domain)
                    TextField("Company domain, e.g. example.com", text: $domain).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Job link · optional", text: $jobURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Job description") { TextEditor(text: $jobDescription).frame(minHeight: 180) }
                Section {
                    Text("Use the employer’s email domain, which may differ from its website. Greenhouse Software uses greenhouse.io. Leave blank for a company lookup.").font(.footnote).foregroundStyle(RelayTheme.secondary)
                    if campaign.status == "failed" {
                        Text("A confirmed zero-result lookup can be retried only after correcting the domain. Saving runs a new Hunter lookup and may use credits. Recovered emails will require review, even when automatic sending is enabled.")
                            .font(.footnote).foregroundStyle(RelayTheme.amber)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(RelayTheme.background)
            .navigationTitle("Job details").navigationBarTitleDisplayMode(.inline)
            .relayKeyboardDismissal()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let request = ImportRequest(url: jobURL, title: title, company: company, domain: domain, description: jobDescription)
                            if await store.updateJob(id: campaign.id, request: request) { dismiss() }
                        }
                    }.disabled(store.isBusy || store.isDemo || title.trimmingCharacters(in: .whitespaces).isEmpty || company.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.interactiveDismissDisabled(store.isBusy)
            .relayActivityOverlay()
        }
    }
}

struct MessageSelection: Identifiable {
    let id = UUID()
    let message: OutboundMessage
}

struct MessagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let message: OutboundMessage
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RelayStatusPill(status: message.status)
                    RelayCard {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("TO").font(.caption2.weight(.semibold)).foregroundStyle(RelayTheme.secondary)
                                Text(message.to).font(.subheadline).textSelection(.enabled)
                            }
                            Divider()
                            Text(message.subject).font(.headline).textSelection(.enabled)
                            Text(message.body).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let error = message.error, !error.isEmpty { RelayNotice(text: error, symbol: "exclamationmark.circle", color: RelayTheme.amber) }
                    if message.status == "submitted" {
                        Text("Submitted to Gmail records the sending request. It does not confirm inbox delivery or a reply.").font(.footnote).foregroundStyle(RelayTheme.secondary)
                    }
                }.padding(20)
            }
            .background(RelayTheme.background)
            .navigationTitle("Email preview").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
