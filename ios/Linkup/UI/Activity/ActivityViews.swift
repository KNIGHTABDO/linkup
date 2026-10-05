import SwiftUI

/// STUB (task activity): collapsed "• • Designing a full HTML…  >" row of a turn's thinking/tools.
struct ActivityRow: View {
    let turn: AssistantTurn
    var body: some View { Text(turn.activityLine) }
}

/// STUB (task activity): the "Summary" sheet timeline of thinking and tool calls.
struct SummarySheet: View {
    let turn: AssistantTurn
    var body: some View { Text("Summary") }
}

/// STUB (task activity): one tool call's input/output.
struct ToolCallDetailView: View {
    let tool: ToolCall
    var body: some View { Text(tool.name) }
}

/// STUB (task activity): Allow / Deny for a tool permission request.
struct PermissionCard: View {
    let request: PermissionRequest
    let sessionId: String
    var body: some View { Text(request.tool) }
}
