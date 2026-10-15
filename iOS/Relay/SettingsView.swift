import OutreachCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RelayStore
    @State private var serviceURL = AppEnvironment.backendURL
    @State private var showConnections = false
    @State private var showAdvanced = false
    @State private var hunterKey = ""
    @State private var replaceHunterKey = false
    @State private var showDeleteAccount = false

    var body: some View {
        NavigationStack {
            List {
                if store.isConnected || store.isDemo {
                    Section {
                        RelayCard {
                            VStack(alignment: .leading, spacing: 17) {
                                HStack(spacing: 14) {
                                    RelayAvatar(name: store.settings.senderName.isEmpty ? "R" : store.settings.senderName)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(store.settings.senderName.isEmpty ? "Your workspace" : store.settings.senderName)
                                            .font(.title3.weight(.bold)).foregroundStyle(RelayTheme.ink)
                                        Text(store.isDemo ? "Practice workspace" : store.gmailEmail ?? "Connect Gmail to get started")
                                            .font(.footnote).foregroundStyle(RelayTheme.secondary).lineLimit(2)
                                    }
                                }
                                Rectangle().fill(RelayTheme.line).frame(height: 1)
                                HStack(spacing: 7) {
                                    Image(systemName: store.isDemo ? "sparkles" : "checkmark.shield.fill")
                                    Text(store.isDemo ? "No real emails in practice" : "Your private Relay space")
                                }
                                .font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.accent)
                            }
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    Section("Workspace") {
                        Button { store.selectedTab = .templates } label: {
                            settingsLabel("Sender name", detail: "Edit your name in Templates, then tap Save", symbol: "person.crop.circle", color: RelayTheme.accent)
                        }.foregroundStyle(RelayTheme.ink)
                        NavigationLink { settingsPage("Connections") { serviceCard; connectionsCard } } label: {
                            settingsLabel("Connected accounts", detail: "Gmail, Hunter & Relay", symbol: "link", color: RelayTheme.accent)
                        }
                        NavigationLink { settingsPage("Sending preferences") { outreachLimitsCard } } label: {
                            settingsLabel("Sending preferences", detail: "Limits, timing & approvals", symbol: "slider.horizontal.3", color: RelayTheme.button)
                        }
                        Button { store.selectedTab = .templates } label: {
                            settingsLabel("Templates & résumé", detail: "Your introduction and attachments", symbol: "doc.text", color: RelayTheme.green)
                        }.foregroundStyle(RelayTheme.ink)
                    }
                    Section {
                        NavigationLink { settingsPage("Data & privacy") { accountCard } } label: {
                            settingsLabel("Data & privacy", detail: "Storage and account controls", symbol: "hand.raised", color: .gray)
                        }
                    } header: { Text("Privacy") } footer: {
                        Text("Relay sends through your Gmail. It does not read your inbox or track opens.")
                    }
                    Section("Practice workspace") {
                        if store.isDemo {
                            Text("Try jobs, templates, attachments, approvals and delivery with fictional contacts. Connections and sends are simulated. Practice data clears when you exit or close the app.").font(.footnote).foregroundStyle(.secondary)
                            Button("Reset practice workspace") { store.enterDemo() }
                            Button("Exit practice") { Task { await store.leaveDemo() } }
                        } else {
                            Button("Explore the demo") { store.enterDemo() }
                        }
                    }
                } else {
                    Section { serviceCard.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                }
                Section("Help & information") {
                    Link(destination: URL(string: "https://relay.trailmails.com/support/")!) {
                            settingsLabel("Support", detail: "Setup and troubleshooting", symbol: "questionmark.circle", color: RelayTheme.accent)
                    }
                    Link(destination: URL(string: "https://relay.trailmails.com/privacy/")!) {
                        settingsLabel("Privacy policy", detail: "How your information is handled", symbol: "hand.raised", color: .gray)
                    }
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(RelayTheme.background)
            .navigationTitle("Settings")
            .relayKeyboardDismissal()
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showConnections) {
                settingsPage("Connections") { serviceCard; connectionsCard }
            }
            .refreshable { await store.refresh() }
            .onAppear { serviceURL = AppEnvironment.backendURL }
            .confirmationDialog(store.isDemo ? "Clear the practice workspace?" : "Delete your Relay account and stored outreach?", isPresented: $showDeleteAccount, titleVisibility: .visible) {
                Button(store.isDemo ? "Clear practice data" : "Delete account", role: .destructive) { Task { _ = await store.deleteAccount() } }
                Button("Keep account", role: .cancel) {}
            } message: {
                Text(store.isDemo ? "Clears only the temporary practice data and returns to your live workspace. No live account or queued email is changed." : "This removes the Relay session, résumé, templates, campaigns, and saved provider connections. Emails already submitted to Gmail cannot be recalled.")
            }
        }
    }

    private func settingsLabel(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .frame(width: 38, height: 38).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(RelayTheme.secondary)
            }
        }.padding(.vertical, 3)
    }

    private func settingsPage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView { VStack(spacing: 20) { content() }.padding(20) }
            .background(RelayTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .relayKeyboardDismissal()
    }

    private var serviceCard: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 15) {
                RelaySectionHeading(title: store.isConnected ? "Your Relay account" : "Welcome to Relay", detail: store.isConnected ? "Your private workspace is connected." : "Create your workspace, then connect your accounts. No invitation needed.")
                if store.isDemo {
                    Label("Demo mode · no service connected", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(RelayTheme.accent)
                } else if store.isConnected {
                    Label("Connected securely", systemImage: "checkmark.shield.fill")
                        .font(.footnote).foregroundStyle(RelayTheme.green)
                        .textSelection(.enabled)
                    Text("Your Gmail, résumé, and templates stay private to your workspace.")
                        .font(.footnote).foregroundStyle(RelayTheme.secondary)
                } else {
                    Button(store.isBusy ? "Getting started…" : "Get started") {
                        Task {
                            if await store.joinRelay() { showConnections = true }
                        }
                    }
                    .buttonStyle(RelayPrimaryButtonStyle())
                    .accessibilityIdentifier("relay.getStarted")
                    .disabled(store.isBusy)
                    Text("You’ll need your own Gmail account and Hunter API key for live outreach. Provider usage limits and charges may apply.")
                        .font(.footnote).foregroundStyle(RelayTheme.secondary)
                    DisclosureGroup("Advanced · custom service", isExpanded: $showAdvanced) {
                    TextField("https://relay.example.com", text: $serviceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .relayField()
                    Text("Use HTTPS for a deployed service. HTTP is accepted only for localhost development; localhost on an iPhone means the phone itself.")
                        .font(.footnote).foregroundStyle(RelayTheme.secondary)
                    Button("Connect service") {
                        Task {
                            if await store.connectService(url: serviceURL) { showConnections = true }
                        }
                    }
                    .buttonStyle(RelayPrimaryButtonStyle())
                    .disabled(store.isBusy || serviceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private var connectionsCard: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 16) {
                if store.isDemo {
                    RelaySectionHeading(title: "Sample connections", detail: "No Google sign-in or API key is used in practice mode.")
                    connectionRow(title: "Sample sender", detail: store.gmailEmail ?? "Not connected", symbol: "envelope")
                    Button(store.gmailEmail == nil ? "Enable sample sender" : "Disconnect sample sender") {
                        Task { if store.gmailEmail == nil { await store.connectGoogle() } else { await store.disconnectGoogle() } }
                    }.buttonStyle(RelaySecondaryButtonStyle())
                    Button(store.hunterConnected ? "Disconnect sample directory" : "Enable sample directory") {
                        Task { if store.hunterConnected { await store.disconnectHunter() } else { _ = await store.connectHunter(apiKey: "") } }
                    }.buttonStyle(RelaySecondaryButtonStyle())
                    Text("Live mode uses Gmail OAuth and your Hunter account. Practice mode does not test or grant those permissions.").font(.footnote).foregroundStyle(.secondary)
                } else {
                RelaySectionHeading(title: "Your accounts", detail: "Your Gmail sends the emails. Your Hunter account supplies the contacts.")
                connectionRow(title: "Gmail", detail: store.gmailEmail ?? "Not connected", symbol: "envelope")
                if store.gmailEmail == nil {
                    Button("Connect Gmail") { Task { await store.connectGoogle() } }
                        .buttonStyle(RelayPrimaryButtonStyle()).disabled(store.isBusy)
                } else {
                    Button("Reconnect Gmail") { Task { await store.connectGoogle() } }
                        .buttonStyle(RelaySecondaryButtonStyle()).disabled(store.isBusy)
                    Button("Disconnect Gmail", role: .destructive) { Task { await store.disconnectGoogle() } }
                        .font(.footnote.weight(.semibold)).frame(maxWidth: .infinity).padding(5).disabled(store.isBusy)
                }
                Divider()
                connectionRow(title: "Hunter", detail: store.hunterConnected ? "Connected" : "Not connected", symbol: "person.2")
                if !store.hunterConnected || replaceHunterKey {
                    SecureField("Paste your Hunter API key", text: $hunterKey)
                        .textContentType(.password).relayField()
                    Button(store.hunterConnected ? "Save new Hunter key" : "Connect Hunter") {
                        Task {
                            if await store.connectHunter(apiKey: hunterKey) { hunterKey = ""; replaceHunterKey = false }
                        }
                    }
                    .buttonStyle(RelayPrimaryButtonStyle()).disabled(store.isBusy || hunterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if store.hunterConnected {
                        Button("Cancel") { hunterKey = ""; replaceHunterKey = false }
                            .buttonStyle(RelaySecondaryButtonStyle()).disabled(store.isBusy)
                    }
                } else {
                    Button("Replace Hunter key") { hunterKey = ""; replaceHunterKey = true }
                        .buttonStyle(RelaySecondaryButtonStyle()).disabled(store.isBusy)
                    Button("Disconnect Hunter", role: .destructive) { Task { await store.disconnectHunter() } }
                        .font(.footnote.weight(.semibold)).frame(maxWidth: .infinity).padding(5).disabled(store.isBusy)
                }
                RelayNotice(text: "Hunter searches for verified professional addresses. It cannot confirm who is the hiring manager, and results may be fewer than your limit.", symbol: "info.circle")
                }
            }
        }
    }

    private var outreachLimitsCard: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 16) {
                RelaySectionHeading(title: "Outreach controls", detail: "Pacing is shared across jobs using the same Gmail account.")
                Stepper(value: $store.settings.maxContacts, in: 1...20) {
                    settingRow("Contacts per job", value: "\(store.settings.maxContacts)")
                }
                Stepper(value: $store.settings.sendIntervalSeconds, in: 600...3600, step: 300) {
                    settingRow("Time between emails", value: intervalLabel(store.settings.sendIntervalSeconds))
                }
                RelayNotice(text: "\(store.settings.pacingSummary). Default: one email every 10 minutes, up to six per hour. Longer saved job delays and your daily limit still apply. Increasing the interval also slows queued mail after you save.", symbol: "clock")
                Text("Spacing reduces bursts; it does not guarantee inbox placement. Send relevant, wanted messages and respect requests not to be contacted.")
                    .font(.footnote).foregroundStyle(.secondary)
                Stepper(value: $store.settings.dailyLimit, in: 1...100) {
                    settingRow("Daily send limit", value: "\(store.settings.dailyLimit)")
                }
                Picker("Contact preference", selection: $store.settings.recipientPreference) {
                    Text("Role, recruiting & leadership").tag("relevant")
                    Text("Senior or executive").tag("senior")
                    Text("Executives only").tag("executive")
                    Text("Recruiting / HR").tag("recruiting")
                }
                .pickerStyle(.menu)
                Toggle("Automatically confirm company website", isOn: Binding(
                    get: { store.settings.autoConfirmCompany == true },
                    set: { store.settings.autoConfirmCompany = $0 }
                ))
                if store.settings.autoConfirmCompany == true {
                    RelayNotice(text: "Relay will trust Hunter’s company match without asking you. Similar company names can produce the wrong match. Unmatched companies still need your input. Enable automatic sending below to also queue emails after research.", symbol: "exclamationmark.triangle", color: RelayTheme.amber)
                }
                Toggle("Send automatically when research is ready", isOn: Binding(
                    get: { store.settings.sendingMode == "automatic" },
                    set: { store.settings.sendingMode = $0 ? "automatic" : "review" }
                ))
                if store.settings.sendingMode == "automatic" {
                    RelayNotice(text: "Saving a job can queue real emails without another approval. Check the selected role template, sender name, résumé, and company details first. This uses Hunter credits and your Gmail sending allowance.", symbol: "exclamationmark.triangle", color: RelayTheme.amber)
                }
                Button(store.hasUnsavedSettings ? "Save outreach controls" : "Controls saved") {
                    Task { _ = await store.saveSettings() }
                }
                .buttonStyle(RelayPrimaryButtonStyle())
                .disabled(store.isBusy || !store.hasUnsavedSettings)
            }
        }
    }

    private var nextStepsCard: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 14) {
                RelaySectionHeading(title: "3. Prepare your first request", detail: "A few details make each message yours.")
                Label(store.gmailEmail == nil ? "Connect Gmail above" : "Gmail connected", systemImage: store.gmailEmail == nil ? "circle" : "checkmark.circle.fill")
                Label(store.hunterConnected ? "Hunter connected" : "Add your Hunter key above", systemImage: store.hunterConnected ? "checkmark.circle.fill" : "circle")
                Button("Edit email template & add résumé") { store.selectedTab = .templates }
                    .buttonStyle(RelaySecondaryButtonStyle())
                Button("Add a job") { store.selectedTab = .jobs }
                    .buttonStyle(RelaySecondaryButtonStyle())
                Text("Enter the job title and company, or share a job link and confirm the details. Review the contacts and draft before sending.")
                    .font(.footnote).foregroundStyle(RelayTheme.secondary)
                RelayNotice(text: "Real outreach sends from your Gmail account. Check each recipient and message before approval. Your daily limit and send spacing still apply.", symbol: "info.circle")
            }
        }
    }

    private var accountCard: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 14) {
                RelaySectionHeading(title: "Data & account", detail: "Relay does not read your Gmail inbox or track opens.")
                Text(store.isDemo ? "This practice workspace is held only in memory. It does not access your live credentials, upload your files or send emails. Exit practice to clear it." : "Your résumé, templates, provider tokens, and campaign snapshots are stored by the connected backend. Review the service's deployment and privacy policy before using real outreach.")
                    .font(.footnote).foregroundStyle(RelayTheme.secondary)
                Button(store.isDemo ? "Clear practice data" : "Delete Relay account", role: .destructive) { showDeleteAccount = true }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(8)
                    .disabled(store.isBusy)
            }
        }
    }

    private func connectionRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(RelayTheme.accent)
                .frame(width: 36, height: 36).background(RelayTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(RelayTheme.secondary).textSelection(.enabled)
            }
            Spacer()
            Image(systemName: detail == "Not connected" ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(detail == "Not connected" ? RelayTheme.secondary : RelayTheme.green)
        }
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(RelayTheme.secondary).monospacedDigit()
        }
    }

    private func intervalLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return seconds % 60 == 0 ? "\(minutes)m" : "\(minutes)m \(seconds % 60)s"
    }
}
