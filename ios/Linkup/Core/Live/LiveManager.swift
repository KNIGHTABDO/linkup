import ActivityKit
import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor @Observable
final class LiveManager: NSObject, UNUserNotificationCenterDelegate {
    let store: SessionStore
    let client: LinkupClient
    weak var ui: UIState?

    @ObservationIgnored private let audioKeepAlive = LiveAudioKeepAlive()
    @ObservationIgnored private var activeActivities: [String: Activity<LinkupActivityAttributes>] = [:]
    @ObservationIgnored private var lastStates: [String: LinkupActivityAttributes.ContentState] = [:]
    @ObservationIgnored private var lastActivityUpdate: [String: Date] = [:]
    @ObservationIgnored private var previouslyRunningSessions = Set<String>()
    @ObservationIgnored private var notifiedPermissionIds = Set<String>()
    @ObservationIgnored private var requestedNotificationPermission = false
    @ObservationIgnored private var lastWidgetReloadDate = Date.distantPast
    @ObservationIgnored private var widgetReloadTask: Task<Void, Never>?
    @ObservationIgnored private var lastSavedSnapshot: LinkupWidgetSnapshot?
    @ObservationIgnored private var currentScenePhase: ScenePhase = .active
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private static let staleInterval: TimeInterval = 5 * 60

    init(store: SessionStore, client: LinkupClient) {
        self.store = store
        self.client = client
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
        audioKeepAlive.shouldRun = { [weak self] in
            guard let self else { return false }
            return self.currentScenePhase == .background && self.hasRunningWork()
        }
    }

    func start(ui: UIState? = nil) {
        if let ui { self.ui = ui }
        guard !started else { return }
        started = true

        // Activities that survived a relaunch are adopted; `evaluate` ends the ones whose work is over.
        for activity in Activity<LinkupActivityAttributes>.activities {
            activeActivities[activity.attributes.sessionId] = activity
        }
        // Sending a message must engage the keep-alive at once, not at the next tick.
        store.didSend = { [weak self] _ in
            guard let self else { return }
            self.evaluate()
            self.ensureTimer()
        }
        observe()
        evaluate()
        ensureTimer()
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        currentScenePhase = phase
        store.isAppActive = (phase == .active)
        switch phase {
        case .background:
            store.flushCache()
            if hasRunningWork() && audioKeepAlive.isEnabled { audioKeepAlive.start() }
        case .active:
            audioKeepAlive.stop()
            audioKeepAlive.reset()
            evaluate()
        default:
            break
        }
        ensureTimer()
    }

    // MARK: - Driving

