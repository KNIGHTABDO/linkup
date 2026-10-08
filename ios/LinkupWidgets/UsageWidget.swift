import SwiftUI
import WidgetKit

struct UsageTimelineEntry: TimelineEntry {
    let date: Date
    /// nil = the app never synced.
    let snapshot: LinkupWidgetSnapshot?
}

struct UsageTimelineProvider: TimelineProvider {
    typealias Entry = UsageTimelineEntry

    func placeholder(in context: Context) -> UsageTimelineEntry {
        UsageTimelineEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageTimelineEntry) -> Void) {
        let snapshot = context.isPreview ? LinkupWidgetSnapshot.placeholder : LinkupWidgetSnapshot.read()
        completion(UsageTimelineEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageTimelineEntry>) -> Void) {
        let snapshot = LinkupWidgetSnapshot.read()
        let entry = UsageTimelineEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Views

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct UsageWidgetSmallView: View {
    let snapshot: LinkupWidgetSnapshot

    var body: some View {
        let fiveHour = snapshot.claudeFiveHourUtilization ?? 0
        let weekly = snapshot.claudeWeeklyUtilization ?? 0

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                SparkShape(rays: 12, phase: 0)
                    .fill(Theme.accent)
                    .frame(width: 14, height: 14)
                Text("Claude")
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    ZStack {
                        ProgressRing(progress: fiveHour, color: Theme.accent, lineWidth: 5)
                            .frame(width: 44, height: 44)
                        Text("\(Int(fiveHour * 100))%")
                            .font(Theme.sans(11, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    Text("5h")
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }

                VStack(spacing: 4) {
                    ZStack {
                        ProgressRing(progress: weekly, color: Color.linkupWarning, lineWidth: 5)
                            .frame(width: 44, height: 44)
                        Text("\(Int(weekly * 100))%")
                            .font(Theme.sans(11, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    Text("Week")
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            if let title = snapshot.lastSessionTitle, !title.isEmpty {
                HStack(spacing: 4) {
                    SparkShape(rays: 12, phase: 0)
                        .fill(Theme.agentColor(snapshot.lastSessionAgent))
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            } else if let agy = snapshot.agyCreditsText, !agy.isEmpty {
                Text(agy)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(4)
    }
}

struct UsageWidgetMediumView: View {
    let snapshot: LinkupWidgetSnapshot

    var body: some View {
        let fiveHour = snapshot.claudeFiveHourUtilization ?? 0
        let weekly = snapshot.claudeWeeklyUtilization ?? 0

        HStack(spacing: 16) {
            // Left side: Usage rings
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    SparkShape(rays: 12, phase: 0)
                        .fill(Theme.accent)
                        .frame(width: 14, height: 14)
                    Text("Claude Limits")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        ZStack {
                            ProgressRing(progress: fiveHour, color: Theme.accent, lineWidth: 6)
                                .frame(width: 46, height: 46)
                            Text("\(Int(fiveHour * 100))%")
                                .font(Theme.sans(12, weight: .bold))
                                .foregroundStyle(Theme.text)
                        }
                        Text("5-Hour")
                            .font(Theme.sans(10, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        if let reset = snapshot.claudeFiveHourReset {
                            Text(reset, style: .time)
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }

                    VStack(spacing: 4) {
                        ZStack {
                            ProgressRing(progress: weekly, color: Color.linkupWarning, lineWidth: 6)
                                .frame(width: 46, height: 46)
                            Text("\(Int(weekly * 100))%")
                                .font(Theme.sans(12, weight: .bold))
                                .foregroundStyle(Theme.text)
                        }
                        Text("Weekly")
                            .font(Theme.sans(10, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        if let reset = snapshot.claudeWeeklyReset {
                            Text(formatDay(reset))
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
            }

            Divider()
                .overlay(Theme.hairline)

            // Right side: Last session & Antigravity
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SparkShape(rays: 12, phase: 0)
                        .fill(Theme.agentColor(snapshot.lastSessionAgent))
                        .frame(width: 14, height: 14)
                    Text((snapshot.lastSessionAgent ?? "agent").capitalized)
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                Text(snapshot.lastSessionTitle ?? "No recent session")
                    .font(Theme.serif(13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                Spacer()

                if let agy = snapshot.agyCreditsText, !agy.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Antigravity")
                            .font(Theme.sans(10, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                        Text(agy)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
    }

    private func formatDay(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "E"
        return df.string(from: date)
    }
}

struct UsageWidgetAccessoryCircularView: View {
    let snapshot: LinkupWidgetSnapshot

    var body: some View {
        let util = snapshot.claudeFiveHourUtilization ?? 0
        Gauge(value: min(max(util, 0), 1)) {
            Text("5h")
                .font(.system(size: 10, weight: .bold))
        } currentValueLabel: {
            Text("\(Int(util * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

struct UsageWidgetEmptyView: View {
    var compact = false

    var body: some View {
        VStack(spacing: 6) {
            SparkShape(rays: 12, phase: 0)
                .fill(Theme.accent)
                .frame(width: 16, height: 16)
            Text("Open Linkup to sync")
                .font(Theme.sans(compact ? 10 : 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UsageWidgetEntryView: View {
    let entry: UsageTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                UsageWidgetEmptyView(compact: family == .accessoryCircular)
            }
        }
        .widgetURL(URL(string: entry.snapshot?.lastSessionId.map { "linkup://session/\($0)" } ?? "linkup://"))
        .containerBackground(Theme.background, for: .widget)
    }

    @ViewBuilder
    private func content(_ snapshot: LinkupWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        VStack(spacing: 2) {
            Group {
                switch family {
                case .systemMedium:
                    UsageWidgetMediumView(snapshot: snapshot)
                case .accessoryCircular:
                    UsageWidgetAccessoryCircularView(snapshot: snapshot)
                default:
                    UsageWidgetSmallView(snapshot: snapshot)
                }
            }
            .opacity(stale ? 0.5 : 1)
            if stale && family != .accessoryCircular {
                Text("updated \(snapshot.updatedAt, style: .relative) ago")
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
    }
}

struct UsageWidget: Widget {
    let kind: String = "UsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Linkup Usage")
        .description("Claude rate limits, Antigravity credits, and last session status.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
