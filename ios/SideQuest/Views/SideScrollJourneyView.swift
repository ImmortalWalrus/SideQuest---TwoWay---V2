import SwiftUI

struct SideScrollJourneyView: View {
    let appState: AppState
    @State private var scrollOffset: CGFloat = 0
    @State private var animateWalkers: Bool = false

    private let sceneWidth: CGFloat = 2400
    private let sceneHeight: CGFloat = 280

    private var journeyTravelers: [JourneyTraveler] {
        var travelers: [JourneyTraveler] = []

        let userLevel = appState.profile.level
        let maxLevel = max(userLevel, 1)
        let userProgress = min(0.9, max(0.1, Double(userLevel) / Double(maxLevel + 10)))

        travelers.append(JourneyTraveler(
            id: "self",
            username: appState.profile.username,
            loadout: appState.profile.spriteLoadout,
            level: userLevel,
            progressX: userProgress,
            isUser: true
        ))

        let realFriends = appState.acceptedFriends
        for (i, friend) in realFriends.prefix(5).enumerated() {
            let friendLevel = LevelSystem.level(for: friend.totalScore)
            let friendProgress = min(0.9, max(0.05, Double(friendLevel) / Double(maxLevel + 10)))
            let jitter = Double(i) * 0.06 - 0.12
            travelers.append(JourneyTraveler(
                id: friend.id,
                username: friend.username,
                loadout: .default,
                level: friendLevel,
                progressX: max(0.05, min(0.95, friendProgress + jitter)),
                isUser: false
            ))
        }

        return travelers.sorted { $0.progressX < $1.progressX }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundStyle(.orange)
                Text("Quest")
                    .font(.title3.weight(.bold))
                Spacer()
                Text(journeyTravelers.count > 1 ? "\(journeyTravelers.count) travelers" : "Solo journey")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                ZStack(alignment: .bottomLeading) {
                    skyBackground
                    mountainsLayer
                    groundLayer
                    pathLine
                    travelersLayer
                    decorationsLayer
                }
                .frame(width: sceneWidth, height: sceneHeight)
                .clipShape(.rect(cornerRadius: 16))
            }
            .contentMargins(.horizontal, 16)
            .scrollIndicators(.hidden)
            .onAppear {
                animateWalkers = true
            }
        }
    }

    private var skyBackground: some View {
        Canvas { context, canvasSize in
            let skyGradient = Gradient(colors: [
                Color(red: 0.1, green: 0.08, blue: 0.2),
                Color(red: 0.15, green: 0.1, blue: 0.35),
                Color(red: 0.25, green: 0.15, blue: 0.45),
                Color(red: 0.4, green: 0.2, blue: 0.5),
            ])
            context.fill(
                Rectangle().path(in: CGRect(origin: .zero, size: canvasSize)),
                with: .linearGradient(skyGradient, startPoint: .init(x: 0, y: 0), endPoint: .init(x: 0, y: canvasSize.height))
            )

            let starPositions: [(CGFloat, CGFloat, CGFloat)] = [
                (0.05, 0.1, 2), (0.12, 0.25, 1.5), (0.18, 0.08, 2.5),
                (0.25, 0.2, 1), (0.33, 0.05, 2), (0.4, 0.15, 1.5),
                (0.48, 0.22, 2), (0.55, 0.08, 1), (0.62, 0.18, 2.5),
                (0.7, 0.12, 1.5), (0.78, 0.06, 2), (0.85, 0.2, 1),
                (0.92, 0.1, 2), (0.08, 0.35, 1), (0.38, 0.3, 1.5),
                (0.65, 0.28, 1), (0.88, 0.32, 2),
            ]
            for (px, py, r) in starPositions {
                let rect = CGRect(x: canvasSize.width * px, y: canvasSize.height * py, width: r, height: r)
                context.fill(Circle().path(in: rect), with: .color(.white.opacity(0.8)))
            }

            let moonRect = CGRect(x: canvasSize.width * 0.82, y: 20, width: 40, height: 40)
            context.fill(Circle().path(in: moonRect), with: .color(Color(red: 0.95, green: 0.9, blue: 0.7).opacity(0.9)))
            let moonShadow = CGRect(x: canvasSize.width * 0.82 + 8, y: 18, width: 36, height: 36)
            context.fill(Circle().path(in: moonShadow), with: .color(Color(red: 0.1, green: 0.08, blue: 0.2)))
        }
        .frame(width: sceneWidth, height: sceneHeight)
        .allowsHitTesting(false)
    }

    private var mountainsLayer: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            var backMountains = Path()
            backMountains.move(to: CGPoint(x: 0, y: h * 0.55))
            let backPeaks: [(CGFloat, CGFloat)] = [
                (0.08, 0.3), (0.18, 0.2), (0.28, 0.35), (0.38, 0.15),
                (0.5, 0.28), (0.6, 0.18), (0.72, 0.32), (0.82, 0.22),
                (0.92, 0.3), (1.0, 0.4),
            ]
            for (px, py) in backPeaks {
                backMountains.addLine(to: CGPoint(x: w * px, y: h * py))
            }
            backMountains.addLine(to: CGPoint(x: w, y: h * 0.55))
            backMountains.closeSubpath()
            context.fill(backMountains, with: .color(Color(red: 0.15, green: 0.12, blue: 0.25).opacity(0.8)))

            var frontMountains = Path()
            frontMountains.move(to: CGPoint(x: 0, y: h * 0.6))
            let frontPeaks: [(CGFloat, CGFloat)] = [
                (0.1, 0.42), (0.22, 0.35), (0.32, 0.45), (0.45, 0.3),
                (0.55, 0.4), (0.68, 0.32), (0.78, 0.42), (0.88, 0.36),
                (1.0, 0.48),
            ]
            for (px, py) in frontPeaks {
                frontMountains.addLine(to: CGPoint(x: w * px, y: h * py))
            }
            frontMountains.addLine(to: CGPoint(x: w, y: h * 0.6))
            frontMountains.closeSubpath()
            context.fill(frontMountains, with: .color(Color(red: 0.18, green: 0.15, blue: 0.3).opacity(0.9)))
        }
        .frame(width: sceneWidth, height: sceneHeight)
        .allowsHitTesting(false)
    }

    private var groundLayer: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: h * 0.62))
            ground.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.58), control: CGPoint(x: w * 0.12, y: h * 0.56))
            ground.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.64), control: CGPoint(x: w * 0.38, y: h * 0.68))
            ground.addQuadCurve(to: CGPoint(x: w * 0.75, y: h * 0.6), control: CGPoint(x: w * 0.62, y: h * 0.56))
            ground.addQuadCurve(to: CGPoint(x: w, y: h * 0.62), control: CGPoint(x: w * 0.88, y: h * 0.66))
            ground.addLine(to: CGPoint(x: w, y: h))
            ground.addLine(to: CGPoint(x: 0, y: h))
            ground.closeSubpath()

            context.fill(ground, with: .color(Color(red: 0.12, green: 0.22, blue: 0.1)))

            var grassTop = Path()
            grassTop.move(to: CGPoint(x: 0, y: h * 0.62))
            grassTop.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.58), control: CGPoint(x: w * 0.12, y: h * 0.56))
            grassTop.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.64), control: CGPoint(x: w * 0.38, y: h * 0.68))
            grassTop.addQuadCurve(to: CGPoint(x: w * 0.75, y: h * 0.6), control: CGPoint(x: w * 0.62, y: h * 0.56))
            grassTop.addQuadCurve(to: CGPoint(x: w, y: h * 0.62), control: CGPoint(x: w * 0.88, y: h * 0.66))
            grassTop.addLine(to: CGPoint(x: w, y: h * 0.67))
            grassTop.addLine(to: CGPoint(x: 0, y: h * 0.67))
            grassTop.closeSubpath()
            context.fill(grassTop, with: .color(Color(red: 0.15, green: 0.3, blue: 0.12)))
        }
        .frame(width: sceneWidth, height: sceneHeight)
        .allowsHitTesting(false)
    }

    private var pathLine: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            var road = Path()
            road.move(to: CGPoint(x: 0, y: h * 0.72))
            road.addQuadCurve(to: CGPoint(x: w * 0.2, y: h * 0.68), control: CGPoint(x: w * 0.1, y: h * 0.66))
            road.addQuadCurve(to: CGPoint(x: w * 0.4, y: h * 0.74), control: CGPoint(x: w * 0.3, y: h * 0.78))
            road.addQuadCurve(to: CGPoint(x: w * 0.6, y: h * 0.7), control: CGPoint(x: w * 0.5, y: h * 0.66))
            road.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.74), control: CGPoint(x: w * 0.7, y: h * 0.78))
            road.addQuadCurve(to: CGPoint(x: w, y: h * 0.7), control: CGPoint(x: w * 0.9, y: h * 0.66))
            context.stroke(road, with: .color(Color(red: 0.35, green: 0.28, blue: 0.18).opacity(0.8)), lineWidth: 18)
            context.stroke(road, with: .color(Color(red: 0.45, green: 0.38, blue: 0.25).opacity(0.6)), lineWidth: 10)

            let dashCount = 30
            for i in 0..<dashCount {
                let t = CGFloat(i) / CGFloat(dashCount)
                let x = w * t
                let y = pathY(at: t, height: h)
                let dashRect = CGRect(x: x - 3, y: y - 1, width: 6, height: 2)
                context.fill(RoundedRectangle(cornerRadius: 1).path(in: dashRect), with: .color(.white.opacity(0.15)))
            }
        }
        .frame(width: sceneWidth, height: sceneHeight)
        .allowsHitTesting(false)
    }

    private var travelersLayer: some View {
        ZStack {
            ForEach(journeyTravelers) { traveler in
                let xPos = sceneWidth * traveler.progressX
                let yPos = pathY(at: traveler.progressX, height: sceneHeight) - 50

                VStack(spacing: 2) {
                    if traveler.isUser {
                        Text("YOU")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.2), in: Capsule())
                    }

                    Text(traveler.username)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2)

                    HStack(spacing: 2) {
                        Image(systemName: LevelSystem.iconName(for: traveler.level))
                            .font(.system(size: 7))
                            .foregroundStyle(.orange)
                        Text("Lv\(traveler.level)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    SpriteAvatarView(
                        loadout: traveler.loadout,
                        size: 64,
                        isWalking: animateWalkers,
                        facingRight: true
                    )
                }
                .position(x: xPos, y: yPos)
            }
        }
        .frame(width: sceneWidth, height: sceneHeight)
    }

    private var decorationsLayer: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            let treePositions: [(CGFloat, CGFloat)] = [
                (0.03, 0.54), (0.15, 0.5), (0.27, 0.56), (0.42, 0.52),
                (0.58, 0.54), (0.73, 0.5), (0.87, 0.56), (0.95, 0.52),
            ]
            for (px, py) in treePositions {
                let tx = w * px
                let ty = h * py
                let trunkRect = CGRect(x: tx - 3, y: ty, width: 6, height: 20)
                context.fill(RoundedRectangle(cornerRadius: 2).path(in: trunkRect), with: .color(Color(red: 0.35, green: 0.25, blue: 0.15)))

                var foliage = Path()
                foliage.move(to: CGPoint(x: tx - 12, y: ty + 2))
                foliage.addLine(to: CGPoint(x: tx, y: ty - 22))
                foliage.addLine(to: CGPoint(x: tx + 12, y: ty + 2))
                foliage.closeSubpath()
                context.fill(foliage, with: .color(Color(red: 0.1, green: 0.35, blue: 0.12)))

                var foliage2 = Path()
                foliage2.move(to: CGPoint(x: tx - 10, y: ty - 8))
                foliage2.addLine(to: CGPoint(x: tx, y: ty - 30))
                foliage2.addLine(to: CGPoint(x: tx + 10, y: ty - 8))
                foliage2.closeSubpath()
                context.fill(foliage2, with: .color(Color(red: 0.12, green: 0.4, blue: 0.15)))
            }

            let signX = w * 0.08
            let signY = h * 0.58
            let postRect = CGRect(x: signX - 2, y: signY, width: 4, height: 20)
            context.fill(RoundedRectangle(cornerRadius: 1).path(in: postRect), with: .color(Color(red: 0.4, green: 0.3, blue: 0.2)))
            let signRect = CGRect(x: signX - 12, y: signY - 10, width: 24, height: 12)
            context.fill(RoundedRectangle(cornerRadius: 2).path(in: signRect), with: .color(Color(red: 0.5, green: 0.38, blue: 0.25)))

            let flagX = w * 0.95
            let flagY = h * 0.52
            let poleRect = CGRect(x: flagX - 2, y: flagY - 10, width: 4, height: 30)
            context.fill(RoundedRectangle(cornerRadius: 1).path(in: poleRect), with: .color(Color(white: 0.6)))
            var flag = Path()
            flag.move(to: CGPoint(x: flagX + 2, y: flagY - 10))
            flag.addLine(to: CGPoint(x: flagX + 20, y: flagY - 4))
            flag.addLine(to: CGPoint(x: flagX + 2, y: flagY + 2))
            flag.closeSubpath()
            context.fill(flag, with: .color(.orange))
        }
        .frame(width: sceneWidth, height: sceneHeight)
        .allowsHitTesting(false)
    }

    private func pathY(at t: CGFloat, height: CGFloat) -> CGFloat {
        let h = height
        let baseY = h * 0.72
        let wave1 = sin(t * .pi * 2) * h * 0.03
        let wave2 = sin(t * .pi * 4 + 1) * h * 0.02
        return baseY + wave1 + wave2
    }
}

struct JourneyTraveler: Identifiable {
    let id: String
    let username: String
    let loadout: SpriteLoadout
    let level: Int
    let progressX: CGFloat
    let isUser: Bool
}
