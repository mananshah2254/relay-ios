import SwiftUI
import UIKit

/// Indeterminate activity: no invented percentages or simulated provider stages.
struct RelayActivityMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 3.2
            Group {
                if compact {
                    ZStack {
                        Capsule().fill(RelayTheme.accent.opacity(0.17)).frame(width: 36, height: 2)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(RelayTheme.accent)
                            .offset(x: reduceMotion ? 0 : CGFloat(sin(phase * .pi * 2)) * 17)
                    }.frame(width: 52, height: 28)
                } else {
                    ZStack {
                        Circle().stroke(RelayTheme.accent.opacity(0.10), lineWidth: 1).frame(width: 124, height: 70)
                        Circle().stroke(RelayTheme.accent.opacity(0.10), lineWidth: 1).frame(width: 84, height: 84)
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .fill(RelayTheme.wash).frame(width: 68, height: 68)
                        Image(systemName: "envelope.open.fill")
                            .font(.system(size: 27, weight: .light)).foregroundStyle(RelayTheme.accent)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 17, weight: .medium)).foregroundStyle(RelayTheme.accent)
                            .offset(x: reduceMotion ? 48 : CGFloat(cos(phase * .pi * 2)) * 62,
                                    y: reduceMotion ? -20 : CGFloat(sin(phase * .pi * 2)) * 36)
                    }.frame(width: 160, height: 110)
                }
            }
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
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.055, green: 0.075, blue: 0.11, alpha: 1) : UIColor(red: 0.975, green: 0.973, blue: 0.962, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.105, green: 0.13, blue: 0.18, alpha: 1) : .white
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.96, green: 0.97, blue: 1, alpha: 1) : UIColor(red: 0.09, green: 0.14, blue: 0.22, alpha: 1)
    })
    static let secondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.67, green: 0.72, blue: 0.78, alpha: 1) : UIColor(red: 0.42, green: 0.47, blue: 0.53, alpha: 1)
    })
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.70, green: 0.67, blue: 1, alpha: 1) : UIColor(red: 0.35, green: 0.31, blue: 0.72, alpha: 1)
    })
    static let green = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.48, green: 0.83, blue: 0.71, alpha: 1) : UIColor(red: 0.12, green: 0.47, blue: 0.36, alpha: 1)
    })
    static let amber = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.75, blue: 0.47, alpha: 1) : UIColor(red: 0.61, green: 0.34, blue: 0.10, alpha: 1)
    })
    static let line = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.09) : UIColor(red: 0.15, green: 0.19, blue: 0.28, alpha: 0.08)
    })
    static let button = Color(red: 0.34, green: 0.29, blue: 0.71)
    static let wash = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.18, green: 0.17, blue: 0.30, alpha: 1) : UIColor(red: 0.93, green: 0.92, blue: 0.98, alpha: 1)
    })
}

struct RelayCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(RelayTheme.line, lineWidth: 1))
            .shadow(color: RelayTheme.ink.opacity(0.035), radius: 16, y: 7)
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
            .background(LinearGradient(colors: [RelayTheme.button, RelayTheme.button.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .background(RelayTheme.wash.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct RelaySectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(RelayTheme.ink)
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
        case "simulated": "Simulated · not sent"
        case "draft": "Draft"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static func color(_ status: String) -> Color {
        switch status {
        case "completed", "submitted", "simulated": RelayTheme.green
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
            Text(title).font(.title3.weight(.bold)).foregroundStyle(RelayTheme.ink)
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
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
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
        .background(RelayTheme.wash, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }
}

extension View {
    func relayField() -> some View {
        self.padding(13)
            .background(RelayTheme.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(RelayTheme.line, lineWidth: 1))
    }
}
