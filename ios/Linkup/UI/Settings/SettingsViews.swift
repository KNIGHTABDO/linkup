import SwiftUI
import UIKit
import AVFoundation
#if canImport(VisionKit) && canImport(Vision)
import VisionKit
import Vision
#endif

// MARK: - Pairing URL Parser & Sanitizer

enum PairingURLParser {
    /// Strips trailing slashes and any trailing "/linkup" path segment so host bases like
    /// `https://host.ts.net/linkup` don't produce duplicate `/linkup/linkup/ws` paths.
    static func sanitizeHostURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") && !s.isEmpty {
            s = "https://" + s
        }
        while s.hasSuffix("/") {
            s.removeLast()
        }
        if s.hasSuffix("/linkup") {
            s = String(s.dropLast("/linkup".count))
        }
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }

    /// Extracts normalized server base URL and token from a pairing URL.
    static func parse(url: URL) -> (serverURL: String, token: String)? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if url.scheme == "linkup" {
            guard let server = comps.queryItems?.first(where: { $0.name == "url" })?.value,
                  let token = comps.queryItems?.first(where: { $0.name == "token" })?.value else {
                return nil
            }
            let sanitized = sanitizeHostURL(server)
            guard !sanitized.isEmpty, !token.isEmpty else { return nil }
            return (sanitized, token)
        } else if url.scheme == "https" || url.scheme == "http" {
            guard let token = comps.queryItems?.first(where: { $0.name == "token" })?.value else {
                return nil
            }
            var hostComps = comps
            hostComps.queryItems = nil
            guard let hostURL = hostComps.url?.absoluteString else { return nil }
            let sanitized = sanitizeHostURL(hostURL)
            guard !sanitized.isEmpty, !token.isEmpty else { return nil }
            return (sanitized, token)
        }
        return nil
    }

    /// Parses pairing link from text (either direct URL or text containing linkup://pair).
    static func parse(text: String) -> (serverURL: String, token: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let res = parse(url: url) {
            return res
        }
        if let range = trimmed.range(of: "linkup://pair?") {
            let substring = String(trimmed[range.lowerBound...])
            let firstWord = substring.components(separatedBy: .whitespacesAndNewlines).first ?? substring
            if let url = URL(string: firstWord), let res = parse(url: url) {
                return res
            }
        }
        return nil
    }
}

// MARK: - ConnectView

