import SwiftUI

@main
struct RelayApp: App {
    @UIApplicationDelegateAdaptor(RelayAppDelegate.self) private var appDelegate
    @StateObject private var store = RelayStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RelayRootView()
                .environmentObject(store)
                .tint(RelayTheme.accent)
                #if DEBUG
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--relay-preview-light") ? .light : nil)
                #endif
                .task { await store.activate() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(8)) }
                        catch { break }
                        await store.pollIfNeeded()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.activate() } }
                }
                .onOpenURL { _ in Task { await store.activate() } }
        }
    }
}

private struct RelayRootView: View {
    @EnvironmentObject private var store: RelayStore
    var body: some View {
        VStack(spacing: 0) {
            if store.isDemo {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                    Text("Practice · No real emails").font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Button("Exit") { Task { await store.leaveDemo() } }.font(.caption.weight(.bold)).padding(.vertical, 10)
                }
                .padding(.horizontal, 20)
                .foregroundStyle(RelayTheme.accent)
                .background(RelayTheme.accent.opacity(0.09))
            }
            TabView(selection: $store.selectedTab) {
                JobsView().tabItem { Label("Jobs", systemImage: "briefcase") }.tag(RelayTab.jobs)
                OutreachView().tabItem { Label("Outreach", systemImage: "paperplane") }.tag(RelayTab.outreach)
                TemplatesView().tabItem { Label("Templates", systemImage: "text.document") }.tag(RelayTab.templates)
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(RelayTab.settings)
            }
        }
        .background(RelayTheme.background)
        .onChange(of: store.selectedTab) { _, _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .relayActivityOverlay()
        .overlay(alignment: .top) {
            if let notice = store.notice, !store.isBusy {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RelayTheme.green)
                    Text(notice).font(.subheadline.weight(.medium))
                    Button { store.notice = nil } label: { Image(systemName: "xmark").padding(8) }
                        .accessibilityLabel("Dismiss confirmation")
                }
                .padding(12).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.08), radius: 15, y: 5).padding(.horizontal, 20)
                .accessibilityElement(children: .contain)
                .task(id: notice) {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    if store.notice == notice { store.notice = nil }
                }
            }
        }
        .alert("Couldn’t finish that", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Try again in a moment.") }
    }
}
