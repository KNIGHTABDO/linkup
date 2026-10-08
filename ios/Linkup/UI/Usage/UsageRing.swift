import SwiftUI

/// Shared usage color thresholds and formatters across Linkup usage dashboard and widgets.
enum UsageColor {
    static let warning = Color(red: 0xE8 / 255, green: 0xB0 / 255, blue: 0x4B / 255) // #E8B04B

    /// Threshold colors for utilization:
    /// - ivory < 50 %
    /// - accent < 80 %
    /// - #E8B04B < 95 %
    /// - danger ≥ 95 %
    static func thresholdColor(for utilization: Double?) -> Color {
        guard let u = utilization else { return Theme.text }
        if u >= 0.95 {
            return Theme.danger
        } else if u >= 0.80 {
            return warning
        } else if u >= 0.50 {
            return Theme.accent
        } else {
            return Theme.text
        }
    }

    /// Color for remaining quota (1.0 = 100% full, 0.0 = exhausted):
    /// - danger < 10%
    /// - warning < 25%
    /// - accent < 50%
    /// - agent color (or success) ≥ 50%
    static func quotaRemainingColor(for remaining: Double?) -> Color {
        guard let rem = remaining else { return Theme.secondaryText }
        if rem < 0.10 {
            return Theme.danger
        } else if rem < 0.25 {
            return warning
        } else if rem < 0.50 {
            return Theme.accent
        } else {
            return Theme.agentColor("agy")
        }
    }
}

/// A tiny circular progress ring (stroke 2.5) colored by the same plan utilization thresholds,
/// for the composer's model pill.
struct UsageRingBadge: View {
    let utilization: Double?
    var size: CGFloat = 18

    private var clampedUtilization: Double {
        min(max(utilization ?? 0.0, 0.0), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: CGFloat(clampedUtilization))
                .stroke(
                    UsageColor.thresholdColor(for: utilization),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: clampedUtilization)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan usage")
        .accessibilityValue(utilization.map { "\(Int(round($0 * 100))) percent used" } ?? "unknown")
    }
}

/// Watches Claude's 5-hour utilization and sets `ui.toast` when crossing 0.80 or 0.95,
/// remembered once per reset window in UserDefaults by `resetsAt`.
struct UsageAlertWatcher: ViewModifier {
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    func body(content: Content) -> some View {
        content
            .onAppear { checkAlerts() }
            .onChange(of: store.usage) { _, _ in checkAlerts() }
    }

    private func checkAlerts() {
        let fiveHour = store.usage?.claudePlan?.fiveHour ?? store.usage?.claude?.fiveHour
        guard let util = fiveHour?.utilization,
              let resetsAt = fiveHour?.resetsAt ?? store.usage?.claude?.resetsAt else { return }

        let windowKey = Int(resetsAt)
        let key80 = "linkup.usage.alert.\(windowKey).80"
        let key95 = "linkup.usage.alert.\(windowKey).95"

        if util >= 0.95 {
            if !UserDefaults.standard.bool(forKey: key95) {
                UserDefaults.standard.set(true, forKey: key80)
                UserDefaults.standard.set(true, forKey: key95)
                ui.toast = "Claude: 95 % of your 5-hour limit used"
            }
        } else if util >= 0.80 {
            if !UserDefaults.standard.bool(forKey: key80) {
                UserDefaults.standard.set(true, forKey: key80)
                ui.toast = "Claude: 80 % of your 5-hour limit used"
            }
        }
    }
}

extension View {
    func usageAlerts() -> some View {
        modifier(UsageAlertWatcher())
    }
}

/// Formats relative time ("Updated 12 s ago", "Updated 2 min ago") live with periodic updates.
struct LiveRelativeTimeText: View {
    let timestamp: Double?
    var prefix: String = "Updated "

    var body: some View {
        if let timestamp {
            TimelineView(.periodic(from: .now, by: 5)) { timeline in
                Text(formatRelative(from: Date(timeIntervalSince1970: timestamp), now: timeline.date))
            }
        }
    }

    private func formatRelative(from date: Date, now: Date) -> String {
        let diff = max(now.timeIntervalSince(date), 0)
        if diff < 5 { return "\(prefix)just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "\(prefix)\(f.localizedString(for: date, relativeTo: now))"
    }
}

/// Formats countdown time ("Resets in 2 h 14 min") live with periodic updates.
struct LiveCountdownText: View {
    let resetDate: Date?

    var body: some View {
        if let resetDate {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Text(formatCountdown(until: resetDate, now: timeline.date))
            }
        }
    }

    private func formatCountdown(until date: Date, now: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "Resets now" }
        if remaining < 60 { return "Resets in < 1 min" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = remaining >= 86400 ? [.day, .hour] : [.hour, .minute]
        f.maximumUnitCount = 2
        f.zeroFormattingBehavior = .dropAll
        return "Resets in \(f.string(from: remaining) ?? "")"
    }
}

/// Token count and currency formatting helpers.
enum UsageFormatter {
    /// Compact, locale-aware ("1.2K" / "1,2 k" / "3M").
    static func tokenCount(_ count: Int) -> String {
        if count < 1_000 { return count.formatted() }
        return count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func shortCount(_ count: Int) -> String {
        if count < 1_000 { return count.formatted() }
        return count.formatted(.number.notation(.compactName).precision(.fractionLength(0)))
    }

    static func cost(_ cost: Double) -> String {
        let digits = cost >= 0.01 ? 2 : 3
        return cost.formatted(.currency(code: "USD").precision(.fractionLength(digits)))
    }
}
