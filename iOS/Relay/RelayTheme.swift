import SwiftUI
import UIKit

/// Indeterminate activity: no invented percentages or simulated provider stages.
struct RelayActivityMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
            ZStack {
                Capsule().fill(RelayTheme.accent.opacity(0.12)).frame(width: compact ? 36 : 100, height: 2)
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                    Spacer()
                    Image(systemName: "envelope.circle.fill")
                }
                .font(.system(size: compact ? 14 : 30, weight: .light)).foregroundStyle(RelayTheme.accent.opacity(0.4))
                Image(systemName: "paperplane.fill")
                    .font(.system(size: compact ? 12 : 22, weight: .medium)).foregroundStyle(RelayTheme.accent)
                    .offset(x: CGFloat(phase - 0.5) * (compact ? 28 : 82), y: -CGFloat(sin(phase * .pi)) * (compact ? 8 : 22))
                    .opacity(reduceMotion ? 1 : sin(phase * .pi))
            }.frame(width: compact ? 52 : 140, height: compact ? 28 : 72)
        }.accessibilityHidden(true)
    }
}

struct RelayActivityPanel: View {
    let title: String
    let detail: String
    @State private var started = Date()
    var body: some View {
        VStack(spacing: 18) {
            RelayActivityMark()
            VStack(spacing: 8) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(RelayTheme.ink)
                Text(detail).font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TimelineView(.periodic(from: started, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(started))
                Text(elapsed >= 12 ? "Still waiting for the service · \(elapsed)s" : "Waiting for a confirmed response")
                    .font(.caption).monospacedDigit().foregroundStyle(RelayTheme.secondary)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: 340)
        .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(RelayTheme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 30, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct RelayActivityOverlay: ViewModifier {
    @EnvironmentObject private var store: RelayStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .disabled(store.isBusy)
            .accessibilityHidden(store.isBusy)
            .overlay {
                if store.isBusy {
                    ZStack {
                        RelayTheme.background.opacity(0.94).ignoresSafeArea()
                        RelayActivityPanel(title: store.activityTitle, detail: store.activityDetail).padding(24)
                    }.transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isBusy)
    }
}

extension View {
    func relayActivityOverlay() -> some View { modifier(RelayActivityOverlay()) }
}

extension View {
    func relayKeyboardDismissal() -> some View {
        self.scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.fontWeight(.semibold).accessibilityLabel("Dismiss keyboard")
                }
            }
    }
}

enum RelayTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color(uiColor: UIColor { traits in
        .label
    })
    static let secondary = Color(uiColor: .secondaryLabel)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.69, blue: 1, alpha: 1) : UIColor(red: 0.0, green: 0.36, blue: 0.82, alpha: 1)
    })
    static let green = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.46, green: 0.80, blue: 0.64, alpha: 1) : UIColor(red: 0.19, green: 0.43, blue: 0.32, alpha: 1)
    })
    static let amber = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.95, green: 0.73, blue: 0.40, alpha: 1) : UIColor(red: 0.57, green: 0.36, blue: 0.09, alpha: 1)
    })
    static let line = Color.primary.opacity(0.075)
    static let button = Color(red: 0.04, green: 0.36, blue: 0.82)
}

struct RelayCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(RelayTheme.line, lineWidth: 0.5))
    }
}

struct RelayPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .foregroundStyle(.white)
            .background(RelayTheme.button.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: configuration.isPressed)
    }
}

struct RelaySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(14)
            .foregroundStyle(RelayTheme.accent)
            .background(RelayTheme.accent.opacity(configuration.isPressed ? 0.15 : 0.085), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct RelaySectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(RelayTheme.ink)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(RelayTheme.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RelayStatusPill: View {
    let status: String
    var body: some View {
        Text(RelayStatus.title(status))
            .font(.caption.weight(.semibold))
            .foregroundStyle(RelayStatus.color(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RelayStatus.color(status).opacity(0.09), in: Capsule())
            .accessibilityLabel("Status: \(RelayStatus.title(status))")
    }
}

enum RelayStatus {
    static func title(_ status: String) -> String {
        switch status {
        case "needs_details": "Needs details"
        case "researching": "Finding people"
        case "ready": "Ready to review"
        case "queued": "Queued"
        case "sending": "Submitting"
        case "completed": "Finished"
        case "partial": "Partly completed"
        case "failed": "Needs attention"
        case "canceled": "Canceled"
        case "uncertain": "Status unknown"
        case "submitted": "Submitted to Gmail"
        case "draft": "Draft"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static func color(_ status: String) -> Color {
        switch status {
        case "completed", "submitted": RelayTheme.green
        case "failed", "partial", "uncertain", "needs_details": RelayTheme.amber
        case "canceled", "draft": RelayTheme.secondary
        default: RelayTheme.accent
        }
    }
}

struct RelayEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 31, weight: .light)).foregroundStyle(RelayTheme.accent)
                .frame(width: 72, height: 72).background(RelayTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 23))
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(RelayTheme.ink)
            Text(detail).font(.subheadline).foregroundStyle(RelayTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }
}

struct RelayNotice: View {
    let text: String
    var symbol: String = "info.circle"
    var color: Color = RelayTheme.accent
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).padding(.top, 2)
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RelayAvatar: View {
    let name: String
    var symbol: String? = nil
    var body: some View {
        Group {
            if let symbol { Image(systemName: symbol).font(.title3) }
            else { Text(String(name.prefix(1)).uppercased()).font(.title3.weight(.semibold)) }
        }
        .foregroundStyle(RelayTheme.accent)
        .frame(width: 48, height: 48)
        .background(RelayTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityHidden(true)
    }
}

extension View {
    func relayField() -> some View {
        self.padding(13)
            .background(RelayTheme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(RelayTheme.line))
    }
}
