import Foundation
import UIKit

/// CI screenshot mode (`-LinkupScreen <name>`, see scripts/screens.sh): loads real event logs captured from the
/// bridge (Resources/Fixtures/screenshot-fixture.json) instead of connecting. Never active in normal launches.
@MainActor
enum DebugLaunch {
    static var screen: String? { UserDefaults.standard.string(forKey: "LinkupScreen") }

    static func apply(_ app: AppModel) {
        guard let url = Bundle.main.url(forResource: "screenshot-fixture", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return }
        fakePairingIfNeeded(app)
        app.store.loadFixture(json)
        let first = app.store.sessions.first(where: { $0.agent == "claude" })?.id ?? app.store.sessions.first?.id
        switch screen {
        case "chat", "summary", "artifact": app.ui.currentSessionId = first
        case "sidebar": app.ui.isSidebarOpen = true
        case "models": app.ui.isShowingModelPicker = true
        case "settings": app.ui.isShowingSettings = true
        case "usage": app.ui.isShowingUsage = true
        case "connect": app.ui.isShowingConnect = true
        case "cards": app.ui.currentSessionId = app.store.sessions.first(where: { $0.mode == "chat" })?.id
        case "projects": app.ui.isShowingProjects = true
        case "running": app.ui.isShowingRunning = true
        case "compare": app.ui.isShowingCompare = true
        case "schedules": app.ui.isShowingSchedules = true
        case "handoff": app.ui.currentSessionId = first; app.ui.handoffSessionId = first
        default: break
        }
        if screen == "summary", let id = first {
            app.ui.summaryTurn = app.store.transcript(for: id).lastAssistantTurn
        }
        if screen == "artifact" {
            let candidates = [first].compactMap { $0 } + app.store.sessions.map(\.id)
            app.ui.openArtifact = candidates.lazy
                .compactMap { app.store.transcript(for: $0).lastAssistantTurn?.artifacts.first }
                .first
        }
    }

    /// Screenshots need a "paired" look. A phone that is already paired is left alone; otherwise the placeholder
    /// pairing is removed again as soon as the app leaves the foreground.
    private static func fakePairingIfNeeded(_ app: AppModel) {
        guard !app.settings.isConfigured else { return }
        app.settings.serverURL = "https://example.ts.net"
        app.settings.token = "screenshot-mode"
        let settings = app.settings
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated {
                settings.serverURL = ""
                settings.token = ""
            }
        }
    }
}

extension SessionStore {
    /// Screenshot mode only.
    func loadFixture(_ json: [String: JSONValue]) {
        ingest(["op": .string("sessions"), "sessions": json["sessions"] ?? .array([])])
        ingest(["op": .string("catalog"), "agents": .array(Self.fixtureAgents)])
        if let usage = json["usage"] { ingest(["op": .string("usage"), "usage": usage]) }
        for (sid, events) in json["events"]?.object ?? [:] {
            let t = transcript(for: sid)
            t.reset()
            for e in events.array ?? [] { if let o = e.object { t.apply(BridgeEvent(json: o)) } }
        }
    }

    private static var fixtureAgents: [JSONValue] {
        func agent(_ id: String, _ name: String, _ models: [(String, String, String?)], efforts: [String] = []) -> JSONValue {
            .object(["id": .string(id), "name": .string(name), "available": .bool(true),
                     "defaultModel": .string(models[0].0),
                     "models": .array(models.map { m in
                         .object(["id": .string(m.0), "name": .string(m.1), "description": m.2.map(JSONValue.string) ?? .null,
                                  "efforts": .array(efforts.map(JSONValue.string))])
                     })])
        }
        return [
            agent("claude", "Claude Code", [("default", "Default (recommended)", "Opus 5.5 · Best for everyday, complex tasks"),
                                            ("sonnet", "Sonnet 5.5", "Most efficient for simpler tasks"),
                                            ("haiku", "Haiku 4.5", "Fastest for quick answers")],
                  efforts: ["low", "medium", "high", "xhigh", "max"]),
            agent("agy", "Antigravity", [("gemini-3.8-flash-high", "Gemini 3.8 Flash (High)", nil),
                                         ("gemini-3.1-pro-high", "Gemini 3.1 Pro (High)", nil)]),
            agent("hermes", "Hermes", [("hermes-knight", "Hermes Knight", nil)]),
        ]
    }
}
