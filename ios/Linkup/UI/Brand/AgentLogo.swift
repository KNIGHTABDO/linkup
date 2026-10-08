import SwiftUI

/// The agent's real brand mark: the Claude spark, Antigravity's arch, and Nous Research's mark for Hermes
/// (monochrome, tinted ivory). Use this everywhere an agent appears.
struct AgentLogo: View {
    let agent: String
    var size: CGFloat = 22

    private var label: String {
        switch agent {
        case "claude": return "Claude"
        case "agy": return "Antigravity"
        case "hermes": return "Hermes"
        default: return "Agent"
        }
    }

    var body: some View {
        Group {
            switch agent {
            case "claude":
                Image("LogoClaude").resizable().scaledToFit()
            case "agy":
                Image("LogoAntigravity").resizable().scaledToFit()
            case "hermes":
                Image("LogoHermes").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(Theme.text)
            default:
                Image(systemName: "circle.dashed").font(.system(size: size * 0.8)).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }
}
