import AppIntents
import Foundation

struct StopTurnIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Agent Turn"
    static var description = IntentDescription("Interrupts and stops the current agent turn in Linkup.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionId: String

    init() {
        self.sessionId = ""
    }

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    func perform() async throws -> some IntentResult {
        LinkupAppGroup.requestStop(for: sessionId)
        return .result()
    }
}
