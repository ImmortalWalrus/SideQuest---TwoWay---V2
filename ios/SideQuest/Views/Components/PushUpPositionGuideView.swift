import SwiftUI

struct PushUpPositionGuideView: View {
    let bodyDetected: Bool
    let armsVisible: Bool
    let goodDistance: Bool
    let accentColor: Color
    @State private var breathe: Bool = false

    var body: some View {
        ZStack {
            ghostSilhouette
                .opacity(bodyDetected ? 0.15 : 0.4)
                .animation(.easeInOut(duration: 0.5), value: bodyDetected)

            VStack {
                Spacer()

                positioningChecklist
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var ghostSilhouette: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let headCenter = CGPoint(x: w * 0.25, y: h * 0.35)
            let shoulderPt = CGPoint(x: w * 0.32, y: h * 0.42)
            let elbowPt = CGPoint(x: w * 0.30, y: h * 0.55)
            let wristPt = CGPoint(x: w * 0.28, y: h * 0.65)
            let hipPt = CGPoint(x: w * 0.55, y: h * 0.42)
            let kneePt = CGPoint(x: w * 0.72, y: h * 0.50)
            let anklePt = CGPoint(x: w * 0.85, y: h * 0.58)

            let joints = [headCenter, shoulderPt, elbowPt, wristPt, hipPt, kneePt, anklePt]
            let connections: [(Int, Int)] = [
                (0, 1), (1, 2), (2, 3), (1, 4), (4, 5), (5, 6)
            ]

            let lineColor = accentColor.resolve(in: .init())
            let shading: GraphicsContext.Shading = .color(
                Color(red: Double(lineColor.red), green: Double(lineColor.green), blue: Double(lineColor.blue)).opacity(0.6)
            )

            for (a, b) in connections {
                var path = Path()
                path.move(to: joints[a])
                path.addLine(to: joints[b])
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            let dotShading: GraphicsContext.Shading = .color(
                Color(red: Double(lineColor.red), green: Double(lineColor.green), blue: Double(lineColor.blue)).opacity(0.8)
            )
            for joint in joints {
                let rect = CGRect(x: joint.x - 6, y: joint.y - 6, width: 12, height: 12)
                context.fill(Circle().path(in: rect), with: dotShading)
            }

            let headRect = CGRect(x: headCenter.x - 14, y: headCenter.y - 14, width: 28, height: 28)
            context.stroke(Circle().path(in: headRect), with: dotShading, lineWidth: 3)
        }
        .scaleEffect(breathe ? 1.01 : 0.99)
    }

    private var positioningChecklist: some View {
        HStack(spacing: 12) {
            checkItem(label: "Body", checked: bodyDetected, icon: "person.fill")
            checkItem(label: "Arms", checked: armsVisible, icon: "figure.arms.open")
            checkItem(label: "Distance", checked: goodDistance, icon: "arrow.left.and.right")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func checkItem(label: String, checked: Bool, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(checked ? .green : .white.opacity(0.4))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(checked ? .white : .white.opacity(0.4))
        }
        .animation(.spring(response: 0.3), value: checked)
    }
}
