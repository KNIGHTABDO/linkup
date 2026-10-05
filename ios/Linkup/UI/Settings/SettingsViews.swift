import SwiftUI
import UIKit
#if canImport(VisionKit) && canImport(Vision)
import VisionKit
import Vision
#endif

// MARK: - ConnectView

/// Pair with the bridge on the PC via camera QR code scan, pasted pairing link, or manual address and token.
struct ConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionSettings.self) private var settings
    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui

    @State private var isShowingScannerSheet = false
    @State private var isManualExpanded = false
    @State private var manualURL = ""
    @State private var manualToken = ""
    @State private var hasCopiedCommand = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Top close button when already configured
                if settings.isConfigured {
                    HStack {
                        Spacer()
                        Button {
                            ui.isShowingConnect = false
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                        .clipShape(Circle())
                    }
                }

                // Header: Big animated spark and serif greeting
                VStack(spacing: 16) {
                    SparkView(size: 56, animating: true)
                        .padding(.top, settings.isConfigured ? 0 : 20)

                    Text("Link up your agents")
                        .font(Theme.serif(30, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        Text("Run `python -m linkup_bridge pair` on your PC and scan the code.")
                            .font(Theme.sans(16))
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Text("python -m linkup_bridge pair")
                                .font(Theme.mono(13))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = "python -m linkup_bridge pair"
                                hasCopiedCommand = true
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    hasCopiedCommand = false
                                }
                            } label: {
                                Image(systemName: hasCopiedCommand ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(hasCopiedCommand ? Theme.success : Theme.secondaryText)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy pairing command")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
                    }
                    .padding(.horizontal, 8)
                }

                // Primary actions: Scan QR & Paste link
                VStack(spacing: 12) {
                    Button {
                        isShowingScannerSheet = true
                    } label: {
                        Label("Scan pairing code", systemImage: "qrcode.viewfinder")
                            .font(Theme.sans(16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)

                    Button {
                        pastePairingLink()
                    } label: {
                        Label("Paste link", systemImage: "doc.on.clipboard")
                            .font(Theme.sans(15, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                }

                // Manual section
                DisclosureGroup("Enter manually", isExpanded: $isManualExpanded) {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server URL")
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)

                            TextField("https://your-pc.tailnet.ts.net", text: $manualURL)
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Token")
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)

                            SecureField("Token", text: $manualToken)
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
                        }

                        Button {
                            settings.serverURL = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            settings.token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
                            client.connect()
                        } label: {
                            Text("Connect")
                                .font(Theme.sans(15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .disabled(manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        HStack(spacing: 8) {
                            if client.state == .connected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.success)
                            } else {
                                Circle()
                                    .fill(statusDotColor(client.state))
                                    .frame(width: 8, height: 8)
                            }

                            Text(client.state.label)
                                .font(Theme.sans(14))
                                .foregroundStyle(client.state == .connected ? Theme.success : Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .padding(.top, 12)
                }
                .font(Theme.sans(15, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            manualURL = settings.serverURL
            manualToken = settings.token
        }
        .onChange(of: client.state) { _, newState in
            if newState == .connected {
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    ui.isShowingConnect = false
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isShowingScannerSheet) {
            SettingsQRScannerSheet { url in
                applyAndConnect(url: url)
            }
        }
    }

    private func pastePairingLink() {
        var candidateURL = UIPasteboard.general.url
        if candidateURL == nil, let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if text.hasPrefix("linkup://") {
                candidateURL = URL(string: text)
            } else if let range = text.range(of: "linkup://pair?") {
                let substring = String(text[range.lowerBound...])
                let firstWord = substring.components(separatedBy: .whitespacesAndNewlines).first ?? substring
                candidateURL = URL(string: firstWord)
            } else {
                candidateURL = URL(string: text)
            }
        }

        if let url = candidateURL, applyAndConnect(url: url) {
            // Handled
        } else {
            ui.toast = "Clipboard does not contain a valid Linkup pairing link"
        }
    }

    @discardableResult
    private func applyAndConnect(url: URL) -> Bool {
        if settings.apply(pairingLink: url) {
            client.connect()
            isShowingScannerSheet = false
            ui.isShowingConnect = false
            dismiss()
            return true
        }
        return false
    }

    private func statusDotColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected: return Theme.success
        case .connecting: return Theme.accent
        case .offline: return Theme.danger
        case .notConfigured: return Theme.tertiaryText
        }
    }
}

// MARK: - SettingsView

/// Settings sheet: connection management, agents catalog, usage link, and bridge version info.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionSettings.self) private var settings
    @Environment(LinkupClient.self) private var client
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var isRefreshingAgents = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var bridgeStatusText: String {
        if let name = client.serverName, !name.isEmpty {
            return "Bridge on \(name)"
        } else if client.state == .connected {
            return "Bridge on PC"
        } else {
            return "Not connected"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section: Connection
                Section("Connection") {
                    HStack {
                        Text("Server")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(settings.serverURL.isEmpty ? "Not configured" : settings.serverURL)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .listRowBackground(Theme.elevated)

                    HStack {
                        Text("Status")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusDotColor(client.state))
                                .frame(width: 8, height: 8)
                            Text(client.state.label)
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.secondaryText)
                            if client.state == .connected, let latency = client.latencyMs {
                                Text("(\(latency) ms)")
                                    .font(Theme.mono(12))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }
                    }
                    .listRowBackground(Theme.elevated)

                    Button {
                        client.connect()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                    }
                    .listRowBackground(Theme.elevated)

                    Button {
                        ui.isShowingConnect = true
                    } label: {
                        Label("Pair again", systemImage: "qrcode")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                    }
                    .listRowBackground(Theme.elevated)

                    Button(role: .destructive) {
                        client.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "bolt.slash")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.danger)
                    }
                    .disabled(client.state == .notConfigured)
                    .listRowBackground(Theme.elevated)
                }

                // Section: Agents
                Section("Agents") {
                    if store.agents.isEmpty {
                        Text("No agents registered")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.secondaryText)
                            .listRowBackground(Theme.elevated)
                    } else {
                        ForEach(store.agents) { agent in
                            SettingsAgentRow(agent: agent)
                                .listRowBackground(Theme.elevated)
                        }
                    }

                    Button {
                        Task {
                            isRefreshingAgents = true
                            await store.refreshCatalog(force: true)
                            isRefreshingAgents = false
                        }
                    } label: {
                        HStack {
                            Label("Refresh agents", systemImage: "arrow.triangle.2.circlepath")
                                .font(Theme.sans(15))
                                .foregroundStyle(Theme.accent)
                            if isRefreshingAgents {
                                Spacer()
                                ProgressView()
                                    .tint(Theme.accent)
                            }
                        }
                    }
                    .disabled(isRefreshingAgents)
                    .listRowBackground(Theme.elevated)
                }

                // Section: Usage
                Section {
                    NavigationLink {
                        UsageView(showsNavigationContainer: false)
                    } label: {
                        Label("Usage", systemImage: "chart.bar.xaxis")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                    }
                    .listRowBackground(Theme.elevated)
                }

                // Section: About
                Section("About") {
                    HStack {
                        Text("App Version")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(appVersion)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .listRowBackground(Theme.elevated)

                    HStack {
                        Text("Bridge")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(bridgeStatusText)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .listRowBackground(Theme.elevated)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        ui.isShowingSettings = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .clipShape(Circle())
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surface)
    }

    private func statusDotColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected: return Theme.success
        case .connecting: return Theme.accent
        case .offline: return Theme.danger
        case .notConfigured: return Theme.tertiaryText
        }
    }
}

// MARK: - UsageView

/// Claude 5-hour / 7-day plan limits, per-agent token totals, and highest-usage sessions.
struct UsageView: View {
    var showsNavigationContainer: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        if showsNavigationContainer {
            NavigationStack {
                UsageContent()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            closeButton
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.surface)
        } else {
            UsageContent()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        closeButton
                    }
                }
        }
    }

    private var closeButton: some View {
        Button {
            ui.isShowingUsage = false
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
    }
}

