import Foundation
import Observation

/// Manages pinned assistant turns per session, persisted in UserDefaults.
@MainActor @Observable
final class PinnedStore {
    static let shared = PinnedStore()

    /// Cache of sessionId -> Set of turn IDs
    private var cache: [String: Set<String>] = [:]

    init() {}

    /// Returns the set of pinned turn IDs for the given session.
    func pinnedIds(for sessionId: String) -> Set<String> {
        if let existing = cache[sessionId] {
            return existing
        }
        let list = UserDefaults.standard.stringArray(forKey: storageKey(for: sessionId)) ?? []
        let set = Set(list)
        cache[sessionId] = set
        return set
    }

    /// Checks whether a turn is pinned in a session.
    func isPinned(turnId: String, in sessionId: String) -> Bool {
        pinnedIds(for: sessionId).contains(turnId)
    }

    /// Toggles the pinned state of a turn in a session.
    func togglePin(turnId: String, in sessionId: String) {
        var current = pinnedIds(for: sessionId)
        if current.contains(turnId) {
            current.remove(turnId)
        } else {
            current.insert(turnId)
        }
        cache[sessionId] = current
        UserDefaults.standard.set(Array(current), forKey: storageKey(for: sessionId))
    }

    /// Unpins a turn in a session.
    func unpin(turnId: String, in sessionId: String) {
        var current = pinnedIds(for: sessionId)
        if current.remove(turnId) != nil {
            cache[sessionId] = current
            UserDefaults.standard.set(Array(current), forKey: storageKey(for: sessionId))
        }
    }

    private func storageKey(for sessionId: String) -> String {
        "linkup_pinned_turns_\(sessionId)"
    }
}
