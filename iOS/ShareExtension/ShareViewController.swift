import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OutreachCore

final class ShareViewController: UIViewController {
    private let model = ShareViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.close = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        let host = UIHostingController(rootView: SharePanel(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        Task { await model.load(items: extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }
}

@MainActor
private final class ShareViewModel: ObservableObject {
    @Published var url = ""
    @Published var sharedText: String?
    @Published var title = ""
    @Published var company = ""
    @Published var isLoading = true
    @Published var isSubmitting = false
    @Published var saved = false
    @Published var message: String?
    @Published var error: String?
    var close: (() -> Void)?

    func load(items: [NSExtensionItem]) async {
        var texts: [String] = []
        var urls: [URL] = []
        for item in items {
            if let text = item.attributedTitle?.string, !text.isEmpty { texts.append(text) }
            if let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
                    if let value = value as? URL { urls.append(value) }
                    else if let value = value as? NSURL { urls.append(value as URL) }
                    else if let value = value as? String, let candidate = URL(string: value) { urls.append(candidate) }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) as? String {
                    texts.append(value)
                }
            }
        }
        let text = texts.joined(separator: "\n")
        sharedText = text.isEmpty ? nil : String(text.prefix(40_000))
        inferDetails(from: text)
        if urls.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            urls = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
        }
        var validationMessage: String?
        for candidate in urls {
            do {
                url = try OutreachValidation.normalizeJobURL(candidate.absoluteString).absoluteString
                break
            } catch {
                validationMessage = error.localizedDescription
            }
        }
        if url.isEmpty {
            self.error = validationMessage ?? "This share doesn't contain a job link. Share the job's HTTPS URL, or paste it into Relay."
        }
        if !url.isEmpty, let token = SharedCredentials.token,
           let serviceURL = URL(string: AppEnvironment.backendURL),
           let client = try? APIClient(baseURL: serviceURL, token: token),
           let details = try? await client.previewJob(ImportRequest(url: url, sharedText: sharedText, title: title, company: company)) {
            if title.isEmpty { title = details.title }
            if company.isEmpty { company = details.company }
        }
        isLoading = false
    }

    private func inferDetails(from text: String) {
        guard let expression = try? NSRegularExpression(
            pattern: "(?:check out this job at|job at)\\s+([^:\\n]{1,200}):\\s*([^\\n]{1,300})",
            options: [.caseInsensitive]
        ) else { return }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges == 3,
              let companyRange = Range(match.range(at: 1), in: text),
              let titleRange = Range(match.range(at: 2), in: text) else { return }
        company = String(text[companyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        title = String(text[titleRange])
            .replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func submit() {
        guard !isSubmitting, !saved, !url.isEmpty else { return }
        isSubmitting = true
        error = nil
        do {
            let pending = try SharedInbox.enqueue(
                url: url,
                sharedText: sharedText,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                company: company.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if SharedCredentials.token != nil && !AppEnvironment.backendURL.isEmpty {
                do {
                    try ShareUploadCoordinator.shared.submit(pending) { [weak self] accepted in
                        Task { @MainActor [weak self] in
                            self?.message = accepted
                                ? "Added to Relay. Open Jobs to see the details and outreach progress."
                                : "Saved on this iPhone. Open Relay to finish importing when your connection is available."
                        }
                    }
                    message = "Saved. The import will upload when a connection is available. Open Relay to check its progress."
                } catch {
                    message = "Saved on this iPhone. Open Relay to finish importing this job."
                }
            } else {
                message = "Saved on this iPhone. Open Relay and connect your service to prepare outreach."
            }
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

private struct SharePanel: View {
    @ObservedObject var model: ShareViewModel
    @FocusState private var editingField: String?
    @Environment(\.colorScheme) private var colorScheme
    private var ink: Color { colorScheme == .dark ? .white : Color(red: 0.11, green: 0.14, blue: 0.19) }
    private var accent: Color { Color(red: 0.35, green: 0.33, blue: 0.81) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: model.saved ? "checkmark.circle.fill" : "paperplane.fill")
                        .font(.system(size: 33, weight: .semibold)).foregroundStyle(accent)
                        .frame(width: 72, height: 72)
                        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.saved ? "A new possibility." : "Your next introduction.")
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                        Text(model.saved ? (model.message ?? "Your job is saved.") : "Bring this job into Relay and put your referral outreach in motion.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    if model.isLoading {
                        ProgressView("Reading shared job…")
                    } else if !model.url.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(URL(string: model.url)?.host ?? "Job link", systemImage: "link")
                                .font(.subheadline.weight(.semibold))
                            Text(model.url).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                        if !model.saved {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Confirm the opportunity").font(.headline)
                                TextField("Job title", text: $model.title)
                                    .focused($editingField, equals: "title")
                                    .textInputAutocapitalization(.words)
                                    .padding(14)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                TextField("Company", text: $model.company)
                                    .focused($editingField, equals: "company")
                                    .textInputAutocapitalization(.words)
                                    .padding(14)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                Text("Relay fills details from shared text and supported job boards. A bare LinkedIn link may not provide them. Missing details can be completed later in Relay; no email is sent while the role or company is missing.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Text(AppEnvironment.settingsPreview)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    Button {
                        if model.saved { model.close?() } else { model.submit() }
                    } label: {
                        HStack {
                            Text(model.saved ? "Done" : "Add job to Relay")
                            Spacer()
                            Image(systemName: model.saved ? "checkmark" : "arrow.right")
                        }
                        .font(.headline).padding(18).foregroundStyle(.white)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(
                        model.isLoading || model.isSubmitting ||
                        (!model.saved && (
                            model.url.isEmpty
                        ))
                    )
                    .opacity(!model.saved && model.url.isEmpty ? 0.5 : 1)
                }
                .padding(26)
            }
            .foregroundStyle(ink)
            .background(colorScheme == .dark ? Color(uiColor: .systemBackground) : Color(red: 0.985, green: 0.978, blue: 0.954))
            .navigationTitle("Relay")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingField = nil }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { model.close?() } } }
        }
    }
}
