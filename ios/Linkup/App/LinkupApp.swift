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
                .environment(app.live)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in app.handle(url) }
                .task { app.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            app.live.scenePhaseChanged(to: phase)
            if phase == .active {
                if DebugLaunch.screen == nil { app.client.reconnectIfNeeded() }
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
    let live: LiveManager
    @ObservationIgnored private var started = false

    init() {
        client = LinkupClient(settings: settings)
        store = SessionStore(client: client)
        live = LiveManager(store: store, client: client)
        // A launch from a notification action has no window, so the scene's .task never runs.
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    func start() {
        guard !started else { return }
        started = true
        live.start(ui: ui)
        updates.checkIfDue()
        if DebugLaunch.screen != nil {
            DebugLaunch.apply(self)
            return
        }
        if settings.isConfigured { client.connect() } else { ui.isShowingConnect = true }
    }

    func handle(_ url: URL) {
        if url.host == "session" {
            let id = url.lastPathComponent
            if !id.isEmpty, id != "/" { ui.openSession(id) }
            return
        }
        // An already-paired phone asks before a link replaces the saved PC.
        if settings.isConfigured, DebugLaunch.screen == nil {
            ui.pendingPairingURL = url
            return
        }
        pair(with: url)
    }

    func pair(with url: URL) {
        if settings.apply(pairingLink: url) {
            ui.isShowingConnect = false
            client.connect()
        }
    }
}

private extension LinkupClient {
    /// `disconnect()` leaves this reason; returning to the foreground must not undo it.
    var isUserDisconnected: Bool {
        if case .offline(let why) = state { return why == "Disconnected" }
        return false
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
    var toast: String? {
        didSet { if toast != nil { toastID += 1 } }
    }
    /// Bumps on every toast so repeating the same message restarts its timer.
    private(set) var toastID = 0
    var isShowingProjects = false
    var isShowingRunning = false
    var isShowingSchedules = false
    var isShowingCompare = false
    /// Session the hand-off picker is open for.
    var handoffSessionId: String?
    /// Local dev-server port shown in the preview browser.
    var previewPort: Int?
    /// A `linkup://pair` link waiting for the user to confirm replacing the saved PC.
    var pendingPairingURL: URL?

    /// The one way to switch conversations (nil = new chat): closes the drawer with its slide animation and
    /// drops per-chat panels (Summary/Artifact inspector) that belong to the previous chat.
    func openSession(_ id: String?) {
        if currentSessionId != id {
            summaryTurn = nil
            openArtifact = nil
        }
        currentSessionId = id
        if isSidebarOpen {
            withAnimation(.smooth(duration: 0.35)) { isSidebarOpen = false }
        }
    }

    func newChat() { openSession(nil) }
}
