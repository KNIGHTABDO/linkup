import SwiftUI

@main
struct LinkupApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.settings)
                .environment(app.client)
                .environment(app.store)
                .environment(app.ui)
                .environment(app.updates)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in app.handle(url) }
                .task { app.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.client.reconnectIfNeeded()
                app.updates.checkIfDue()
            }
        }
    }
}

/// Root object graph: connection settings, the bridge client, the session store and UI state.
@MainActor @Observable
final class AppModel {
    let settings = ConnectionSettings()
    let client: LinkupClient
    let store: SessionStore
    let ui = UIState()
    let updates = UpdateChecker()
    @ObservationIgnored private var started = false

    init() {
        client = LinkupClient(settings: settings)
        store = SessionStore(client: client)
    }

    func start() {
        guard !started else { return }
        started = true
        updates.checkIfDue()
        if DebugLaunch.screen != nil {
            DebugLaunch.apply(self)
            return
        }
        if settings.isConfigured { client.connect() } else { ui.isShowingConnect = true }
    }

    func handle(_ url: URL) {
        if settings.apply(pairingLink: url) {
            ui.isShowingConnect = false
            client.connect()
        }
    }
}

/// Navigation and presentation state shared by the shell, sidebar and chat.
@MainActor @Observable
final class UIState {
    /// The open conversation (nil = new-chat screen).
    var currentSessionId: String?
    /// Agent/model/effort the next new session starts with (the composer's model pill).
    var draftAgent = UserDefaults.standard.string(forKey: "draftAgent") ?? "claude" {
        didSet { UserDefaults.standard.set(draftAgent, forKey: "draftAgent") }
    }
    var draftModel: String? = UserDefaults.standard.string(forKey: "draftModel") {
        didSet { UserDefaults.standard.set(draftModel, forKey: "draftModel") }
    }
    var draftEffort: String? = UserDefaults.standard.string(forKey: "draftEffort") {
        didSet { UserDefaults.standard.set(draftEffort, forKey: "draftEffort") }
    }
    var draftProject: String? = UserDefaults.standard.string(forKey: "draftProject") {
        didSet { UserDefaults.standard.set(draftProject, forKey: "draftProject") }
    }
    var isSidebarOpen = false
    var isShowingSettings = false
    var isShowingConnect = false
    var isShowingModelPicker = false
    var isShowingUsage = false
    /// Turn whose activity timeline ("Summary") is open.
    var summaryTurn: AssistantTurn?
    var openArtifact: ArtifactRef?
    var toast: String?
    var isShowingProjects = false
    var isShowingRunning = false
    var isShowingSchedules = false
    var isShowingCompare = false
    /// Session the hand-off picker is open for.
    var handoffSessionId: String?
    /// Local dev-server port shown in the preview browser.
    var previewPort: Int?

    func newChat() {
        currentSessionId = nil
        isSidebarOpen = false
    }
}