    /// Re-armed on every change of the session list / usage / connection; a timer runs only while something works.
    private func observe() {
        withObservationTracking {
            _ = store.sessions.map { "\($0.id)\($0.status)\($0.updated)" }
            _ = store.usage
            _ = client.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.evaluate()
                self.ensureTimer()
                self.observe()
            }
        }
    }

    private func hasRunningWork() -> Bool {
        if store.sessions.contains(where: { $0.isRunning }) { return true }
        return store.sessions.contains { store.existingTranscript(for: $0.id)?.liveTurn != nil }
    }

    private func needsTimer() -> Bool {
        hasRunningWork() || !activeActivities.isEmpty || audioKeepAlive.isPlaying
    }

    private func ensureTimer() {
        guard timerTask == nil, needsTimer() else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.evaluate()
                if !self.needsTimer() {
                    self.timerTask = nil
                    return
                }
            }
        }
    }

    private func drainStops() {
        for sid in LinkupAppGroup.consumePendingStops() {
            if !store.interrupt(sid) {
                // Offline: keep the request so it is retried (it expires after 5 minutes).
                LinkupAppGroup.requestStop(for: sid)
            }
        }
    }

    private func endActivity(_ sid: String, state: LinkupActivityAttributes.ContentState?, dismissAfter: TimeInterval) {
        guard let activity = activeActivities.removeValue(forKey: sid) else { return }
        lastStates[sid] = nil
        lastActivityUpdate[sid] = nil
        let final = state ?? activity.content.state
        Task {
            await activity.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: dismissAfter <= 0 ? .immediate : .after(Date.now.addingTimeInterval(dismissAfter))
            )
        }
    }

    // MARK: - Evaluation

    func evaluate() {
        drainStops()

        let known = Set(store.sessions.map(\.id))
        // Forget bookkeeping of deleted sessions.
        previouslyRunningSessions.formIntersection(known)
        var livePerms = Set<String>()
        for id in known {
            for req in store.existingTranscript(for: id)?.pendingPermissions ?? [] { livePerms.insert(req.id) }
        }
        notifiedPermissionIds.formIntersection(livePerms)

        var hasAnyRunningTurn = false
        let connected = client.state == .connected

        for session in store.sessions {
            let sid = session.id
            let transcript = store.existingTranscript(for: sid)
            let title = session.displayTitle
            let agent = session.agent

            if let transcript, !transcript.isLoading, let turn = transcript.liveTurn {
                hasAnyRunningTurn = true
                previouslyRunningSessions.insert(sid)
                requestNotificationPermissionIfNeeded()

                if currentScenePhase != .active {
                    for req in transcript.pendingPermissions where !notifiedPermissionIds.contains(req.id) {
                        notifiedPermissionIds.insert(req.id)
                        postPermissionNotification(sessionId: sid, permissionId: req.id, title: title, tool: req.tool)
                    }
                }

                let state = LinkupActivityAttributes.ContentState(
                    phase: turn.phase.rawValue,
                    line: turn.activityLine,
                    started: turn.started,
                    finished: turn.finished,
                    steps: turn.activity.count,
                    tokens: (turn.usage?.input ?? 0) + (turn.usage?.output ?? 0)
                )
                updateActivity(sid: sid, agent: agent, title: title, state: state)
            } else if session.isRunning && (transcript == nil || transcript?.isLoading == true) {
                // Running on the PC but not loaded here: still counts as work for the keep-alive.
                hasAnyRunningTurn = true
            } else {
                if previouslyRunningSessions.remove(sid) != nil {
                    let lastTurn = transcript?.lastAssistantTurn
                    let fullText = lastTurn?.textBlocks.map(\.text).joined() ?? ""
                    let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
                    let doneLine = firstLine.isEmpty ? "Done" : String(firstLine.prefix(80))
                    let endState = LinkupActivityAttributes.ContentState(
                        phase: "done",
                        line: doneLine,
                        started: lastTurn?.started ?? Date(),
                        finished: Date(),
                        steps: lastTurn?.activity.count ?? 0,
                        tokens: (lastTurn?.usage?.input ?? 0) + (lastTurn?.usage?.output ?? 0)
                    )
                    endActivity(sid, state: endState, dismissAfter: 15 * 60)
                    if currentScenePhase != .active {
                        postTurnFinishedNotification(sessionId: sid, title: title, answer: doneLine)
                    }
                } else if connected, activeActivities[sid] != nil {
                    // Restored at launch (or its end was missed) and nothing runs any more.
                    endActivity(sid, state: nil, dismissAfter: 0)
                }
            }
        }

        // Activities of deleted sessions.
        if connected {
            for sid in Array(activeActivities.keys) where !known.contains(sid) {
                endActivity(sid, state: nil, dismissAfter: 0)
            }
        }

        if currentScenePhase == .background {
            if hasAnyRunningTurn && audioKeepAlive.isEnabled && !audioKeepAlive.isPlaying && !audioKeepAlive.hitCap {
                audioKeepAlive.start()
            } else if audioKeepAlive.isPlaying {
                audioKeepAlive.tick(hasRunningTurn: hasAnyRunningTurn)
            }
            if !hasAnyRunningTurn && !audioKeepAlive.isPlaying { audioKeepAlive.reset() }
        } else if currentScenePhase == .active, audioKeepAlive.isPlaying {
            audioKeepAlive.stop()
        }

        updateWidgetSnapshotIfNeeded()
    }

    private func updateActivity(sid: String, agent: String, title: String, state: LinkupActivityAttributes.ContentState) {
        let now = Date()
        if let activity = activeActivities[sid] {
            // Unchanged content is not re-sent, except to push the stale date forward before it expires.
            let refreshDue = now.timeIntervalSince(lastActivityUpdate[sid] ?? .distantPast) > Self.staleInterval - 60
            guard lastStates[sid] != state || refreshDue else { return }
            lastStates[sid] = state
            lastActivityUpdate[sid] = now
            Task {
                await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(Self.staleInterval)))
            }
        } else if (currentScenePhase == .active || audioKeepAlive.isPlaying) && ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = LinkupActivityAttributes(sessionId: sid, agent: agent, title: title)
            do {
                let activity = try Activity<LinkupActivityAttributes>.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: now.addingTimeInterval(Self.staleInterval)),
                    pushType: nil
                )
                activeActivities[sid] = activity
                lastStates[sid] = state
                lastActivityUpdate[sid] = now
            } catch {
                // Rate limit or disabled by the user: the next evaluation (a second later while running) retries.
            }
        }
    }

    // MARK: - Notifications

    func requestNotificationPermissionIfNeeded() {
        guard !requestedNotificationPermission else { return }
        requestedNotificationPermission = true
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    private func setupNotificationCategories() {
        let allowAction = UNNotificationAction(identifier: "ALLOW", title: "Allow", options: [])
        let denyAction = UNNotificationAction(identifier: "DENY", title: "Deny", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: "PERMISSION_REQUEST",
            actions: [allowAction, denyAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func postTurnFinishedNotification(sessionId: String, title: String, answer: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = answer.isEmpty ? "Done" : answer
        content.sound = .default
        content.userInfo = ["sessionId": sessionId]
        let request = UNNotificationRequest(
            identifier: "turn-end-\(sessionId)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func postPermissionNotification(sessionId: String, permissionId: String, title: String, tool: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Needs your approval"
        content.categoryIdentifier = "PERMISSION_REQUEST"
        content.sound = .default
        content.userInfo = ["sessionId": sessionId, "permissionId": permissionId]
        let request = UNNotificationRequest(
            identifier: "perm-\(sessionId)-\(permissionId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func postFailureNotification(sessionId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Answer not delivered"
        content.body = "Linkup couldn\u{2019}t reach your PC. Open the app to approve or deny."
        content.userInfo = ["sessionId": sessionId]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "perm-fail-\(sessionId)", content: content, trigger: nil)
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        Task { @MainActor in
            self.handleNotificationResponse(action: action, userInfo: userInfo)
            completionHandler()
        }
    }

    private func handleNotificationResponse(action: String, userInfo: [AnyHashable: Any]) {
        guard let sessionId = userInfo["sessionId"] as? String else { return }
        let permissionId = userInfo["permissionId"] as? String

        if action == "ALLOW" || action == "DENY", let permissionId {
            let allow = action == "ALLOW"
            Task { @MainActor in
                // The app may just have been woken in the background: wait for the socket before answering.
                if self.client.state != .connected {
                    self.client.reconnectIfNeeded()
                    _ = await self.client.waitUntilConnected(timeout: 15)
                }
                let existing = self.store.existingTranscript(for: sessionId)?.pendingPermissions.first(where: { $0.id == permissionId })
                let req = existing ?? PermissionRequest(id: permissionId, tool: "tool", input: .null, reason: nil)
                if !self.store.answer(req, in: sessionId, allow: allow) {
                    self.postFailureNotification(sessionId: sessionId)
                }
            }
        } else if action == UNNotificationDefaultActionIdentifier {
            ui?.openSession(sessionId)
            ui?.isSidebarOpen = false
        }
    }

    // MARK: - Home Screen Widget Snapshot

    private func updateWidgetSnapshotIfNeeded() {
        let claudePlan = store.usage?.claudePlan
        let claudeFallback = store.usage?.claude
        let fiveHour = claudePlan?.fiveHour?.utilization ?? claudeFallback?.fiveHour?.utilization
        let fiveHourReset = claudePlan?.fiveHour?.resetDate ?? claudeFallback?.fiveHour?.resetDate
        let weekly = claudePlan?.sevenDay?.utilization ?? claudeFallback?.sevenDay?.utilization
        let weeklyReset = claudePlan?.sevenDay?.resetDate ?? claudeFallback?.sevenDay?.resetDate
        let agyCredits = store.usage?.agy?.credits
        let lastSession = store.sessions.first

        let newSnapshot = LinkupWidgetSnapshot(
            claudeFiveHourUtilization: fiveHour,
            claudeFiveHourReset: fiveHourReset,
            claudeWeeklyUtilization: weekly,
            claudeWeeklyReset: weeklyReset,
            agyCreditsText: agyCredits,
            lastSessionTitle: lastSession?.displayTitle,
            lastSessionAgent: lastSession?.agent,
            lastSessionId: lastSession?.id,
            updatedAt: Date()
        )

        // Content changes reload the widget; otherwise the snapshot is only re-stamped every 10 minutes so the
        // widget can tell "fresh" from "the app has not synced for a long time".
        let changed = newSnapshot.hasChanged(from: lastSavedSnapshot)
        let heartbeatDue = Date().timeIntervalSince(lastSavedSnapshot?.updatedAt ?? .distantPast) > 600
        guard changed || heartbeatDue else { return }
        lastSavedSnapshot = newSnapshot
        newSnapshot.write()
        scheduleWidgetReload()
    }

    /// At most one reload per 5 minutes; a change inside the window is reloaded when the window ends.
    private func scheduleWidgetReload() {
        let wait = 300 - Date().timeIntervalSince(lastWidgetReloadDate)
        if wait <= 0 {
            lastWidgetReloadDate = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } else if widgetReloadTask == nil {
            widgetReloadTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.widgetReloadTask = nil
                self.lastWidgetReloadDate = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
