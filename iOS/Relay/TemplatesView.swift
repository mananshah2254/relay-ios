import OutreachCore
import SwiftUI
import UniformTypeIdentifiers

struct TemplatesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var templateSelection
    @EnvironmentObject private var store: RelayStore
    @State private var showPreview = false
    @State private var showDiscard = false
    private let placeholders = ["{{first_name}}", "{{company}}", "{{job_title}}", "{{job_url}}", "{{sender_name}}"]

    var body: some View {
        NavigationStack {
            List {
                    if !store.isConnected && !store.isDemo {
                        RelayNotice(text: "Connect your Relay service in Settings to save a template. You can explore a sample first.")
                    }
                    Section {
                        TextField("Your full name", text: $store.settings.senderName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel("Sender name")
                    } header: { Text("Sender name") } footer: {
                        Text("The name used in your email introduction and signature. Enter it here, then tap Save at the top right before finding contacts.")
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(RoleTemplate.roles, id: \.self) { role in
                                    Button {
                                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.settings.selectTemplate(role) }
                                    } label: {
                                        Text(RoleTemplate.name(role)).font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .foregroundStyle((store.settings.selectedTemplate ?? "general") == role ? Color.white : RelayTheme.accent)
                                            .background {
                                                if (store.settings.selectedTemplate ?? "general") == role {
                                                    RoundedRectangle(cornerRadius: 12).fill(RelayTheme.button)
                                                        .matchedGeometryEffect(id: "selectedTemplate", in: templateSelection)
                                                } else { RoundedRectangle(cornerRadius: 12).fill(RelayTheme.accent.opacity(0.07)) }
                                            }
                                    }.buttonStyle(.plain)
                                    .accessibilityAddTraits((store.settings.selectedTemplate ?? "general") == role ? .isSelected : [])
                                }
                            }
                        }
                    } header: { Text("Choose a role") } footer: { Text("Each role keeps its own wording. Save your selection before adding a job.") }
                    Section("Subject") {
                        TextField("Email subject", text: $store.settings.subjectTemplate, axis: .vertical).lineLimit(2...4).accessibilityLabel("Email subject")
                    }
                    Section {
                        TextEditor(text: $store.settings.bodyTemplate).frame(minHeight: 260).scrollContentBackground(.hidden).accessibilityLabel("Email message template")
                    } header: { Text("Message") } footer: { Text("Personalize this with your real experience. Existing drafts keep their original wording.") }
                    Section {
                        DisclosureGroup("Insert a personal detail") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 9) {
                                ForEach(placeholders, id: \.self) { placeholder in
                                    Button {
                                        store.settings.bodyTemplate += (store.settings.bodyTemplate.hasSuffix(" ") || store.settings.bodyTemplate.hasSuffix("\n") ? "" : " ") + placeholder
                                    } label: {
                                        Text(placeholder).font(.caption.monospaced()).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                            .foregroundStyle(RelayTheme.accent).background(RelayTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Section { ResumeCard().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                    Section { Button { showPreview = true } label: { Label("Preview sample email", systemImage: "eye") } }
                    if store.hasUnsavedSettings {
                        Section { Button("Discard unsaved changes", role: .destructive) { showDiscard = true } }
                    }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(RelayTheme.background)
            .navigationTitle("Templates").navigationBarTitleDisplayMode(.large)
            .relayKeyboardDismissal()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { _ = await store.saveSettings() } }
                        .disabled(store.isBusy || (!store.isConnected && !store.isDemo) || !store.hasUnsavedSettings)
                }
            }
            .sheet(isPresented: $showPreview) { TemplatePreviewSheet(settings: store.settings) }
            .confirmationDialog("Discard your unsaved template and preference changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { store.discardSettingsChanges() }
                Button("Keep editing", role: .cancel) {}
            }
        }
    }
}

struct ResumeCard: View {
    @EnvironmentObject private var store: RelayStore
    @State private var showImporter = false
    @State private var showRemove = false

    var body: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    RelayAvatar(name: "", symbol: "doc.richtext")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your résumé").font(.headline)
                        Text("A PDF, ready when you need it.").font(.footnote).foregroundStyle(RelayTheme.secondary)
                    }
                }
                if let resume = store.resume {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.fill").foregroundStyle(RelayTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resume.filename).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(resume.byteCount), countStyle: .file)).font(.caption).foregroundStyle(RelayTheme.secondary)
                        }
                        Spacer(minLength: 0)
                        Button { showRemove = true } label: { Image(systemName: "trash").padding(5) }
                            .foregroundStyle(RelayTheme.secondary).accessibilityLabel("Remove saved résumé").disabled(store.isBusy)
                    }
                    Toggle("Attach to new outreach", isOn: $store.settings.attachResume).font(.subheadline)
                } else {
                    Text("Optional. Add a PDF from Files and choose whether it accompanies new outreach.").font(.footnote).foregroundStyle(RelayTheme.secondary)
                }
                Button(store.resume == nil ? "Choose a PDF" : "Replace résumé") { showImporter = true }
                    .buttonStyle(RelaySecondaryButtonStyle()).disabled((!store.isConnected && !store.isDemo) || store.isBusy)
                if store.isDemo { Text("Practice attachments stay in memory. No PDF is uploaded or emailed.").font(.footnote).foregroundStyle(RelayTheme.secondary) }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { _ = await store.uploadResume(url: url) } }
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Remove your saved résumé?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove résumé", role: .destructive) { Task { await store.deleteResume() } }
            Button("Keep résumé", role: .cancel) {}
        } message: { Text("This removes the file used for future outreach.") }
    }
}

private struct TemplatePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let settings: OutreachSettings
    private var sampleValues: [String: String] {
        ["first_name": "Jordan", "company": "Example Studio", "job_title": "Product Designer", "job_url": "https://example.com/careers/designer", "sender_name": settings.senderName.isEmpty ? "Your name" : settings.senderName]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RelayNotice(text: "Preview using fictional people and a sample job. This does not send an email.", symbol: "sparkle.magnifyingglass")
                    RelayCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("To: Jordan · jordan@example.com").font(.footnote).foregroundStyle(RelayTheme.secondary)
                            Divider()
                            Text(render(settings.subjectTemplate)).font(.headline)
                            Text(render(settings.bodyTemplate)).font(.body).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                            if settings.attachResume {
                                Divider()
                                Label("Saved résumé will be included in new outreach", systemImage: "paperclip").font(.footnote).foregroundStyle(RelayTheme.secondary)
                            }
                        }.textSelection(.enabled)
                    }
                }.padding(20)
            }
            .background(RelayTheme.background)
            .navigationTitle("Sample email").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func render(_ template: String) -> String {
        do { return try OutreachValidation.render(template: template, values: sampleValues) }
        catch { return "Template needs attention: \(error.localizedDescription)" }
    }
}
