import OutreachCore
import SwiftUI

struct OutreachView: View {
    @EnvironmentObject private var store: RelayStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: MessageFilter = .all
    @State private var query = ""
    @State private var preview: MessageSelection?

    private func messages(_ campaign: Campaign) -> [OutboundMessage] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return campaign.messages.filter {
            filter.includes($0) && (term.isEmpty || campaign.company.localizedCaseInsensitiveContains(term) || $0.to.localizedCaseInsensitiveContains(term) || $0.subject.localizedCaseInsensitiveContains(term))
        }
    }
    private var campaigns: [Campaign] { store.campaigns.filter { !messages($0).isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        metric(store.allMessages.filter { $0.status == "draft" }.count, "Drafts", "doc.text", RelayTheme.accent)
                        Divider()
                        metric(store.queuedCount, "Queued", "clock", RelayTheme.amber)
                        Divider()
                        metric(store.isDemo ? store.simulatedCount : store.submittedCount, store.isDemo ? "Simulated" : "Submitted", "checkmark.circle", RelayTheme.green)
                    }.padding(.vertical, 8)
                }
                if store.isConnected || store.isDemo {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: store.queuePaused ? "pause.circle.fill" : "clock.arrow.circlepath")
                                .foregroundStyle(RelayTheme.accent).font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.queuePaused ? "Sending paused" : "Sending schedule").font(.subheadline.weight(.semibold))
                                Text((store.snapshot?.settings ?? .default).pacingSummary)
                                    .font(.caption).foregroundStyle(RelayTheme.secondary)
                                Text("\(store.snapshot?.settings.dailyLimit ?? 10) per 24h · Longer saved job delays may apply")
                                    .font(.caption).foregroundStyle(RelayTheme.secondary)
                            }
                            Spacer(minLength: 4)
                            Button(store.queuePaused ? "Resume" : "Pause") { Task { await store.setQueuePaused(!store.queuePaused) } }
                                .buttonStyle(.bordered).disabled(store.isBusy)
                        }
                    }
                    Section {
                        Picker("Email status", selection: $filter) {
                            ForEach(MessageFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                if campaigns.isEmpty {
                    Section {
                        ContentUnavailableView("No emails here", systemImage: "tray", description: Text(query.isEmpty && filter == .all ? "Prepare a job to see its drafts and track your outreach." : "Try another filter or search term."))
                    }
                } else {
                    ForEach(campaigns) { campaign in
                        Section {
                            ForEach(messages(campaign)) { message in
                                Button { preview = MessageSelection(message: message) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(message.to).font(.subheadline.weight(.semibold)).foregroundStyle(RelayTheme.ink).lineLimit(1)
                                        Text(message.subject).font(.subheadline).foregroundStyle(RelayTheme.secondary).lineLimit(2)
                                        RelayStatusPill(status: message.status)
                                    }.padding(.vertical, 6)
                                }.buttonStyle(.plain)
                            }
                        } header: {
                            NavigationLink { CampaignDetailView(id: campaign.id) } label: {
                                HStack { Text(campaign.company); Spacer(); Image(systemName: "arrow.up.right") }
                            }
                        }
                    }
                }
                if store.isDemo {
                    Section("Practice delivery") {
                        Button("Simulate next delivery", systemImage: "clock.arrow.circlepath") { Task { await store.simulateNextDelivery() } }
                            .disabled(store.isBusy || store.queuePaused || store.queuedCount == 0)
                        Text("Advances the practice clock to the next permitted send time, including your spacing and daily limit. No Gmail request is made. Pause, resume or cancel the queue to try those controls.")
                            .font(.footnote).foregroundStyle(RelayTheme.secondary)
                    }
                } else {
                    Section { Text("Submitted means accepted by Gmail—not proof of delivery. Replies arrive in Gmail.").font(.footnote).foregroundStyle(RelayTheme.secondary) }
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(RelayTheme.background)
            .navigationTitle("Outreach").navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Company, recipient or subject")
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: filter)
            .refreshable { await store.refresh() }
            .sheet(item: $preview) { MessagePreviewSheet(message: $0.message) }
        }
    }

    private func metric(_ count: Int, _ title: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            Text("\(count)").font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(RelayTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
