import ActivityKit
import SwiftUI
import WidgetKit

struct LinkupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LinkupActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        SparkShape(rays: 12, phase: 0)
                            .fill(Theme.agentColor(context.attributes.agent))
                            .frame(width: 16, height: 16)
                        Text(context.attributes.agent.capitalized)
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.finished == nil {
                        Text(timerInterval: context.state.started...Date.distantFuture, countsDown: false)
                            .monospacedDigit()
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("Done")
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.success)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.line)
                            .font(Theme.serif(13))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)

                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.tertiaryText)
                                Text("\(context.state.steps) \(context.state.steps == 1 ? "step" : "steps")")
                                    .font(Theme.sans(11, weight: .medium))
                                    .foregroundStyle(Theme.tertiaryText)
                            }

                            if context.state.tokens > 0 {
                                Text("•")
                                    .font(Theme.sans(10))
                                    .foregroundStyle(Theme.tertiaryText)
                                Text("\(context.state.tokens) tok")
                                    .font(Theme.sans(11, weight: .medium))
                                    .foregroundStyle(Theme.tertiaryText)
                            }

                            Spacer()

                            if context.state.finished == nil {
                                Button(intent: StopTurnIntent(sessionId: context.attributes.sessionId)) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "stop.fill")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("Stop")
                                            .font(Theme.sans(12, weight: .semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Theme.danger.opacity(0.18), in: Capsule())
                                    .foregroundStyle(Theme.danger)
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                    Text("Finished")
                                        .font(Theme.sans(12, weight: .medium))
                                }
                                .foregroundStyle(Theme.success)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                SparkShape(rays: 12, phase: 0)
                    .fill(Theme.agentColor(context.attributes.agent))
                    .frame(width: 14, height: 14)
            } compactTrailing: {
                if context.state.finished == nil {
                    Text(timerInterval: context.state.started...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: 44)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.success)
                }
            } minimal: {
                SparkShape(rays: 12, phase: 0)
                    .fill(Theme.agentColor(context.attributes.agent))
                    .frame(width: 14, height: 14)
            }
        }
    }
}

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<LinkupActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SparkShape(rays: 12, phase: 0)
                    .fill(Theme.agentColor(context.attributes.agent))
                    .frame(width: 18, height: 18)

                Text(context.attributes.title)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer()

                if context.state.finished == nil {
                    Text(timerInterval: context.state.started...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("Done")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.success)
                }
            }

            Text(context.state.line)
                .font(Theme.serif(14))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("\(context.state.steps) \(context.state.steps == 1 ? "step" : "steps")")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.tertiaryText)

                if context.state.tokens > 0 {
                    Text("•")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("\(context.state.tokens) tokens")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                }

                Spacer()

                if context.state.finished == nil {
                    Button(intent: StopTurnIntent(sessionId: context.attributes.sessionId)) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Stop")
                                .font(Theme.sans(12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.danger.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(Theme.background)
        .activitySystemActionForegroundColor(Theme.accent)
    }
}
