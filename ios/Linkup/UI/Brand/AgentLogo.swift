import SwiftUI

/// The agent's real brand mark: the Claude spark, Antigravity's arch, and Nous Research's mark for Hermes
/// (monochrome, tinted ivory). Use this everywhere an agent appears.
struct AgentLogo: View {
    let agent: String
    var size: CGFloat = 22

    var body: some View {
        switch agent {
        case "claude":
            Image("LogoClaude").resizable().scaledToFit().frame(width: size, height: size)
        case "agy":
            Image("LogoAntigravity").resizable().scaledToFit().frame(width: size, height: size)
        case "hermes":
            Image("LogoHermes").renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Theme.text)
                .frame(width: size, height: size)
        default:
            Image(systemName: "circle.dashed").font(.system(size: size * 0.8)).foregroundStyle(Theme.secondaryText)
                .frame(width: size, height: size)
        }
    }
}
