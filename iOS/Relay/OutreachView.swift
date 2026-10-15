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
                    RelayCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("OUTREACH AT A GLANCE", systemImage: "chart.bar.xaxis")
                                .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(RelayTheme.accent)
                            HStack(spacing: 12) {
                                metric(store.allMessages.filter { $0.status == "draft" }.count, "Drafts", "doc.text", RelayTheme.accent)
                                Rectangle().fill(RelayTheme.line).frame(width: 1)
                                metric(store.queuedCount, "Queued", "clock", RelayTheme.amber)
                                Rectangle().fill(RelayTheme.line).frame(width: 1)
                                metric(store.isDemo ? store.simulatedCount : store.submittedCount, store.isDemo ? "Simulated" : "Submitted", "checkmark.circle", RelayTheme.green)
                            }.frame(height: 78)
                        }
                    }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if store.isConnected || store.isDemo {
                    Section {
                        RelayCard {
                            VStack(alignment: .leading, spacing: 15) {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: store.queuePaused ? "pause.fill" : "clock.arrow.circlepath")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(RelayTheme.accent)
                                        .frame(width: 44, height: 44)
                                        .background(RelayTheme.wash, in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(store.queuePaused ? "Sending is paused" : "A calmer sending rhythm")
                                            .font(.headline).foregroundStyle(RelayTheme.ink)
                                        Text((store.snapshot?.settings ?? .default).pacingSummary)
                                            .font(.subheadline).foregroundStyle(RelayTheme.secondary)
                                        Text("\(store.snapshot?.settings.dailyLimit ?? 10) per 24 hours · longer job delays may apply")
                                            .font(.caption).foregroundStyle(RelayTheme.secondary)
                                    }
                                }
                                Button(store.queuePaused ? "Resume sending" : "Pause sending") { Task { await store.setQueuePaused(!store.queuePaused) } }
                                    .buttonStyle(RelaySecondaryButtonStyle()).disabled(store.isBusy)
                            }
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
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
                                    RelayCard {
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: "envelope")
                                                .font(.system(size: 17, weight: .medium))
                                                .foregroundStyle(RelayTheme.accent)
                                                .frame(width: 38, height: 38)
                                                .background(RelayTheme.wash, in: RoundedRectangle(cornerRadius: 12))
                                            VStack(alignment: .leading, spacing: 7) {
                                                Text(message.to).font(.subheadline.weight(.semibold)).foregroundStyle(RelayTheme.ink).lineLimit(1)
                                                Text(message.subject).font(.subheadline).foregroundStyle(RelayTheme.secondary).lineLimit(2)
                                                RelayStatusPill(status: message.status)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.secondary)
                                        }
                                    }
                                }.buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
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
            Text("\(count)").font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            Text(title).font(.caption.weight(.medium)).foregroundStyle(RelayTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
