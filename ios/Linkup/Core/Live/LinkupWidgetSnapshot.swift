import Foundation

enum LinkupAppGroup {
    static let suiteName = "group.com.knightabdo.linkup"
    static let pendingStopsKey = "pending_stops"
    static let widgetSnapshotKey = "widget_snapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func requestStop(for sessionId: String) {
        guard let defaults else { return }
        var pending = defaults.stringArray(forKey: pendingStopsKey) ?? []
        if !pending.contains(sessionId) {
            pending.append(sessionId)
            defaults.set(pending, forKey: pendingStopsKey)
        }
    }

    static func consumePendingStops() -> [String] {
        guard let defaults else { return [] }
        let pending = defaults.stringArray(forKey: pendingStopsKey) ?? []
        if !pending.isEmpty {
            defaults.removeObject(forKey: pendingStopsKey)
        }
        return pending
    }
}

struct LinkupWidgetSnapshot: Codable, Equatable, Sendable {
    var claudeFiveHourUtilization: Double?
    var claudeFiveHourReset: Date?
    var claudeWeeklyUtilization: Double?
    var claudeWeeklyReset: Date?
    var agyCreditsText: String?
    var lastSessionTitle: String?
    var lastSessionAgent: String?
    var updatedAt: Date

    static let placeholder = LinkupWidgetSnapshot(
        claudeFiveHourUtilization: 0.42,
        claudeFiveHourReset: Date().addingTimeInterval(3600 * 2),
        claudeWeeklyUtilization: 0.18,
        claudeWeeklyReset: Date().addingTimeInterval(86400 * 4),
        agyCreditsText: "1,240 credits",
        lastSessionTitle: "Linkup Live Activity",
        lastSessionAgent: "claude",
        updatedAt: Date()
    )

    static func read() -> LinkupWidgetSnapshot {
        guard let data = LinkupAppGroup.defaults?.data(forKey: LinkupAppGroup.widgetSnapshotKey),
              let snapshot = try? JSONDecoder().decode(LinkupWidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        LinkupAppGroup.defaults?.set(data, forKey: LinkupAppGroup.widgetSnapshotKey)
    }

    func hasChanged(from other: LinkupWidgetSnapshot?) -> Bool {
        guard let other else { return true }
        return claudeFiveHourUtilization != other.claudeFiveHourUtilization ||
               claudeFiveHourReset != other.claudeFiveHourReset ||
               claudeWeeklyUtilization != other.claudeWeeklyUtilization ||
               claudeWeeklyReset != other.claudeWeeklyReset ||
               agyCreditsText != other.agyCreditsText ||
               lastSessionTitle != other.lastSessionTitle ||
               lastSessionAgent != other.lastSessionAgent
    }
}