/// Main scrollable dashboard content for UsageView.
private struct UsageContent: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Claude Plan Card
                if let claude = resolvedClaudeRateLimit, (claude.fiveHour != nil || claude.sevenDay != nil) {
                    SettingsClaudePlanCard(claude: claude, accountLabel: store.agent("claude")?.accountLabel)
                } else {
                    SettingsClaudeNoUsageCard(accountLabel: store.agent("claude")?.accountLabel)
                }

                // 2. Per-Agent Usage Cards
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
                                SettingsAgentUsageCard(
                                    agentId: agentId,
                                    name: store.agent(agentId)?.name ?? AgentKind(rawValue: agentId)?.title ?? agentId.capitalized,
                                    totals: totals
                                )
                            }
                        }
                    }
                }

                // 3. Top Sessions by Tokens
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
                                    Image(systemName: AgentKind(rawValue: session.agent)?.symbol ?? "cpu")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Theme.agentColor(session.agent))
                                        .frame(width: 28, height: 28)
                                        .background(Theme.agentColor(session.agent).opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                    Text(session.displayTitle)
                                        .font(Theme.sans(14, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(formatTokenCount(sessionTotalTokens(session)))
                                        .font(Theme.mono(13))
                                        .foregroundStyle(Theme.secondaryText)
                                        .contentTransition(.numericText())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                if index < topSessions.count - 1 {
                                    Divider()
                                        .overlay(Theme.hairline)
                                        .padding(.leading, 54)
                                }
                            }
                        }
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                    }
                }
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

    /// Claude rate limit: from live store.usage, or fallback from screenshot-fixture in demo mode.
    private var resolvedClaudeRateLimit: ClaudeRateLimit? {
        if let live = store.usage?.claude { return live }
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

    /// Per-agent totals: from live store.usage.totals, or computed from store.sessions.
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

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000.0
            let formatted = String(format: "%.1f", value)
            return formatted.hasSuffix(".0") ? "\(Int(value))M" : "\(formatted)M"
        } else if count >= 1_000 {
            let value = Double(count) / 1_000.0
            let formatted = String(format: "%.1f", value)
            return formatted.hasSuffix(".0") ? "\(Int(value))k" : "\(formatted)k"
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Subviews & Cards

private struct SettingsAgentRow: View {
    let agent: AgentInfo

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: AgentKind(rawValue: agent.id)?.symbol ?? "cpu")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.agentColor(agent.id))
                .frame(width: 28, height: 28)
                .background(Theme.agentColor(agent.id).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(Theme.sans(15, weight: .medium))
                        .foregroundStyle(Theme.text)

                    if let account = agent.accountLabel, !account.isEmpty {
                        Text(account)
                            .font(Theme.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(agent.available ? Theme.success : Theme.danger)
                            .frame(width: 6, height: 6)
                        Text(agent.available ? "Available" : (agent.error ?? "Unavailable"))
                            .font(Theme.sans(12))
                            .foregroundStyle(agent.available ? Theme.secondaryText : Theme.danger)
                            .lineLimit(1)
                    }

                    if let models = agent.models, !models.isEmpty {
                        Text("•")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.tertiaryText)
                        Text("\(models.count) \(models.count == 1 ? "model" : "models")")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SettingsClaudePlanCard: View {
    let claude: ClaudeRateLimit
    let accountLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "asterisk")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)

                Text("Claude Plan")
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)

                if let account = accountLabel, !account.isEmpty {
                    Text(account)
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(claudeStatusColor(claude.status))
                        .frame(width: 7, height: 7)
                    Text(claudeStatusText(claude.status))
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(claudeStatusColor(claude.status))
                }
            }

            HStack(spacing: 20) {
                let fiveHourUtil = claude.fiveHour?.utilization ?? 0.0
                SettingsUsageRing(
                    title: "Current session",
                    utilization: fiveHourUtil,
                    resetText: formatResetTime(until: claude.fiveHour?.resetDate, defaultText: "Resets in 2 h 14 min")
                )

                let sevenDayUtil = claude.sevenDay?.utilization ?? 0.0
                SettingsUsageRing(
                    title: "Weekly",
                    utilization: sevenDayUtil,
                    resetText: formatResetTime(until: claude.sevenDay?.resetDate, defaultText: "Resets in 3 d 16 h")
                )
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
    }

    private func claudeStatusText(_ status: String?) -> String {
        switch status {
        case "allowed": return "Allowed"
        case "allowed_warning": return "Close to the limit"
        case "rejected": return "Limit reached"
        case .some(let s): return s.replacingOccurrences(of: "_", with: " ").capitalized
        case .none: return "Active"
        }
    }

    private func claudeStatusColor(_ status: String?) -> Color {
        switch status {
        case "allowed": return Theme.success
        case "allowed_warning": return Theme.accent
        case "rejected": return Theme.danger
        default: return Theme.secondaryText
        }
    }

    private func formatResetTime(until date: Date?, defaultText: String) -> String {
        guard let date else { return defaultText }
        let remaining = date.timeIntervalSinceNow
        if remaining > 0 {
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            if hours > 24 {
                let days = hours / 24
                let remHours = hours % 24
                return "Resets in \(days) d \(remHours) h"
            } else if hours > 0 {
                return "Resets in \(hours) h \(minutes) min"
            } else if minutes > 0 {
                return "Resets in \(minutes) min"
            } else {
                return "Resets in < 1 min"
            }
        }
        return defaultText
    }
}

