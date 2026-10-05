import SwiftUI

/// STUB (task logos): the agent's real brand mark (Claude spark, Antigravity, Hermes/Nous). Use this everywhere an
/// agent appears instead of SF Symbols.
struct AgentLogo: View {
    let agent: String
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: AgentKind(rawValue: agent)?.symbol ?? "circle")
            .font(.system(size: size * 0.8, weight: .semibold))
            .foregroundStyle(Theme.agentColor(agent))
            .frame(width: size, height: size)
    }
}