/// Pair with the bridge on the PC via camera QR code scan, pasted pairing link, or manual address and token.
struct ConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionSettings.self) private var settings
    @Environment(LinkupClient.self) private var client
    @Environment(UIState.self) private var ui

    @State private var isShowingScannerSheet = false
    @State private var pendingPairingURL: URL? = nil
    @State private var isManualExpanded = false
    @State private var manualURL = ""
    @State private var manualToken = ""
    @State private var hasCopiedCommand = false
    @State private var copyTask: Task<Void, Never>? = nil

    @State private var isConnecting = false
    @State private var inlineError: String? = nil
    @State private var originalServerURL: String? = nil
    @State private var originalToken: String? = nil

    @FocusState private var focusedField: ManualField?
    private enum ManualField: Hashable {
        case url, token
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Top close button when already configured
                if settings.isConfigured {
                    HStack {
                        Spacer()
                        SheetCloseButton {
                            ui.isShowingConnect = false
                            dismiss()
                        }
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
                        Text("Run ")
                            .font(Theme.sans(16))
                            .foregroundStyle(Theme.secondaryText)
                        + Text("python -m linkup_bridge pair")
                            .font(Theme.mono(15))
                            .foregroundStyle(Theme.text)
                        + Text(" on your PC and scan the code.")
                            .font(Theme.sans(16))
                            .foregroundStyle(Theme.secondaryText)

                        HStack(spacing: 10) {
                            Text("python -m linkup_bridge pair")
                                .font(Theme.mono(13))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = "python -m linkup_bridge pair"
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                withAnimation(.snappy) {
                                    hasCopiedCommand = true
                                }
                                copyTask?.cancel()
                                copyTask = Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    withAnimation(.snappy) {
                                        hasCopiedCommand = false
                                    }
                                }
                            } label: {
                                Image(systemName: hasCopiedCommand ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(hasCopiedCommand ? Theme.success : Theme.secondaryText)
                                    .contentTransition(.symbolEffect(.replace))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy pairing command")
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 4)
                        .padding(.vertical, 2)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                    }
                    .padding(.horizontal, 8)
                }

                // Inline status / error feedback
                if isConnecting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Theme.accent)
                        Text("Connecting to bridge\u{2026}")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                } else if client.state == .connected {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.success)
                        Text("Connected to bridge!")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.success)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Theme.success.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.success.opacity(0.25), lineWidth: 1))
                } else if let error = inlineError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 2)
                        Text(error)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Theme.danger.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.danger.opacity(0.25), lineWidth: 1))
                }

                // Primary actions: Scan QR & Paste link
                VStack(spacing: 12) {
                    Button {
                        inlineError = nil
                        isShowingScannerSheet = true
                    } label: {
                        Label("Scan pairing code", systemImage: "qrcode.viewfinder")
                            .font(Theme.sans(16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
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
                            .frame(minHeight: 44)
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
                                .focused($focusedField, equals: .url)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .token }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
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
                                .focused($focusedField, equals: .token)
                                .submitLabel(.go)
                                .onSubmit {
                                    if !isManualConnectDisabled {
                                        connectManually()
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                        }

                        Button {
                            connectManually()
                        } label: {
                            HStack(spacing: 8) {
                                if isConnecting {
                                    ProgressView()
                                        .tint(Color.white)
                                }
                                Text(isConnecting ? "Connecting\u{2026}" : "Connect")
                                    .font(Theme.sans(15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .disabled(isManualConnectDisabled)

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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .onAppear {
            manualURL = settings.serverURL
            manualToken = settings.token
        }
        .onChange(of: client.state) { _, newState in
            handleClientStateChange(newState)
        }
        .sheet(isPresented: $isShowingScannerSheet, onDismiss: {
            if let url = pendingPairingURL {
                pendingPairingURL = nil
                applyAndConnect(url: url)
            }
        }) {
            SettingsQRScannerSheet { url in
                pendingPairingURL = url
                isShowingScannerSheet = false
            }
        }
    }

    private var isManualConnectDisabled: Bool {
        manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        isConnecting
    }

    private func connectManually() {
        let cleanURL = PairingURLParser.sanitizeHostURL(manualURL)
        let cleanToken = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        startConnectionAttempt(serverURL: cleanURL, token: cleanToken)
    }

    private func pastePairingLink() {
        inlineError = nil
        if let url = UIPasteboard.general.url, let parsed = PairingURLParser.parse(url: url) {
            startConnectionAttempt(serverURL: parsed.serverURL, token: parsed.token)
            return
        }
        if let text = UIPasteboard.general.string, let parsed = PairingURLParser.parse(text: text) {
            startConnectionAttempt(serverURL: parsed.serverURL, token: parsed.token)
            return
        }
        inlineError = "Clipboard does not contain a valid Linkup pairing link"
    }

    private func applyAndConnect(url: URL) {
        inlineError = nil
        if let parsed = PairingURLParser.parse(url: url) {
            startConnectionAttempt(serverURL: parsed.serverURL, token: parsed.token)
        } else {
            inlineError = "Scanned code is not a valid Linkup pairing link"
        }
    }

    private func startConnectionAttempt(serverURL: String, token: String) {
        originalServerURL = settings.serverURL
        originalToken = settings.token

        settings.serverURL = serverURL
        settings.token = token
        UserDefaults.standard.set(false, forKey: "userDisconnected")

        isConnecting = true
        inlineError = nil
        client.connect()

        Task {
            try? await Task.sleep(for: .seconds(16))
            if isConnecting && client.state != .connected {
                isConnecting = false
                inlineError = "Connection timed out. Check that your PC is reachable and the bridge is running."
                if let origURL = originalServerURL, let origTok = originalToken, !origURL.isEmpty {
                    settings.serverURL = origURL
                    settings.token = origTok
                }
            }
        }
    }

    private func handleClientStateChange(_ newState: ConnectionState) {
        switch newState {
        case .connected:
            isConnecting = false
            inlineError = nil
            originalServerURL = nil
            originalToken = nil
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                ui.isShowingConnect = false
                dismiss()
            }
        case .offline(let why):
            if isConnecting {
                isConnecting = false
                inlineError = why.isEmpty ? "Could not reach bridge on your PC. Check that the bridge is running." : why
                if let origURL = originalServerURL, let origTok = originalToken, !origURL.isEmpty {
                    settings.serverURL = origURL
                    settings.token = origTok
                }
                originalServerURL = nil
                originalToken = nil
            }
        case .connecting:
            break
        case .notConfigured:
            isConnecting = false
        }
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

/// Settings sheet: connection management, agents catalog, usage link, defaults, voice language, and bridge version info.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionSettings.self) private var settings
    @Environment(LinkupClient.self) private var client
    @Environment(SessionStore.self) private var store
    @Environment(UIState.self) private var ui

    @AppStorage("linkupSpeechLanguage") private var speechLanguage: String = ""
    @State private var isRefreshingAgents = false
    @State private var shouldOpenConnect = false

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
        @Bindable var uiState = ui

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
                        UserDefaults.standard.set(false, forKey: "userDisconnected")
                        client.connect()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                    }
                    .listRowBackground(Theme.elevated)

                    Button {
                        shouldOpenConnect = true
                        dismiss()
                    } label: {
                        Label("Pair again", systemImage: "qrcode")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                    }
                    .listRowBackground(Theme.elevated)

                    Button(role: .destructive) {
                        UserDefaults.standard.set(true, forKey: "userDisconnected")
                        client.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "bolt.slash")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.danger)
                    }
                    .disabled(client.state == .notConfigured)
                    .listRowBackground(Theme.elevated)

                    Button(role: .destructive) {
                        UserDefaults.standard.set(true, forKey: "userDisconnected")
                        settings.serverURL = ""
                        settings.token = ""
                        client.disconnect()
                        shouldOpenConnect = true
                        dismiss()
                    } label: {
                        Label("Forget server", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.danger)
                    }
                    .disabled(!settings.isConfigured)
                    .listRowBackground(Theme.elevated)
                }

                // Section: Voice & Dictation Language
                Section("Voice & Dictation") {
                    Picker("Language", selection: $speechLanguage) {
                        Text("Automatic").tag("")
                        Text("English").tag("en-US")
                        Text("Français").tag("fr-FR")
                        Text("الدارجة / Arabic (Morocco)").tag("ar-MA")
                        Text("العربية").tag("ar-SA")
                    }
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
                    .listRowBackground(Theme.elevated)
                }

                // Section: Defaults
                Section("Defaults") {
                    Picker("Default Agent", selection: $uiState.draftAgent) {
                        ForEach(store.agents) { agent in
                            Text(agent.name).tag(agent.id)
                        }
                    }
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
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

                UpdatesSection()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .onDisappear {
            if shouldOpenConnect {
                ui.isShowingConnect = true
            }
        }
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

/// Claude 5-hour / 7-day plan limits, Antigravity credits & quotas, Hermes local tokens,
/// per-agent token totals with 7-day activity charts, and highest-usage sessions.
struct UsageView: View {
    var showsNavigationContainer: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(UIState.self) private var ui

    var body: some View {
        if showsNavigationContainer {
            NavigationStack {
                UsageDashboardView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SheetCloseButton {
                                ui.isShowingUsage = false
                                dismiss()
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationBackground(Theme.surface)
        } else {
            UsageDashboardView()
        }
    }
}

private struct SettingsAgentRow: View {
    let agent: AgentInfo

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: AgentKind(rawValue: agent.id)?.symbol ?? "cpu")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.agentColor(agent.id))
                .frame(width: 28, height: 28)
                .background(Theme.agentColor(agent.id).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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

// MARK: - QR Scanner Sheet & Controller

private struct SettingsQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onScan: (URL) -> Void

    @State private var invalidCodeMessage: String? = nil
    @State private var invalidCodeTask: Task<Void, Never>? = nil
    @State private var isCameraAuthorized: Bool = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()

                #if canImport(VisionKit) && canImport(Vision)
                if !isCameraAuthorized {
                    cameraDeniedView
                } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    SettingsQRScannerRepresentable(
                        onFound: { url in
                            onScan(url)
                        },
                        onInvalidCode: {
                            withAnimation(.snappy) {
                                invalidCodeMessage = "Not a Linkup pairing code"
                            }
                            invalidCodeTask?.cancel()
                            invalidCodeTask = Task {
                                try? await Task.sleep(for: .seconds(2.5))
                                withAnimation(.snappy) {
                                    invalidCodeMessage = nil
                                }
                            }
                        }
                    )
                    .ignoresSafeArea()

                    if let message = invalidCodeMessage {
                        VStack {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.accent)
                                    .font(.system(size: 14))
                                Text(message)
                                    .font(Theme.sans(14, weight: .medium))
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.elevated)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                            .padding(.top, 16)

                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
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
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .onAppear {
            checkCameraPermission()
        }
    }

    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .denied, .restricted:
            isCameraAuthorized = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isCameraAuthorized = granted
                }
            }
        case .authorized:
            isCameraAuthorized = true
        @unknown default:
            isCameraAuthorized = true
        }
    }

    private var cameraDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.secondaryText)

            Text("Camera Access Needed")
                .font(Theme.sans(18, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("Linkup needs camera access to scan pairing QR codes. Enable camera access in iOS Settings.")
                .font(Theme.sans(15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(Theme.sans(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 48)
            .padding(.top, 8)
        }
        .padding()
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
    var onInvalidCode: () -> Void

    func makeUIViewController(context: Context) -> ScannerContainerController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return ScannerContainerController(scanner: scanner)
    }

    func updateUIViewController(_ uiViewController: ScannerContainerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound, onInvalidCode: onInvalidCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (URL) -> Void
        let onInvalidCode: () -> Void
        private var hasFound = false

        init(onFound: @escaping (URL) -> Void, onInvalidCode: @escaping () -> Void) {
            self.onFound = onFound
            self.onInvalidCode = onInvalidCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasFound else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue {
                    if PairingURLParser.parse(text: payload) != nil {
                        hasFound = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        DispatchQueue.main.async { [weak self] in
                            if let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                self?.onFound(url)
                            }
                        }
                        break
                    } else {
                        DispatchQueue.main.async { [weak self] in
                            self?.onInvalidCode()
                        }
                    }
                }
            }
        }
    }
}

private final class ScannerContainerController: UIViewController {
    let scanner: DataScannerViewController

    init(scanner: DataScannerViewController) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        view.addSubview(scanner.view)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        try? scanner.startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }
}
#endif