private struct SettingsClaudeNoUsageCard: View {
    let accountLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "asterisk")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("Claude Plan")
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let account = accountLabel, !account.isEmpty {
                    Text(account)
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Text("Send a message with Claude Code to see your plan usage.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
    }
}

private struct SettingsUsageRing: View {
    let title: String
    let utilization: Double // 0...1
    let resetText: String?

    private var ringColor: Color {
        if utilization >= 0.95 {
            return Theme.danger
        } else if utilization >= 0.80 {
            return Theme.accent
        } else {
            return Theme.success
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.hairline.opacity(1.8), lineWidth: 8)
                    .frame(width: 82, height: 82)

                Circle()
                    .trim(from: 0, to: CGFloat(min(max(utilization, 0.0), 1.0)))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 82, height: 82)
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: utilization)

                Text("\(Int(round(utilization * 100)))%")
                    .font(Theme.sans(18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
            }
            .padding(.top, 4)

            Text(title)
                .font(Theme.sans(13, weight: .medium))
                .foregroundStyle(Theme.text)

            if let reset = resetText {
                Text(reset)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsAgentUsageCard: View {
    let agentId: String
    let name: String
    let totals: AgentTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: AgentKind(rawValue: agentId)?.symbol ?? "cpu")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.agentColor(agentId))
                    .frame(width: 26, height: 26)
                    .background(Theme.agentColor(agentId).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(name)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Spacer()

                if totals.costUsd > 0 {
                    Text(formatCost(totals.costUsd))
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.secondaryText)
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 0) {
                statColumn(label: "Input tokens", value: formatTokenCount(totals.inputTokens))
                Divider()
                    .frame(height: 26)
                    .overlay(Theme.hairline)
                statColumn(label: "Output tokens", value: formatTokenCount(totals.outputTokens))
                Divider()
                    .frame(height: 26)
                    .overlay(Theme.hairline)
                statColumn(label: "Sessions", value: "\(totals.sessions)")
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

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let value = Double(count) / 1_000_000.0
            let formatted = String(format: "%.1f", value)
            return formatted.hasSuffix(".0") ? "\(Int(value))M" : "\(formatted)M"
        } else if count >= 1_000 {
            let value = Double(count) / 1_000.0
            let formatted = String(format: "%.1f", value)
            return formatted.hasSuffix(".0") ? "\(Int(value))k" : "\(formatted)k"
        } else {
            return "\(count)"
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 10.0 {
            return String(format: "$%.2f", cost)
        } else if cost >= 0.01 {
            return String(format: "$%.2f", cost)
        } else {
            return String(format: "$%.3f", cost)
        }
    }
}

// MARK: - QR Scanner Sheet & Controller

private struct SettingsQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onScan: (URL) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                #if canImport(VisionKit) && canImport(Vision)
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    SettingsQRScannerRepresentable { url in
                        onScan(url)
                    }
                    .ignoresSafeArea()
                } else {
                    fallbackMessageView
                }
                #else
                fallbackMessageView
                #endif
            }
            .navigationTitle("Scan Pairing Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .clipShape(Circle())
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
    }

    private var fallbackMessageView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.secondaryText)

            Text("Camera Scanning Unavailable")
                .font(Theme.sans(18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("Camera QR scanning is not supported or currently available on this device. You can paste the pairing link from your clipboard or enter connection details manually.")
                .font(Theme.sans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding()
    }
}

#if canImport(VisionKit) && canImport(Vision)
private struct SettingsQRScannerRepresentable: UIViewControllerRepresentable {
    var onFound: (URL) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (URL) -> Void
        private var hasFound = false

        init(onFound: @escaping (URL) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasFound else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue,
                   let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    hasFound = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onFound(url)
                    }
                    break
                }
            }
        }
    }
}
#endif
