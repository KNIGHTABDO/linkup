import ActivityKit
import Foundation

struct LinkupActivityAttributes: ActivityAttributes {
    var sessionId: String
    var agent: String
    var title: String

    struct ContentState: Codable, Hashable {
        var phase: String
        var line: String
        var started: Date
        var finished: Date?
        var steps: Int
        var tokens: Int
    }
}
