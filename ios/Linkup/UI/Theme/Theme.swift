import SwiftUI

/// Claude-app palette and type: warm near-black surfaces, ivory text, the Claude orange, serif for the agent's voice.
enum Theme {
    static let background = Color(red: 0x1F / 255, green: 0x1E / 255, blue: 0x1D / 255)       // #1F1E1D
    static let surface = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x24 / 255)          // #262624
    static let elevated = Color(red: 0x30 / 255, green: 0x30 / 255, blue: 0x2E / 255)         // #30302E
    static let userBubble = Color(red: 0x38 / 255, green: 0x37 / 255, blue: 0x34 / 255)       // #383734
    static let hairline = Color.white.opacity(0.08)
    static let text = Color(red: 0xF0 / 255, green: 0xEE / 255, blue: 0xE6 / 255)             // ivory
    static let secondaryText = Color(red: 0xA6 / 255, green: 0xA3 / 255, blue: 0x9A / 255)
    static let tertiaryText = Color(red: 0x73 / 255, green: 0x71 / 255, blue: 0x6B / 255)
    static let accent = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)           // Claude orange #D97757
    static let artifactTile = Color(red: 0x2B / 255, green: 0x24 / 255, blue: 0x5C / 255)     // indigo artifact chip
    static let danger = Color(red: 0xE5 / 255, green: 0x5B / 255, blue: 0x4F / 255)
    static let success = Color(red: 0x6F / 255, green: 0xB3 / 255, blue: 0x7E / 255)
    static let link = Color(red: 0x7F / 255, green: 0xB0 / 255, blue: 0xF5 / 255)

    /// Agent voice (responses, greeting): serif like the Claude app.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// UI chrome and the user's own words: SF Pro.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

    static let margin: CGFloat = 18
    static let bubbleRadius: CGFloat = 22
    static let composerRadius: CGFloat = 28

    static func agentColor(_ agent: String?) -> Color {
        switch agent {
        case "agy": Color(red: 0.42, green: 0.62, blue: 0.98)
        case "hermes": Color(red: 0.75, green: 0.6, blue: 0.95)
        default: accent
        }
    }
}

/// The Claude-style asterisk "spark" (12 rounded rays). `phase` 0…1 rotates/pulses it while the agent works.
struct SparkShape: Shape {
    var rays = 12
    var phase: Double = 0

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let width = r * 0.16
        for i in 0..<rays {
            let angle = Double(i) / Double(rays) * 2 * .pi + phase * 2 * .pi / Double(rays) + 0.13
            let length = r * (i % 2 == 0 ? 1.0 : 0.82) * (1 - 0.08 * sin(phase * 2 * .pi + Double(i)))
            let end = CGPoint(x: c.x + cos(angle) * length, y: c.y + sin(angle) * length)
            var ray = Path()
            ray.move(to: c)
            ray.addLine(to: end)
            path.addPath(ray.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round)))
        }
        return path
    }
}

/// The spark in Claude orange; spins gently while `animating`.
struct SparkView: View {
    var size: CGFloat = 40
    var animating = false
    @State private var phase = 0.0

    var body: some View {
        SparkShape(phase: phase)
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .onAppear { if animating { start() } }
            .onChange(of: animating) { _, on in if on { start() } else { withAnimation(.smooth) { phase = 0 } } }
            .accessibilityHidden(true)
    }

    private func start() {
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { phase = 1 }
    }
}

/// Three dots pulsing in orange: "the agent is working" (Claude app's typing indicator).
struct WorkingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                    .opacity(on ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18), value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityLabel("Working")
    }
}
