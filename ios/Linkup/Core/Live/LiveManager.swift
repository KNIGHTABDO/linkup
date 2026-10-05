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
    @ObservationIgnored private var previouslyRunningSessions = Set<String>()
    @ObservationIgnored private var notifiedPermissionIds = Set<String>()
    @ObservationIgnored private var requestedNotificationPermission = false
    @ObservationIgnored private var lastWidgetReloadDate = Date.distantPast
    @ObservationIgnored private var lastSavedSnapshot: LinkupWidgetSnapshot?
    @ObservationIgnored private var currentScenePhase: ScenePhase = .active
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(store: SessionStore, client: LinkupClient) {
        self.store = store
        self.client = client
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
    }

    func start(ui: UIState? = nil) {
        if let ui { self.ui = ui }
        guard pollTask == nil else { return }

        // Track any existing activities
        for activity in Activity<LinkupActivityAttributes>.activities {
            activeActivities[activity.attributes.sessionId] = activity
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { break }
                await self.poll()
            }
        }
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        self.currentScenePhase = phase
        if phase == .background {
            if !previouslyRunningSessions.isEmpty && audioKeepAlive.isEnabled {
                audioKeepAlive.start()
            }
        } else if phase == .active {
            if audioKeepAlive.isPlaying {
                audioKeepAlive.stop()
            }
        }
    }

    // MARK: - Polling Loop (1 second)

    func poll() async {
        // 1. Process stop requests from Dynamic Island / Lock Screen button
        let stops = LinkupAppGroup.consumePendingStops()
        for sid in stops {
            store.interrupt(sid)
        }

        // 2. Identify sessions to inspect
        var sessionIdsToInspect = Set<String>()
        for s in store.sessions {
            if s.isRunning { sessionIdsToInspect.insert(s.id) }
        }
        if let currentId = ui?.currentSessionId {
            sessionIdsToInspect.insert(currentId)
        }
        for id in activeActivities.keys {
            sessionIdsToInspect.insert(id)
        }
        for id in previouslyRunningSessions {
            sessionIdsToInspect.insert(id)
        }

        var hasAnyRunningTurn = false

        for sid in sessionIdsToInspect {
            let transcript = store.transcript(for: sid)
            let session = store.session(sid)
            let title = session?.displayTitle ?? "Linkup"
            let agent = session?.agent ?? "claude"

            if let turn = transcript.liveTurn {
                hasAnyRunningTurn = true
                previouslyRunningSessions.insert(sid)

                requestNotificationPermissionIfNeeded()

                // Permission request notification while backgrounded
                if currentScenePhase != .active {
                    for req in transcript.pendingPermissions {
                        if !notifiedPermissionIds.contains(req.id) {
                            notifiedPermissionIds.insert(req.id)
                            postPermissionNotification(
                                sessionId: sid,
                                permissionId: req.id,
                                title: title,
                                tool: req.tool
                            )
                        }
                    }
                }

                // Update or start Live Activity
                let canStart = (currentScenePhase == .active || audioKeepAlive.isPlaying)
                let state = LinkupActivityAttributes.ContentState(
                    phase: turn.phase.rawValue,
                    line: turn.activityLine,
                    started: turn.started,
                    finished: turn.finished,
                    steps: turn.activity.count,
                    tokens: (turn.usage?.input ?? 0) + (turn.usage?.output ?? 0)
                )

                if let existingActivity = activeActivities[sid] {
                    Task {
                        await existingActivity.update(ActivityContent(state: state, staleDate: nil))
                    }
                } else if canStart && ActivityAuthorizationInfo().areActivitiesEnabled {
                    let attributes = LinkupActivityAttributes(
                        sessionId: sid,
                        agent: agent,
                        title: title
                    )
                    do {
                        let activity = try Activity<LinkupActivityAttributes>.request(
                            attributes: attributes,
                            content: ActivityContent(state: state, staleDate: nil),
                            pushType: nil
                        )
                        activeActivities[sid] = activity
                    } catch {
                        // Request failed (e.g. system rate limit or disabled by user)
                    }
                }
            } else {
                // No live turn
                if previouslyRunningSessions.contains(sid) {
                    previouslyRunningSessions.remove(sid)

                    let lastTurn = transcript.lastAssistantTurn
                    let fullText = lastTurn?.textBlocks.map(\.text).joined() ?? ""
                    let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
                    let snippet = String(firstLine.prefix(80))
                    let doneLine = snippet.isEmpty ? "Done" : snippet

                    if let activity = activeActivities.removeValue(forKey: sid) {
                        let endState = LinkupActivityAttributes.ContentState(
                            phase: "done",
                            line: doneLine,
                            started: lastTurn?.started ?? Date(),
                            finished: Date(),
                            steps: lastTurn?.activity.count ?? 0,
                            tokens: (lastTurn?.usage?.input ?? 0) + (lastTurn?.usage?.output ?? 0)
                        )
                        Task {
                            await activity.end(
                                ActivityContent(state: endState, staleDate: nil),
                                dismissalPolicy: .after(Date.now.addingTimeInterval(15 * 60))
                            )
                        }
                    }

                    if currentScenePhase != .active {
                        postTurnFinishedNotification(sessionId: sid, title: title, answer: doneLine)
                    }
                }
            }
        }

        // 3. Audio keep-alive tick
        if currentScenePhase == .background {
            if hasAnyRunningTurn && audioKeepAlive.isEnabled && !audioKeepAlive.isPlaying {
                audioKeepAlive.start()
            } else if audioKeepAlive.isPlaying {
                audioKeepAlive.tick(hasRunningTurn: hasAnyRunningTurn)
            }
        } else if currentScenePhase == .active {
            if audioKeepAlive.isPlaying {
                audioKeepAlive.stop()
            }
        }

        // 4. Widget snapshot update
        updateWidgetSnapshotIfNeeded()
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
        let allowAction = UNNotificationAction(
            identifier: "ALLOW",
            title: "Allow",
            options: []
        )
        let denyAction = UNNotificationAction(
            identifier: "DENY",
            title: "Deny",
            options: [.destructive]
        )
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
        content.userInfo = [
            "sessionId": sessionId,
            "permissionId": permissionId
        ]

        let request = UNNotificationRequest(
            identifier: "perm-\(sessionId)-\(permissionId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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

        if action == "ALLOW", let permissionId {
            let transcript = store.transcript(for: sessionId)
            if let req = transcript.pendingPermissions.first(where: { $0.id == permissionId }) {
                store.answer(req, in: sessionId, allow: true)
            } else {
                let req = PermissionRequest(id: permissionId, tool: "tool", input: .null, reason: nil)
                store.answer(req, in: sessionId, allow: true)
            }
        } else if action == "DENY", let permissionId {
            let transcript = store.transcript(for: sessionId)
            if let req = transcript.pendingPermissions.first(where: { $0.id == permissionId }) {
                store.answer(req, in: sessionId, allow: false)
            } else {
                let req = PermissionRequest(id: permissionId, tool: "tool", input: .null, reason: nil)
                store.answer(req, in: sessionId, allow: false)
            }
        } else if action == UNNotificationDefaultActionIdentifier {
            ui?.currentSessionId = sessionId
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
            updatedAt: Date()
        )

        if newSnapshot.hasChanged(from: lastSavedSnapshot) {
            lastSavedSnapshot = newSnapshot
            newSnapshot.write()

            let now = Date()
            if now.timeIntervalSince(lastWidgetReloadDate) >= 300 {
                lastWidgetReloadDate = now
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
