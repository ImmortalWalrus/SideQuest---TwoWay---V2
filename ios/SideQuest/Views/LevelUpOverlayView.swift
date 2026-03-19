import SwiftUI

struct LevelUpOverlayView: View {
    let level: Int
    let onDismiss: () -> Void

    @State private var appeared: Bool = false
    @State private var showRing: Bool = false
    @State private var showText: Bool = false
    @State private var showButton: Bool = false
    @State private var particlePhase: Int = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            particleField

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .strokeBorder(
                                AngularGradient(
                                    colors: [.orange, .yellow, .orange.opacity(0.3), .orange],
                                    center: .center
                                ),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(160 + i * 40), height: CGFloat(160 + i * 40))
                            .scaleEffect(showRing ? 1 : 0.2)
                            .opacity(showRing ? Double(3 - i) * 0.2 : 0)
                            .rotationEffect(.degrees(showRing ? Double(i) * 120 : 0))
                    }

                    Circle()
                        .fill(.orange.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .scaleEffect(appeared ? 1.15 : 0.5)
                        .opacity(appeared ? 0.7 : 0)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.yellow, .orange],
                                center: .center,
                                startRadius: 10,
                                endRadius: 55
                            )
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(appeared ? 1 : 0.1)
                        .shadow(color: .orange.opacity(0.6), radius: appeared ? 30 : 0)

                    Image(systemName: LevelSystem.iconName(for: level))
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .symbolEffect(.bounce.up, value: appeared)
                        .scaleEffect(appeared ? 1 : 0.3)
                }

                VStack(spacing: 10) {
                    Text("LEVEL UP!")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(.orange)
                        .opacity(showText ? 1 : 0)
                        .scaleEffect(showText ? 1 : 0.5)

                    Text("\(level)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .orange.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .orange.opacity(0.4), radius: 12)
                        .opacity(showText ? 1 : 0)
                        .offset(y: showText ? 0 : 30)

                    Text(LevelSystem.title(for: level))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .opacity(showText ? 1 : 0)
                        .offset(y: showText ? 0 : 15)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 20)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5).delay(0.2)) {
                showRing = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.4)) {
                showText = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.8)) {
                showButton = true
            }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                particlePhase += 1
            }
        }
        .sensoryFeedback(.success, trigger: appeared)
        .sensoryFeedback(.impact(weight: .heavy), trigger: showText)
    }

    private var particleField: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let centerY = size.height * 0.35

            for i in 0..<24 {
                let angle = Double(i) * (360.0 / 24.0) * .pi / 180
                let baseRadius: Double = appeared ? Double.random(in: 80...200) : 20
                let x = centerX + cos(angle) * baseRadius
                let y = centerY + sin(angle) * baseRadius

                let sparkSize: CGFloat = CGFloat.random(in: 3...7)
                let rect = CGRect(x: x - sparkSize / 2, y: y - sparkSize / 2, width: sparkSize, height: sparkSize)
                let colors: [Color] = [.orange, .yellow, .white]
                let color = colors[i % colors.count]
                context.fill(
                    Circle().path(in: rect),
                    with: .color(color.opacity(appeared ? Double.random(in: 0.3...0.8) : 0))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
