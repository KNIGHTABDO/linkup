import SwiftUI
import Charts

/// Live usage dashboard for Linkup: Claude Code plan limits, Antigravity credits & quotas,
/// Hermes tokens, per-agent historical totals with 7-day activity charts, and top sessions.
struct UsageDashboardView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Claude Plan Card
                ClaudePlanSectionView()

                // 2. Antigravity Card
                AntigravitySectionView()

                // 3. Hermes Card
                HermesSectionView()

                // 4. Per Agent Totals
                AgentsUsageSectionView()

                // 5. Top Sessions by Tokens
                TopSessionsSectionView()
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.surface.ignoresSafeArea())
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refreshCatalog(force: false)
        }
    }
}

// MARK: - 1. Claude Plan

private struct ClaudePlanSectionView: View {
    @Environment(SessionStore.self) private var store

    private var plan: ClaudePlanUsage? {
        store.usage?.claudePlan
    }

    private var fallbackRateLimit: ClaudeRateLimit? {
        if let live = store.usage?.claude { return live }
        // Fallback to fixture ratelimit in demo / screenshot test mode
        if let url = Bundle.main.url(forResource: "screenshot-fixture", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONDecoder().decode([String: JSONValue].self, from: data),
           let eventsBySession = json["events"]?.object {
            for (_, events) in eventsBySession {
                for event in (events.array ?? []).reversed() {
                    if event["type"]?.string == "ratelimit" {
                        if let rawData = try? JSONEncoder().encode(event),
                           let rl = try? JSONDecoder().decode(ClaudeRateLimit.self, from: rawData) {
                            return rl
                        }
                    }
                }
            }
        }
        return nil
    }

    private var subscriptionLabel: String? {
        if let sub = plan?.subscription, !sub.isEmpty { return sub }
        return store.agent("claude")?.accountLabel
    }

    private var updatedAt: Double? {
        plan?.at ?? fallbackRateLimit?.at
    }

    private var fiveHourWindow: RateLimitWindow? {
        plan?.fiveHour ?? fallbackRateLimit?.fiveHour
    }

    private var sevenDayWindow: RateLimitWindow? {
        plan?.sevenDay ?? fallbackRateLimit?.sevenDay
    }

    private var opusWindow: RateLimitWindow? {
        plan?.sevenDayOpus
    }

    private var sonnetWindow: RateLimitWindow? {
        plan?.sevenDaySonnet
    }

    private var hasRings: Bool {
        fiveHourWindow != nil || sevenDayWindow != nil || opusWindow != nil || sonnetWindow != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                AgentLogo(agent: "claude", size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Claude Plan")
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.text)

                        if let sub = subscriptionLabel, !sub.isEmpty {
                            Text(sub)
                                .font(Theme.sans(11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Theme.accent.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    if let at = updatedAt {
                        LiveRelativeTimeText(timestamp: at)
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Spacer()
            }

            if hasRings {
                // 2x2 grid of rings
                let columns = [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    if let fiveHour = fiveHourWindow {
                        ClaudeRingItemView(title: "5-hour session", window: fiveHour)
                    }
                    if let sevenDay = sevenDayWindow {
                        ClaudeRingItemView(title: "Weekly", window: sevenDay)
                    }
                    if let opus = opusWindow {
                        ClaudeRingItemView(title: "Weekly · Opus", window: opus)
                    }
                    if let sonnet = sonnetWindow {
                        ClaudeRingItemView(title: "Weekly · Sonnet", window: sonnet)
                    }
                }
                .padding(.top, 4)
            } else {
                Text("Claude plan usage appears after the bridge\u{2019}s next check or after running Claude Code.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
    }
}

private struct ClaudeRingItemView: View {
    let title: String
    let window: RateLimitWindow

    private var clampedUtilization: Double {
        min(max(window.utilization ?? 0.0, 0.0), 1.0)
    }

    private var ringColor: Color {
        UsageColor.thresholdColor(for: window.utilization)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.hairline.opacity(1.8), lineWidth: 8)
                    .frame(width: 82, height: 82)

                Circle()
                    .trim(from: 0, to: CGFloat(clampedUtilization))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 82, height: 82)
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: clampedUtilization)

                Text("\(Int(round(clampedUtilization * 100)))%")
                    .font(Theme.sans(18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
            }
            .padding(.top, 4)

            VStack(spacing: 3) {
                Text(title)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let resetDate = window.resetDate {
                    LiveCountdownText(resetDate: resetDate)
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 2. Antigravity

private struct AntigravitySectionView: View {
    @Environment(SessionStore.self) private var store

    private var agy: AgyUsage? {
        store.usage?.agy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                AgentLogo(agent: "agy", size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Antigravity")
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.text)

                        if let status = agy?.status, !status.isEmpty {
                            Text(status.capitalized)
                                .font(Theme.sans(11, weight: .semibold))
                                .foregroundStyle(Theme.agentColor("agy"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Theme.agentColor("agy").opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    if let at = agy?.at {
                        LiveRelativeTimeText(timestamp: at)
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Spacer()
            }

            if let agy {
                // Credits text exactly as reported
                if let credits = agy.credits, !credits.isEmpty {
                    let isDanger = credits.localizedCaseInsensitiveContains("out of")
                        || credits.hasPrefix("0 ")
                        || credits.hasPrefix("0%")
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Credits")
                                .font(Theme.sans(12, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)

                            Text(credits)
                                .font(Theme.sans(20, weight: .bold))
                                .foregroundStyle(isDanger ? Theme.danger : Theme.text)
                                .contentTransition(.numericText())
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                }

                // Per-model quota bars when models non-empty
                if let models = agy.models, !models.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().overlay(Theme.hairline)

                        Text("Model Quotas")
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)

                        ForEach(models) { quota in
                            AntigravityModelQuotaRow(quota: quota)
                        }
                    }
                }
            } else {
                Text("Antigravity usage appears after the bridge\u{2019}s next check")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
    }
}

private struct AntigravityModelQuotaRow: View {
    let quota: AgyModelQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.name)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.text)

                Spacer()

                if let rem = quota.remaining {
                    Text("\(Int(round(rem * 100)))% remaining")
                        .font(Theme.mono(12))
                        .foregroundStyle(UsageColor.quotaRemainingColor(for: rem))
                        .contentTransition(.numericText())
                }
            }

            if let rem = quota.remaining {
                let clamped = min(max(rem, 0.0), 1.0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(UsageColor.quotaRemainingColor(for: rem))
                            .frame(width: max(geo.size.width * CGFloat(clamped), 4), height: 6)
                            .animation(.smooth, value: clamped)
                    }
                }
                .frame(height: 6)
            }

            if let resetsAt = quota.resetsAt {
                let resetDate = Date(timeIntervalSince1970: resetsAt)
                LiveCountdownText(resetDate: resetDate)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - 3. Hermes

private struct HermesSectionView: View {
    @Environment(SessionStore.self) private var store

    private var hermesTotals: AgentTotals? {
        if let totals = store.usage?.totals?["hermes"] {
            return totals
        }
        // Fallback from sessions if totals dict is missing
        var inTok = 0
        var outTok = 0
        var cost = 0.0
        var count = 0
        for s in store.sessions where s.agent == "hermes" {
            let u = s.usage
            inTok += (u?.inputTokens ?? 0) + (u?.cacheRead ?? 0) + (u?.cacheWrite ?? 0)
            outTok += u?.outputTokens ?? 0
            cost += u?.costUsd ?? 0.0
            count += 1
        }
        if count > 0 || inTok > 0 || outTok > 0 {
            return AgentTotals(inputTokens: inTok, outputTokens: outTok, costUsd: cost, sessions: count)
        }
        return nil
    }

    private var isHermesRegistered: Bool {
        store.agent("hermes") != nil || hermesTotals != nil
    }

    var body: some View {
        if isHermesRegistered {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    AgentLogo(agent: "hermes", size: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hermes")
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.text)

                        Text("Local runner (127.0.0.1:8642)")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer()

                    if let totals = hermesTotals {
                        let total = totals.inputTokens + totals.outputTokens
                        Text(UsageFormatter.tokenCount(total))
                            .font(Theme.mono(15).weight(.semibold))
                            .foregroundStyle(Theme.agentColor("hermes"))
                            .contentTransition(.numericText())
                    }
                }

                if let totals = hermesTotals {
                    HStack(spacing: 0) {
                        statColumn(label: "Input tokens", value: UsageFormatter.tokenCount(totals.inputTokens))
                        Divider()
                            .frame(height: 26)
                            .overlay(Theme.hairline)
                        statColumn(label: "Output tokens", value: UsageFormatter.tokenCount(totals.outputTokens))
                        Divider()
                            .frame(height: 26)
                            .overlay(Theme.hairline)
                        statColumn(label: "Sessions", value: "\(totals.sessions)")
                    }
                    .padding(.top, 2)
                } else {
                    Text("No local Hermes tokens recorded yet.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 2)
                }
            }
            .padding(16)
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.sans(16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 4. Per Agent Totals & 7-Day Charts

private struct AgentsUsageSectionView: View {
    @Environment(SessionStore.self) private var store

    private var resolvedTotals: [String: AgentTotals] {
        if let totals = store.usage?.totals, !totals.isEmpty {
            return totals
        }
        var totals: [String: AgentTotals] = [:]
        for s in store.sessions {
            let u = s.usage
            let existing = totals[s.agent] ?? AgentTotals(inputTokens: 0, outputTokens: 0, costUsd: 0.0, sessions: 0)
            let inTok = (u?.inputTokens ?? 0) + (u?.cacheRead ?? 0) + (u?.cacheWrite ?? 0)
            let outTok = u?.outputTokens ?? 0
            let cost = u?.costUsd ?? 0.0
            totals[s.agent] = AgentTotals(
                inputTokens: existing.inputTokens + inTok,
                outputTokens: existing.outputTokens + outTok,
                costUsd: round((existing.costUsd + cost) * 10000) / 10000,
                sessions: existing.sessions + 1
            )
        }
        return totals
    }

    private var resolvedAgentIds: [String] {
        var ids: [String] = []
        let knownOrder = ["claude", "agy", "hermes"]
        for id in knownOrder {
            if resolvedTotals[id] != nil || store.agent(id) != nil {
                ids.append(id)
            }
        }
        for id in resolvedTotals.keys.sorted() {
            if !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agents")
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 4)

            if resolvedAgentIds.isEmpty {
                Text("No agent usage recorded yet.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            } else {
                ForEach(resolvedAgentIds, id: \.self) { agentId in
                    if let totals = resolvedTotals[agentId] {
                        AgentUsageCard(
                            agentId: agentId,
                            name: store.agent(agentId)?.name ?? AgentKind(rawValue: agentId)?.title ?? agentId.capitalized,
                            totals: totals,
                            sessions: store.sessions
                        )
                    }
                }
            }
        }
    }
}

private struct AgentUsageCard: View {
    let agentId: String
    let name: String
    let totals: AgentTotals
    let sessions: [SessionInfo]

    private var dailyUsage: [DailyTokens] {
        UsageDashboardView.computeLast7DaysTokens(for: agentId, sessions: sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                AgentLogo(agent: agentId, size: 24)

                Text(name)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Spacer()

                if totals.costUsd > 0 {
                    Text(UsageFormatter.cost(totals.costUsd))
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.secondaryText)
                        .contentTransition(.numericText())
                }
            }

            // Stat columns
            HStack(spacing: 0) {
                statColumn(label: "Input tokens", value: UsageFormatter.tokenCount(totals.inputTokens))
                Divider()
                    .frame(height: 26)
                    .overlay(Theme.hairline)
                statColumn(label: "Output tokens", value: UsageFormatter.tokenCount(totals.outputTokens))
                Divider()
                    .frame(height: 26)
                    .overlay(Theme.hairline)
                statColumn(label: "Sessions", value: "\(totals.sessions)")
            }

            // 7-day Swift Charts bar chart
            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last 7 days · by last activity")
                        .font(Theme.sans(11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)

                    Spacer()

                    let weekTotal = dailyUsage.reduce(0) { $0 + $1.tokens }
                    if weekTotal > 0 {
                        Text("\(UsageFormatter.tokenCount(weekTotal)) tokens")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.tertiaryText)
                            .contentTransition(.numericText())
                    }
                }

                Chart(dailyUsage) { day in
                    BarMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Tokens", day.tokens)
                    )
                    .foregroundStyle(Theme.agentColor(agentId))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(Theme.sans(10))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text(UsageFormatter.shortCount(count))
                                    .font(Theme.mono(9))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0 ... max(dailyUsage.map(\.tokens).max() ?? 0, 100))
                .frame(height: 72)
            }
        }
        .padding(14)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.sans(16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 5. Top Sessions by Tokens

private struct TopSessionsSectionView: View {
    @Environment(SessionStore.self) private var store

    private var topSessions: [SessionInfo] {
        store.sessions
            .map { ($0, sessionTotalTokens($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0.0 }
    }

    private func sessionTotalTokens(_ session: SessionInfo) -> Int {
        guard let u = session.usage else { return 0 }
        return (u.inputTokens ?? 0) + (u.cacheRead ?? 0) + (u.cacheWrite ?? 0) + (u.outputTokens ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Sessions by Tokens")
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 4)

            if topSessions.isEmpty {
                Text("No session token data yet.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topSessions.enumerated()), id: \.element.id) { index, session in
                        HStack(spacing: 12) {
                            AgentLogo(agent: session.agent, size: 24)

                            Text(session.displayTitle)
                                .font(Theme.sans(14, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)

                            Spacer()

                            Text(UsageFormatter.tokenCount(sessionTotalTokens(session)))
                                .font(Theme.mono(13))
                                .foregroundStyle(Theme.secondaryText)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if index < topSessions.count - 1 {
                            Divider()
                                .overlay(Theme.hairline)
                                .padding(.leading, 50)
                        }
                    }
                }
                .background(Theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }
}

// MARK: - Daily Tokens Model & Bucket Calculation

struct DailyTokens: Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    let dayLabel: String
    var tokens: Int
}

extension UsageDashboardView {
    /// Buckets each session's total tokens by its `updated` day for the last 7 days.
    static func computeLast7DaysTokens(for agentId: String, sessions: [SessionInfo]) -> [DailyTokens] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale.current
        dayFormatter.dateFormat = "EEE" // e.g. "Mon"

        let keyFormatter = DateFormatter()
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.dateFormat = "yyyy-MM-dd"

        var buckets: [DailyTokens] = []
        for dayOffset in (0...6).reversed() {
            if let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday) {
                let key = keyFormatter.string(from: dayDate)
                let label = dayFormatter.string(from: dayDate)
                buckets.append(DailyTokens(dayKey: key, date: dayDate, dayLabel: label, tokens: 0))
            }
        }

        for session in sessions where session.agent == agentId {
            guard let u = session.usage else { continue }
            let total = (u.inputTokens ?? 0) + (u.cacheRead ?? 0) + (u.cacheWrite ?? 0) + (u.outputTokens ?? 0)
            guard total > 0 else { continue }

            let sessionDay = calendar.startOfDay(for: session.updatedDate)
            let sessionKey = keyFormatter.string(from: sessionDay)

            if let index = buckets.firstIndex(where: { $0.dayKey == sessionKey }) {
                buckets[index].tokens += total
            }
        }

        return buckets
    }
}
