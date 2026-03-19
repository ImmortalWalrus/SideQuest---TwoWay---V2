import SwiftUI

struct CharacterEffectView: View {
    let effectName: String
    let diameter: CGFloat

    private let markerAngles: [Double] = [0, 120, 240]

    var body: some View {
        ZStack {
            switch effectName {
            case "Fire Aura":
                fireAura
            case "Lightning":
                lightningAura
            case "Frost Ring":
                frostAura
            default:
                EmptyView()
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fireAura: some View {
        ZStack {
            Circle()
                .stroke(.linearGradient(colors: [.yellow.opacity(0.55), .orange.opacity(0.9), .red.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: diameter * 0.12)
                .blur(radius: diameter * 0.04)

            Circle()
                .stroke(.linearGradient(colors: [.yellow.opacity(0.85), .orange, .red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: diameter * 0.035)

            ForEach(Array(markerAngles.enumerated()), id: \.offset) { index, angle in
                Image(systemName: index == 1 ? "sparkles" : "flame.fill")
                    .font(.system(size: diameter * 0.12, weight: .bold))
                    .foregroundStyle(index == 1 ? .yellow : .orange, .red)
                    .offset(y: -diameter * 0.46)
                    .rotationEffect(.degrees(angle))
            }
        }
    }

    private var lightningAura: some View {
        ZStack {
            Circle()
                .stroke(.yellow.opacity(0.18), lineWidth: diameter * 0.13)
                .blur(radius: diameter * 0.05)

            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(.linearGradient(colors: [.white, .yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: diameter * 0.04, lineCap: .round, dash: [diameter * 0.08, diameter * 0.05]))
                .rotationEffect(.degrees(-18))

            Image(systemName: "bolt.fill")
                .font(.system(size: diameter * 0.18, weight: .black))
                .foregroundStyle(.yellow, .white)
                .offset(y: -diameter * 0.48)

            Image(systemName: "bolt.fill")
                .font(.system(size: diameter * 0.14, weight: .black))
                .foregroundStyle(.yellow, .orange)
                .offset(x: diameter * 0.34, y: diameter * 0.26)
        }
    }

    private var frostAura: some View {
        ZStack {
            Circle()
                .stroke(.cyan.opacity(0.2), lineWidth: diameter * 0.12)
                .blur(radius: diameter * 0.04)

            Circle()
                .stroke(.linearGradient(colors: [.white.opacity(0.95), .cyan, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: diameter * 0.035)

            ForEach(Array(markerAngles.enumerated()), id: \.offset) { _, angle in
                Image(systemName: "snowflake")
                    .font(.system(size: diameter * 0.11, weight: .semibold))
                    .foregroundStyle(.white, .cyan)
                    .offset(y: -diameter * 0.46)
                    .rotationEffect(.degrees(angle))
            }
        }
    }
}
