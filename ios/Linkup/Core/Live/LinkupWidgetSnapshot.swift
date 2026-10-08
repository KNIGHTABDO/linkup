import Foundation
import SwiftUI

/// Shared between the app and the widget extension through the App Group.
enum LinkupAppGroup {
    static let suiteName = "group.com.knightabdo.linkup"
    /// One key per session (`pending_stop_<id>` = request time) so two Stop taps can never overwrite each other.
    static let pendingStopPrefix = "pending_stop_"
    static let widgetSnapshotKey = "widget_snapshot"
    /// A Stop older than this is ignored (the user tapped it long ago; it must not kill a newer turn).
    static let stopMaxAge: TimeInterval = 300

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func requestStop(for sessionId: String) {
        defaults?.set(Date().timeIntervalSince1970, forKey: pendingStopPrefix + sessionId)
    }

    /// Returns the sessions whose Stop was tapped and forgets them. Each session has its own key, so a request
    /// written while this runs is either returned now or on the next call, never lost.
    static func consumePendingStops() -> [String] {
        guard let defaults else { return [] }
        let now = Date().timeIntervalSince1970
        var out: [String] = []
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(pendingStopPrefix) {
            defaults.removeObject(forKey: key)
            let requested = (value as? Double) ?? 0
            if now - requested <= stopMaxAge { out.append(String(key.dropFirst(pendingStopPrefix.count))) }
        }
        return out
    }
}

extension Color {
    /// The one "warning" yellow used by the widgets (matches the app's usage ring).
    static let linkupWarning = Color(red: 0xE8 / 255, green: 0xB0 / 255, blue: 0x4B / 255)
}

struct LinkupWidgetSnapshot: Codable, Equatable, Sendable {
    var claudeFiveHourUtilization: Double?
    var claudeFiveHourReset: Date?
    var claudeWeeklyUtilization: Double?
    var claudeWeeklyReset: Date?
    var agyCreditsText: String?
    var lastSessionTitle: String?
    var lastSessionAgent: String?
    /// For the widget's `linkup://session/<id>` deep link.
    var lastSessionId: String?
    var updatedAt: Date

    /// Numbers older than this are shown dimmed.
    static let staleAfter: TimeInterval = 30 * 60

    func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > Self.staleAfter }

    /// Only for the widget gallery / redacted placeholder, where the widget draws it masked. Never returned by `read()`.
    static let placeholder = LinkupWidgetSnapshot(
        claudeFiveHourUtilization: 0.5,
        claudeFiveHourReset: nil,
        claudeWeeklyUtilization: 0.5,
        claudeWeeklyReset: nil,
        agyCreditsText: nil,
        lastSessionTitle: "Session title",
        lastSessionAgent: "claude",
        lastSessionId: nil,
        updatedAt: Date()
    )

    /// The last snapshot the app wrote, or nil when the app never synced (the widget then says "Open Linkup to sync").
    static func read() -> LinkupWidgetSnapshot? {
        guard let data = LinkupAppGroup.defaults?.data(forKey: LinkupAppGroup.widgetSnapshotKey),
              let snapshot = try? JSONDecoder().decode(LinkupWidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        LinkupAppGroup.defaults?.set(data, forKey: LinkupAppGroup.widgetSnapshotKey)
    }

    /// Content changes only (`updatedAt` alone is not a change).
    func hasChanged(from other: LinkupWidgetSnapshot?) -> Bool {
        guard let other else { return true }
        return claudeFiveHourUtilization != other.claudeFiveHourUtilization ||
               claudeFiveHourReset != other.claudeFiveHourReset ||
               claudeWeeklyUtilization != other.claudeWeeklyUtilization ||
               claudeWeeklyReset != other.claudeWeeklyReset ||
               agyCreditsText != other.agyCreditsText ||
               lastSessionTitle != other.lastSessionTitle ||
               lastSessionAgent != other.lastSessionAgent ||
               lastSessionId != other.lastSessionId
    }
}
