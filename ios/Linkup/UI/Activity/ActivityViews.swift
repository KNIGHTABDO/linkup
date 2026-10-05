import SwiftUI
import UIKit

// MARK: - Activity Row (collapsed inside the turn)

/// Collapsed "• • Designing a full HTML…  >" row of a turn's thinking/tools.
struct ActivityRow: View {
    let turn: AssistantTurn
    @Environment(UIState.self) private var ui

    var body: some View {
        Button {
            ui.summaryTurn = turn
        } label: {
            HStack(spacing: 8) {
                leadingIcon
                    .frame(width: 28, alignment: .leading)

                middleText
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var hasPendingPermission: Bool {
        turn.parts.contains { part in
            if case .permission(let p) = part {
                return p.allowed == nil
            }
            return false
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if hasPendingPermission {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        } else if turn.isLive {
            WorkingDots()
        } else {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var middleText: some View {
        if hasPendingPermission {
            Text("Waiting for your approval")
                .font(Theme.sans(16, weight: .medium))
                .foregroundStyle(Theme.accent)
        } else if turn.isLive {
            ActivityShimmerText(text: turn.activityLine, font: Theme.sans(16))
                .contentTransition(.opacity)
                .animation(.smooth, value: turn.activityLine)
        } else {
            Text(finishedSummaryText)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var accessibilityText: String {
        if hasPendingPermission {
            return "Waiting for your approval"
        } else if turn.isLive {
            return turn.activityLine
        } else {
            return finishedSummaryText
        }
    }

    private var finishedSummaryText: String {
        let durationStr = ActivityFormatters.duration(ms: turnDurationMs)

        var lastThinking: String?
        for part in turn.parts.reversed() {
            if case .thinking(let b) = part {
                let line = b.summaryLine
                if !line.isEmpty {
                    lastThinking = line
                    break
                }
            }
        }

        let base: String
        if let lastThinking {
            base = lastThinking
        } else {
            let toolCount = turn.parts.filter { if case .tool = $0 { return true }; return false }.count
            if toolCount > 0 {
                base = "\(toolCount) \(toolCount == 1 ? "step" : "steps")"
            } else {
                let activityCount = turn.activity.count
                if activityCount > 0 {
                    base = "\(activityCount) \(activityCount == 1 ? "step" : "steps")"
                } else if let durationStr {
                    return "Thought for \(durationStr)"
                } else {
                    base = "Done"
                }
            }
        }

        if let durationStr {
            return "\(base) \u{00B7} \(durationStr)"
        } else {
            return base
        }
    }

    private var turnDurationMs: Int? {
        if let ms = turn.durationMs, ms > 0 {
            return ms
        }
        if let finished = turn.finished {
            let diff = Int(finished.timeIntervalSince(turn.started) * 1000)
            return diff > 0 ? diff : nil
        }
        return nil
    }
}

// MARK: - Summary Sheet (timeline of thinking and tool calls)

/// The "Summary" sheet timeline of thinking and tool calls.
struct SummarySheet: View {
    let turn: AssistantTurn
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                timelineList
            }
            .background(Theme.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surface)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Dismiss")

            Spacer()

            Text("Summary")
                .font(Theme.sans(17, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer()

            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var latestThinkingId: String? {
        for part in turn.parts.reversed() {
            if case .thinking(let b) = part {
                return b.id
            }
        }
        return nil
    }

    private var timelineList: some View {
        let items = turn.activity
        let totalCount = items.count + (turn.isLive ? 1 : 0)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { part in
                        let isFirst = (part.id == items.first?.id)
                        let isLast = (!turn.isLive && part.id == items.last?.id)

                        timelineRow(for: part, isFirst: isFirst, isLast: isLast)
                    }

                    if turn.isLive {
                        let isFirst = items.isEmpty
                        liveThinkingRow(isFirst: isFirst)
                            .id("bottom_anchor")
                    } else {
                        finishedFooter
                            .id("bottom_anchor")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .onChange(of: turn.activity.count) { _, _ in
                if turn.isLive {
                    withAnimation(.smooth) {
                        proxy.scrollTo("bottom_anchor", anchor: .bottom)
                    }
                }
            }
            .onChange(of: turn.activityLine) { _, _ in
                if turn.isLive {
                    withAnimation(.smooth) {
                        proxy.scrollTo("bottom_anchor", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if turn.isLive && totalCount > 0 {
                    proxy.scrollTo("bottom_anchor", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(for part: TurnPart, isFirst: Bool, isLast: Bool) -> some View {
        switch part {
        case .thinking(let block):
            ActivityTimelineEntry(isFirst: isFirst, isLast: isLast) {
                if block.isActive {
                    ActivityLivePulseDot()
                } else {
                    Circle()
                        .fill(Theme.secondaryText)
                        .frame(width: 8, height: 8)
                }
            } content: {
                ThinkingEntryView(block: block, isLatest: block.id == latestThinkingId)
            }

        case .tool(let tool):
            ActivityTimelineEntry(isFirst: isFirst, isLast: isLast) {
                ToolIconView(symbol: tool.presentation.symbol, isError: tool.isError, isRunning: tool.isRunning)
            } content: {
                ToolEntryView(tool: tool)
            }

        case .permission(let req):
            ActivityTimelineEntry(isFirst: isFirst, isLast: isLast) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 17))
                    .foregroundStyle(req.allowed == nil ? Theme.accent : Theme.secondaryText)
            } content: {
                PermissionEntryView(request: req)
            }

        case .notice(_, let text):
            ActivityTimelineEntry(isFirst: isFirst, isLast: isLast) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
            } content: {
                Text(text)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
            }

        case .error(_, let msg):
            ActivityTimelineEntry(isFirst: isFirst, isLast: isLast) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.danger)
            } content: {
                Text(msg)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.danger)
            }

        default:
            EmptyView()
        }
    }

    private func liveThinkingRow(isFirst: Bool) -> some View {
        ActivityTimelineEntry(isFirst: isFirst, isLast: true) {
            ActivityLivePulseDot()
        } content: {
            ActivityShimmerText(text: "Thinking\u{2026}", font: Theme.sans(17))
        }
    }

    private var finishedFooter: some View {
        HStack {
            Text(footerText)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
        }
        .padding(.leading, 28 + 12)
        .padding(.top, 8)
    }

    private var footerText: String {
        var parts: [String] = []

        switch turn.phase {
        case .interrupted:
            parts.append("Interrupted")
        case .error:
            parts.append("Failed")
        default:
            parts.append("Done")
        }

        if let dur = ActivityFormatters.duration(ms: turnDurationMs) {
            parts.append(dur)
        }

        if let usage = turn.usage {
            let total = usage.input + usage.output
            if total > 0 {
                if total >= 1000 {
                    let k = Double(total) / 1000.0
                    let formatted = (k >= 10.0 || total % 1000 < 50) ? String(format: "%.0fk", k) : String(format: "%.1fk", k)
                    parts.append("\(formatted) tokens")
                } else {
                    parts.append("\(total) tokens")
                }
            }

            if let cost = usage.costUsd, cost > 0 {
                parts.append(String(format: "$%.2f", cost))
            }
        }

        return parts.joined(separator: " \u{00B7} ")
    }

    private var turnDurationMs: Int? {
        if let ms = turn.durationMs, ms > 0 {
            return ms
        }
        if let finished = turn.finished {
            let diff = Int(finished.timeIntervalSince(turn.started) * 1000)
            return diff > 0 ? diff : nil
        }
        return nil
    }
}

// MARK: - Timeline Helper Views

/// Reusable timeline entry with an icon in a 28pt column and a 1pt vertical connecting hairline.
private struct ActivityTimelineEntry<Icon: View, Content: View>: View {
    let isFirst: Bool
    let isLast: Bool
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .center) {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 24, height: 24)

                icon()
            }
            .frame(width: 28, height: 28)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
        }
        .padding(.bottom, 20)
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                if isFirst {
                    Color.clear
                        .frame(width: 1, height: 14)
                } else {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1, height: 14)
                }

                if isLast {
                    Color.clear
                        .frame(width: 1)
                } else {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 1)
                }
            }
            .frame(width: 28)
        }
    }
}

/// Thinking entry with text collapsible to 4 lines.
private struct ThinkingEntryView: View {
    let block: ThinkingBlock
    let isLatest: Bool
    @State private var isExpanded = false

    var body: some View {
        if block.isActive && block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ActivityShimmerText(text: "Thinking\u{2026}", font: Theme.sans(17))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(block.text)
                    .font(Theme.sans(17))
                    .foregroundStyle(isLatest ? Theme.text : Theme.secondaryText)
                    .lineLimit(isExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)

                if needsCollapseButton {
                    Button {
                        withAnimation(.smooth) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private var needsCollapseButton: Bool {
        block.text.filter(\.isNewline).count >= 4 || block.text.count > 180
    }
}

/// Tool entry in the timeline with title, running spinner and sub-agent recursion.
private struct ToolEntryView: View {
    let tool: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                ToolCallDetailView(tool: tool)
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Text(tool.presentation.title)
                        .font(Theme.sans(17))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if tool.isRunning {
                        ProgressView()
                            .tint(Theme.secondaryText)
                            .scaleEffect(0.8)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !tool.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tool.children) { child in
                        NavigationLink {
                            ToolCallDetailView(tool: child)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: child.presentation.symbol)
                                    .font(.system(size: 14))
                                    .foregroundStyle(child.isError ? Theme.danger : Theme.secondaryText)
                                    .frame(width: 18)

                                Text(child.presentation.title)
                                    .font(Theme.sans(15))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if child.isRunning {
                                    ProgressView()
                                        .tint(Theme.secondaryText)
                                        .scaleEffect(0.7)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

/// Permission entry in the timeline.
private struct PermissionEntryView: View {
    let request: PermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(Theme.sans(17))
                .foregroundStyle(Theme.text)

            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var statusTitle: String {
        if request.allowed == nil {
            return "Waiting for approval \u{00B7} \(request.tool)"
        } else if request.allowed == true {
            return "Allowed \u{00B7} \(request.tool)"
        } else {
            return "Denied \u{00B7} \(request.tool)"
        }
    }
}

/// Tool icon with danger tint if error, pulsing if running.
private struct ToolIconView: View {
    let symbol: String
    let isError: Bool
    let isRunning: Bool
    @State private var pulsing = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17))
            .foregroundStyle(isError ? Theme.danger : Theme.secondaryText)
            .opacity(isRunning && pulsing ? 0.35 : 1.0)
            .onAppear {
                if isRunning {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulsing = true
                    }
                }
            }
    }
}

/// Small 8pt pulsating dot for active thinking.
private struct ActivityLivePulseDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.secondaryText)
            .frame(width: 8, height: 8)
            .opacity(pulsing ? 1.0 : 0.3)
            .scaleEffect(pulsing ? 1.15 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Tool Call Detail View

/// One tool call's input/output inspection view.
struct ToolCallDetailView: View {
    let tool: ToolCall
    @Environment(UIState.self) private var ui
    @State private var showAllOutput = false
    private let outputCharLimit = 20_000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerStatusSection
                inputCard
                outputCard

                if !tool.children.isEmpty {
                    subagentCard
                }
            }
            .padding(16)
        }
        .background(Theme.surface.ignoresSafeArea())
        .navigationTitle(tool.presentation.activeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let output = tool.output, !output.isEmpty {
                        UIPasteboard.general.string = output
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        ui.toast = "Copied output"
                    }
                } label: {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tool.output?.isEmpty == false ? Theme.text : Theme.tertiaryText)
                }
                .disabled(tool.output?.isEmpty != false)
                .accessibilityLabel("Copy output")
            }
        }
    }

    // MARK: Header Status

    private var headerStatusSection: some View {
        HStack(spacing: 8) {
            if tool.isRunning {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Theme.accent)
                Text("Running\u{2026}")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.accent)
            } else if tool.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.danger)
                Text("Failed")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.danger)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.success)
                Text("Completed")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.success)
            }

            if let duration = toolDurationString {
                Text("\u{00B7}")
                    .foregroundStyle(Theme.tertiaryText)
                Text(duration)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var toolDurationString: String? {
        if let finished = tool.finished {
            let sec = finished.timeIntervalSince(tool.started)
            if sec < 1.0 {
                return String(format: "%.2fs", max(0.01, sec))
            } else if sec < 60.0 {
                return String(format: "%.1fs", sec)
            } else {
                let m = Int(sec / 60)
                let s = Int(sec) % 60
                return "\(m)m \(s)s"
            }
        } else if tool.isRunning {
            let sec = max(1, Int(Date().timeIntervalSince(tool.started)))
            return "\(sec)s elapsed"
        }
        return nil
    }

    // MARK: Input Card

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input")
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)

            friendlyHeaderView

            rawInputSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var friendlyHeaderView: some View {
        let key = tool.name.lowercased()

        if isBashTool(key) {
            bashHeader
        } else if isEditTool(key) {
            editHeader
        } else if isFileTool(key) {
            fileHeader
        } else if isSearchTool(key) {
            searchHeader
        } else if isTaskTool(key) {
            taskHeader
        }
    }

    private func isBashTool(_ key: String) -> Bool {
        ["bash", "run_command", "terminal", "shell", "execute_code", "bashoutput"].contains(key)
    }

    private func isEditTool(_ key: String) -> Bool {
        ["edit", "multiedit", "replace_file_content", "multi_replace_file_content", "notebookedit"].contains(key)
    }

    private func isFileTool(_ key: String) -> Bool {
        ["read", "view_file", "read_file", "notebookread", "write", "write_to_file", "create_file"].contains(key)
    }

    private func isSearchTool(_ key: String) -> Bool {
        ["websearch", "search_web", "web_search", "webfetch", "read_url_content", "fetch", "web_extract"].contains(key)
    }

    private func isTaskTool(_ key: String) -> Bool {
        ["task", "agent", "browser_subagent", "delegate_task"].contains(key)
    }

    @ViewBuilder
    private var bashHeader: some View {
        let cmd = tool.input["command"]?.string ?? tool.input["CommandLine"]?.string ?? tool.input["cmd"]?.string
        if let cmd, !cmd.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("Command")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("$")
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.accent)
                        Text(cmd)
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                }
                .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var fileHeader: some View {
        let path = tool.input["file_path"]?.string ?? tool.input["path"]?.string ?? tool.input["AbsolutePath"]?.string ?? tool.input["TargetFile"]?.string ?? tool.input["file"]?.string
        if let path, !path.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)

                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                Text(path)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var editHeader: some View {
        let path = tool.input["file_path"]?.string ?? tool.input["path"]?.string ?? tool.input["AbsolutePath"]?.string ?? tool.input["TargetFile"]?.string
        let oldStr = tool.input["old_string"]?.string ?? tool.input["TargetContent"]?.string
        let newStr = tool.input["new_string"]?.string ?? tool.input["ReplacementContent"]?.string

        VStack(alignment: .leading, spacing: 8) {
            if let path, !path.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(path)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
            }

            if oldStr != nil || newStr != nil {
                diffView(oldStr: oldStr, newStr: newStr)
            }
        }
    }

    private func diffView(oldStr: String?, newStr: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let oldStr, !oldStr.isEmpty {
                let lines = oldStr.components(separatedBy: "\n")
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines.indices, id: \.self) { idx in
                            HStack(alignment: .top, spacing: 6) {
                                Text("-")
                                    .foregroundStyle(Theme.danger)
                                Text(lines[idx])
                                    .foregroundStyle(Theme.danger)
                            }
                            .font(Theme.mono(12))
                            .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                }
                .background(Theme.danger.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let newStr, !newStr.isEmpty {
                let lines = newStr.components(separatedBy: "\n")
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines.indices, id: \.self) { idx in
                            HStack(alignment: .top, spacing: 6) {
                                Text("+")
                                    .foregroundStyle(Theme.success)
                                Text(lines[idx])
                                    .foregroundStyle(Theme.success)
                            }
                            .font(Theme.mono(12))
                            .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                }
                .background(Theme.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private var searchHeader: some View {
        let query = tool.input["query"]?.string ?? tool.input["Query"]?.string ?? tool.input["pattern"]?.string ?? tool.input["url"]?.string ?? tool.input["Url"]?.string
        if let query, !query.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)

                Text(query)
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var taskHeader: some View {
        let desc = tool.input["description"]?.string ?? tool.input["task"]?.string
        let prompt = tool.input["prompt"]?.string ?? tool.input["Prompt"]?.string

        VStack(alignment: .leading, spacing: 6) {
            if let desc, !desc.isEmpty {
                Text(desc)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            if let prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var rawInputSection: some View {
        let text = rawInputString
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(text)
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
            }
        }
    }

    private var rawInputString: String {
        if let partial = tool.partialInput, !partial.isEmpty {
            return partial
        }
        return tool.input.prettyText
    }

    // MARK: Output Card

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tool.isError ? "Error Output" : "Output")
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(tool.isError ? Theme.danger : Theme.secondaryText)

            if let output = tool.output {
                if output.isEmpty {
                    Text("(No output)")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.tertiaryText)
                } else {
                    let isCapped = output.count > outputCharLimit
                    let textToDisplay = (isCapped && !showAllOutput) ? String(output.prefix(outputCharLimit)) : output

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(textToDisplay)
                            .font(Theme.mono(13))
                            .foregroundStyle(tool.isError ? Theme.danger : Theme.text)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.hairline, lineWidth: 1)
                    }

                    if isCapped {
                        Button {
                            showAllOutput.toggle()
                        } label: {
                            Text(showAllOutput ? "Show less" : "Show all (\(output.count) characters)")
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            } else if tool.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Theme.secondaryText)
                    Text("Waiting for tool output\u{2026}")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 8)
            }

            if !tool.images.isEmpty {
                VStack(spacing: 12) {
                    ForEach(tool.images, id: \.self) { url in
                        RemoteImageView(url: url)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if !tool.artifacts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(tool.artifacts) { artifact in
                        ArtifactCard(artifact: artifact)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }

    // MARK: Subagent Steps Card

    private var subagentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sub-agent Steps (\(tool.children.count))")
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)

            ForEach(tool.children) { child in
                NavigationLink {
                    ToolCallDetailView(tool: child)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: child.presentation.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(child.isError ? Theme.danger : Theme.secondaryText)
                            .frame(width: 20)

                        Text(child.presentation.title)
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if child.isRunning {
                            ProgressView()
                                .tint(Theme.secondaryText)
                                .scaleEffect(0.7)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(12)
                    .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Permission Card (inline in the turn)

/// Allow / Deny card for a tool permission request.
struct PermissionCard: View {
    let request: PermissionRequest
    let sessionId: String
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            keyInputView
            reasonView
            actionOrStatus
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }

    private var agentName: String {
        let session = store.session(sessionId)
        let agentId = session?.agent
        if let info = store.agent(agentId) {
            return info.name
        }
        if let kind = AgentKind(rawValue: agentId ?? "") {
            return kind.title
        }
        return "Agent"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)

            Text("\(agentName) wants to use \(request.tool)")
                .font(Theme.sans(16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var keyInputView: some View {
        if let keyInput = resolvedKeyInput, !keyInput.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(keyInput)
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
        }
    }

    private var resolvedKeyInput: String? {
        if let cmd = request.input["command"]?.string ?? request.input["CommandLine"]?.string ?? request.input["cmd"]?.string {
            return "$ \(cmd)"
        }
        if let path = request.input["file_path"]?.string ?? request.input["path"]?.string ?? request.input["AbsolutePath"]?.string ?? request.input["TargetFile"]?.string {
            return path
        }
        if let url = request.input["url"]?.string ?? request.input["Url"]?.string {
            return url
        }
        if let query = request.input["query"]?.string ?? request.input["Query"]?.string {
            return query
        }
        let pretty = request.input.prettyText
        return pretty.isEmpty ? nil : pretty
    }

    @ViewBuilder
    private var reasonView: some View {
        if let reason = request.reason, !reason.isEmpty {
            Text(reason)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionOrStatus: some View {
        if let allowed = request.allowed {
            HStack(spacing: 8) {
                Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(allowed ? Theme.success : Theme.danger)

                Text(allowed ? "Allowed" : "Denied")
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(allowed ? Theme.success : Theme.danger)

                Spacer()
            }
            .padding(.top, 4)
        } else {
            GlassEffectContainer {
                HStack(spacing: 12) {
                    Button("Deny") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        store.answer(request, in: sessionId, allow: false)
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)

                    Button("Allow") {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        store.answer(request, in: sessionId, allow: true)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Shimmer Text & Formatters

/// Text with an ivory highlight sweeping left to right on a secondaryText base in a 1.6s loop.
struct ActivityShimmerText: View {
    let text: String
    var font: Font = Theme.sans(16)
    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    let bandWidth = max(60, width * 0.4)
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Theme.text, location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: -bandWidth + phase * (width + bandWidth * 2))
                }
                .mask {
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private enum ActivityFormatters {
    static func duration(ms: Int?) -> String? {
        guard let ms, ms > 0 else { return nil }
        let totalSeconds = max(1, Int(round(Double(ms) / 1000.0)))
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else {
            let mins = totalSeconds / 60
            let secs = totalSeconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        }
    }
}
