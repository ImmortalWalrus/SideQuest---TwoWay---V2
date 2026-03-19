import SwiftUI

struct SpriteAvatarView: View {
    let loadout: SpriteLoadout
    let size: CGFloat
    var isWalking: Bool = false
    var facingRight: Bool = true

    @State private var walkCycle: Bool = false

    private var scale: CGFloat { size / 120 }
    private var skinColor: Color { loadout.bodyColor.color }
    private var skinShadow: Color { loadout.bodyColor.color.opacity(0.7) }

    private func cosmeticItem(for slot: SpriteSlot) -> SpriteCosmeticItem? {
        guard let id = loadout.item(for: slot) else { return nil }
        return SpriteCosmeticsCatalog.item(withId: id)
    }

    var body: some View {
        ZStack {
            if let auraItem = cosmeticItem(for: .aura) {
                auraLayer(auraItem)
            }
            capeLayer
            spriteBody
            weaponLayer
            hatLayer
        }
        .frame(width: size, height: size)
        .scaleEffect(x: facingRight ? 1 : -1, y: 1)
        .onAppear {
            if isWalking {
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                    walkCycle = true
                }
            }
        }
        .onChange(of: isWalking) { _, newVal in
            if newVal {
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                    walkCycle = true
                }
            } else {
                walkCycle = false
            }
        }
    }

    private var spriteBody: some View {
        Canvas { context, canvasSize in
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let s = min(canvasSize.width, canvasSize.height) / 120

            let legSwing: CGFloat = isWalking ? (walkCycle ? 12 : -12) : 0
            let armSwing: CGFloat = isWalking ? (walkCycle ? -15 : 15) : 0
            let bodyBob: CGFloat = isWalking ? (walkCycle ? -2 : 2) : 0

            drawLegs(context: context, cx: cx, cy: cy + bodyBob, s: s, swing: legSwing)
            drawShoes(context: context, cx: cx, cy: cy + bodyBob, s: s, swing: legSwing)
            drawTorso(context: context, cx: cx, cy: cy + bodyBob, s: s)
            drawArms(context: context, cx: cx, cy: cy + bodyBob, s: s, swing: armSwing)
            drawHead(context: context, cx: cx, cy: cy + bodyBob, s: s)
            drawHair(context: context, cx: cx, cy: cy + bodyBob, s: s)
            drawFace(context: context, cx: cx, cy: cy + bodyBob, s: s)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func drawHead(context: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let headRect = CGRect(x: cx - 14 * s, y: cy - 48 * s, width: 28 * s, height: 28 * s)
        context.fill(
            RoundedRectangle(cornerRadius: 6 * s).path(in: headRect),
            with: .color(skinColor)
        )
    }

    private func drawFace(context: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let eyeY = cy - 38 * s
        let leftEye = CGRect(x: cx - 8 * s, y: eyeY, width: 4 * s, height: 5 * s)
        let rightEye = CGRect(x: cx + 4 * s, y: eyeY, width: 4 * s, height: 5 * s)
        context.fill(Ellipse().path(in: leftEye), with: .color(Color(white: 0.1)))
        context.fill(Ellipse().path(in: rightEye), with: .color(Color(white: 0.1)))

        let mouthRect = CGRect(x: cx - 4 * s, y: cy - 30 * s, width: 8 * s, height: 2 * s)
        context.fill(
            RoundedRectangle(cornerRadius: 1 * s).path(in: mouthRect),
            with: .color(Color(red: 0.8, green: 0.4, blue: 0.3))
        )
    }

    private func drawHair(context: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        guard let hairItem = cosmeticItem(for: .hair) else { return }
        let hairColor = hairItem.colors.first ?? Color(white: 0.15)

        switch hairItem.id {
        case "spiky_black", "spiky_blonde":
            let baseRect = CGRect(x: cx - 15 * s, y: cy - 52 * s, width: 30 * s, height: 10 * s)
            context.fill(
                RoundedRectangle(cornerRadius: 3 * s).path(in: baseRect),
                with: .color(hairColor)
            )
            for i in 0..<5 {
                let spikeX = cx - 12 * s + CGFloat(i) * 6 * s
                var path = Path()
                path.move(to: CGPoint(x: spikeX, y: cy - 52 * s))
                path.addLine(to: CGPoint(x: spikeX + 3 * s, y: cy - 62 * s - CGFloat(i % 2 == 0 ? 4 : 0) * s))
                path.addLine(to: CGPoint(x: spikeX + 6 * s, y: cy - 52 * s))
                path.closeSubpath()
                context.fill(path, with: .color(hairColor))
            }
        case "flow_brown":
            let baseRect = CGRect(x: cx - 16 * s, y: cy - 52 * s, width: 32 * s, height: 14 * s)
            context.fill(
                RoundedRectangle(cornerRadius: 6 * s).path(in: baseRect),
                with: .color(hairColor)
            )
            let sideLeft = CGRect(x: cx - 17 * s, y: cy - 46 * s, width: 6 * s, height: 16 * s)
            let sideRight = CGRect(x: cx + 11 * s, y: cy - 46 * s, width: 6 * s, height: 16 * s)
            context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: sideLeft), with: .color(hairColor))
            context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: sideRight), with: .color(hairColor))
        case "mohawk_red":
            for i in 0..<7 {
                let spikeX = cx - 9 * s + CGFloat(i) * 3 * s
                var path = Path()
                path.move(to: CGPoint(x: spikeX, y: cy - 48 * s))
                path.addLine(to: CGPoint(x: spikeX + 1.5 * s, y: cy - 66 * s))
                path.addLine(to: CGPoint(x: spikeX + 3 * s, y: cy - 48 * s))
                path.closeSubpath()
                context.fill(path, with: .color(hairColor))
            }
        case "long_silver":
            let baseRect = CGRect(x: cx - 16 * s, y: cy - 52 * s, width: 32 * s, height: 12 * s)
            context.fill(RoundedRectangle(cornerRadius: 5 * s).path(in: baseRect), with: .color(hairColor))
            let flowLeft = CGRect(x: cx - 18 * s, y: cy - 46 * s, width: 7 * s, height: 30 * s)
            let flowRight = CGRect(x: cx + 11 * s, y: cy - 46 * s, width: 7 * s, height: 30 * s)
            context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: flowLeft), with: .color(hairColor))
            context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: flowRight), with: .color(hairColor))
        case "flame_hair":
            for i in 0..<6 {
                let spikeX = cx - 10 * s + CGFloat(i) * 4 * s
                let height: CGFloat = CGFloat([18, 24, 20, 26, 22, 16][i]) * s
                var path = Path()
                path.move(to: CGPoint(x: spikeX, y: cy - 48 * s))
                path.addLine(to: CGPoint(x: spikeX + 2 * s, y: cy - 48 * s - height))
                path.addLine(to: CGPoint(x: spikeX + 4 * s, y: cy - 48 * s))
                path.closeSubpath()
                let color = i % 2 == 0 ? hairItem.colors.first ?? .orange : (hairItem.colors.count > 1 ? hairItem.colors[1] : .red)
                context.fill(path, with: .color(color))
            }
        case "galaxy_hair":
            let baseRect = CGRect(x: cx - 16 * s, y: cy - 54 * s, width: 32 * s, height: 14 * s)
            context.fill(RoundedRectangle(cornerRadius: 6 * s).path(in: baseRect), with: .color(.purple))
            let flowLeft = CGRect(x: cx - 18 * s, y: cy - 46 * s, width: 8 * s, height: 24 * s)
            let flowRight = CGRect(x: cx + 10 * s, y: cy - 46 * s, width: 8 * s, height: 24 * s)
            context.fill(RoundedRectangle(cornerRadius: 4 * s).path(in: flowLeft), with: .color(.blue))
            context.fill(RoundedRectangle(cornerRadius: 4 * s).path(in: flowRight), with: .color(.cyan))
        default:
            let baseRect = CGRect(x: cx - 15 * s, y: cy - 52 * s, width: 30 * s, height: 10 * s)
            context.fill(RoundedRectangle(cornerRadius: 4 * s).path(in: baseRect), with: .color(hairColor))
        }
    }

    private func drawTorso(context: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let topItem = cosmeticItem(for: .top)
        let torsoColor = topItem?.colors.first ?? .blue

        let torsoRect = CGRect(x: cx - 16 * s, y: cy - 20 * s, width: 32 * s, height: 28 * s)
        context.fill(
            RoundedRectangle(cornerRadius: 4 * s).path(in: torsoRect),
            with: .color(torsoColor)
        )

        if let secondary = topItem?.secondaryColors.first {
            let stripeRect = CGRect(x: cx - 14 * s, y: cy - 10 * s, width: 28 * s, height: 4 * s)
            context.fill(
                RoundedRectangle(cornerRadius: 2 * s).path(in: stripeRect),
                with: .color(secondary)
            )
        }

        if topItem?.id == "armor_iron" || topItem?.id == "armor_gold" {
            let shoulderL = CGRect(x: cx - 20 * s, y: cy - 20 * s, width: 10 * s, height: 10 * s)
            let shoulderR = CGRect(x: cx + 10 * s, y: cy - 20 * s, width: 10 * s, height: 10 * s)
            let shoulderColor = topItem?.secondaryColors.first ?? Color(white: 0.4)
            context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: shoulderL), with: .color(shoulderColor))
            context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: shoulderR), with: .color(shoulderColor))
        }
    }

    private func drawArms(context: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat, swing: CGFloat) {
        let armColor = skinColor
        let leftArmRect = CGRect(x: cx - 22 * s, y: cy - 16 * s + swing * s * 0.3, width: 8 * s, height: 22 * s)
        let rightArmRect = CGRect(x: cx + 14 * s, y: cy - 16 * s - swing * s * 0.3, width: 8 * s, height: 22 * s)

        context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: leftArmRect), with: .color(armColor))
        context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: rightArmRect), with: .color(armColor))

        let handL = CGRect(x: cx - 22 * s, y: leftArmRect.maxY - 2 * s, width: 8 * s, height: 8 * s)
        let handR = CGRect(x: cx + 14 * s, y: rightArmRect.maxY - 2 * s, width: 8 * s, height: 8 * s)
        context.fill(Ellipse().path(in: handL), with: .color(skinColor))
        context.fill(Ellipse().path(in: handR), with: .color(skinColor))
    }

    private func drawLegs(context: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat, swing: CGFloat) {
        let bottomItem = cosmeticItem(for: .bottom)
        let legColor = bottomItem?.colors.first ?? Color(white: 0.4)

        let leftLegRect = CGRect(x: cx - 10 * s, y: cy + 8 * s + swing * s * 0.3, width: 9 * s, height: 26 * s)
        let rightLegRect = CGRect(x: cx + 1 * s, y: cy + 8 * s - swing * s * 0.3, width: 9 * s, height: 26 * s)

        context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: leftLegRect), with: .color(legColor))
        context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: rightLegRect), with: .color(legColor))

        if let secondary = bottomItem?.secondaryColors.first {
            let kneeL = CGRect(x: cx - 10 * s, y: cy + 22 * s + swing * s * 0.3, width: 9 * s, height: 5 * s)
            let kneeR = CGRect(x: cx + 1 * s, y: cy + 22 * s - swing * s * 0.3, width: 9 * s, height: 5 * s)
            context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: kneeL), with: .color(secondary))
            context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: kneeR), with: .color(secondary))
        }
    }

    private func drawShoes(context: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat, swing: CGFloat) {
        let shoeItem = cosmeticItem(for: .shoes)
        let shoeColor = shoeItem?.colors.first ?? .white

        let leftShoe = CGRect(x: cx - 12 * s, y: cy + 34 * s + swing * s * 0.3, width: 13 * s, height: 8 * s)
        let rightShoe = CGRect(x: cx - 1 * s, y: cy + 34 * s - swing * s * 0.3, width: 13 * s, height: 8 * s)

        context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: leftShoe), with: .color(shoeColor))
        context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: rightShoe), with: .color(shoeColor))

        if shoeItem?.rarity == .epic || shoeItem?.rarity == .legendary {
            let glowL = CGRect(x: leftShoe.minX + 2 * s, y: leftShoe.maxY - 3 * s, width: leftShoe.width - 4 * s, height: 2 * s)
            let glowR = CGRect(x: rightShoe.minX + 2 * s, y: rightShoe.maxY - 3 * s, width: rightShoe.width - 4 * s, height: 2 * s)
            let glowColor = shoeItem?.colors.last ?? .cyan
            context.fill(RoundedRectangle(cornerRadius: 1 * s).path(in: glowL), with: .color(glowColor.opacity(0.8)))
            context.fill(RoundedRectangle(cornerRadius: 1 * s).path(in: glowR), with: .color(glowColor.opacity(0.8)))
        }
    }

    @ViewBuilder
    private var capeLayer: some View {
        if let capeItem = cosmeticItem(for: .cape) {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let s = min(canvasSize.width, canvasSize.height) / 120
                let sway: CGFloat = isWalking ? (walkCycle ? 4 : -4) : 0

                var capePath = Path()
                capePath.move(to: CGPoint(x: cx - 12 * s, y: cy - 18 * s))
                capePath.addLine(to: CGPoint(x: cx + 12 * s, y: cy - 18 * s))
                capePath.addQuadCurve(
                    to: CGPoint(x: cx + 16 * s + sway * s, y: cy + 30 * s),
                    control: CGPoint(x: cx + 20 * s + sway * s * 0.5, y: cy + 5 * s)
                )
                capePath.addLine(to: CGPoint(x: cx - 16 * s + sway * s, y: cy + 30 * s))
                capePath.addQuadCurve(
                    to: CGPoint(x: cx - 12 * s, y: cy - 18 * s),
                    control: CGPoint(x: cx - 20 * s + sway * s * 0.5, y: cy + 5 * s)
                )
                capePath.closeSubpath()

                let capeColor = capeItem.colors.first ?? .red
                context.fill(capePath, with: .color(capeColor.opacity(0.9)))

                if capeItem.colors.count > 1 {
                    let edgePath = Path { p in
                        p.move(to: CGPoint(x: cx - 14 * s + sway * s, y: cy + 24 * s))
                        p.addLine(to: CGPoint(x: cx + 14 * s + sway * s, y: cy + 24 * s))
                        p.addLine(to: CGPoint(x: cx + 16 * s + sway * s, y: cy + 30 * s))
                        p.addLine(to: CGPoint(x: cx - 16 * s + sway * s, y: cy + 30 * s))
                        p.closeSubpath()
                    }
                    context.fill(edgePath, with: .color(capeItem.colors[1].opacity(0.7)))
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var weaponLayer: some View {
        if let weaponItem = cosmeticItem(for: .weapon) {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let s = min(canvasSize.width, canvasSize.height) / 120

                let weaponColor = weaponItem.colors.first ?? Color(white: 0.6)
                let handleColor = weaponItem.secondaryColors.first ?? Color(red: 0.5, green: 0.35, blue: 0.2)

                switch weaponItem.id {
                case "staff_arcane":
                    let staffRect = CGRect(x: cx + 20 * s, y: cy - 40 * s, width: 4 * s, height: 60 * s)
                    context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: staffRect), with: .color(weaponColor))
                    let orbRect = CGRect(x: cx + 17 * s, y: cy - 48 * s, width: 10 * s, height: 10 * s)
                    context.fill(Circle().path(in: orbRect), with: .color(handleColor))
                default:
                    let bladeRect = CGRect(x: cx + 22 * s, y: cy - 30 * s, width: 5 * s, height: 36 * s)
                    context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: bladeRect), with: .color(weaponColor))
                    let hiltRect = CGRect(x: cx + 18 * s, y: cy + 4 * s, width: 13 * s, height: 4 * s)
                    context.fill(RoundedRectangle(cornerRadius: 1.5 * s).path(in: hiltRect), with: .color(handleColor))
                    let gripRect = CGRect(x: cx + 22 * s, y: cy + 6 * s, width: 5 * s, height: 10 * s)
                    context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: gripRect), with: .color(handleColor))
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var hatLayer: some View {
        if let hatItem = cosmeticItem(for: .hat) {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let s = min(canvasSize.width, canvasSize.height) / 120
                let bodyBob: CGFloat = isWalking ? (walkCycle ? -2 : 2) : 0
                let adjCy = cy + bodyBob

                let hatColor = hatItem.colors.first ?? .red

                switch hatItem.id {
                case "headband_white":
                    let bandRect = CGRect(x: cx - 15 * s, y: adjCy - 48 * s, width: 30 * s, height: 5 * s)
                    context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: bandRect), with: .color(hatColor))
                    var tailPath = Path()
                    tailPath.move(to: CGPoint(x: cx + 14 * s, y: adjCy - 46 * s))
                    tailPath.addLine(to: CGPoint(x: cx + 26 * s, y: adjCy - 52 * s))
                    tailPath.addLine(to: CGPoint(x: cx + 24 * s, y: adjCy - 44 * s))
                    tailPath.closeSubpath()
                    context.fill(tailPath, with: .color(hatColor))
                case "cap_red":
                    let brimRect = CGRect(x: cx - 18 * s, y: adjCy - 48 * s, width: 36 * s, height: 6 * s)
                    context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: brimRect), with: .color(hatColor.opacity(0.8)))
                    let topRect = CGRect(x: cx - 15 * s, y: adjCy - 56 * s, width: 30 * s, height: 12 * s)
                    context.fill(RoundedRectangle(cornerRadius: 5 * s).path(in: topRect), with: .color(hatColor))
                case "warrior_helm":
                    let helmRect = CGRect(x: cx - 17 * s, y: adjCy - 54 * s, width: 34 * s, height: 20 * s)
                    context.fill(RoundedRectangle(cornerRadius: 4 * s).path(in: helmRect), with: .color(hatColor))
                    let visorRect = CGRect(x: cx - 14 * s, y: adjCy - 40 * s, width: 28 * s, height: 6 * s)
                    context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: visorRect), with: .color(Color(white: 0.3)))
                    if let accent = hatItem.secondaryColors.first {
                        var crestPath = Path()
                        crestPath.move(to: CGPoint(x: cx - 4 * s, y: adjCy - 54 * s))
                        crestPath.addLine(to: CGPoint(x: cx, y: adjCy - 66 * s))
                        crestPath.addLine(to: CGPoint(x: cx + 4 * s, y: adjCy - 54 * s))
                        crestPath.closeSubpath()
                        context.fill(crestPath, with: .color(accent))
                    }
                case "wizard_hat":
                    var hatPath = Path()
                    hatPath.move(to: CGPoint(x: cx - 20 * s, y: adjCy - 46 * s))
                    hatPath.addLine(to: CGPoint(x: cx + 20 * s, y: adjCy - 46 * s))
                    hatPath.addLine(to: CGPoint(x: cx + 5 * s, y: adjCy - 80 * s))
                    hatPath.addQuadCurve(
                        to: CGPoint(x: cx - 5 * s, y: adjCy - 70 * s),
                        control: CGPoint(x: cx + 8 * s, y: adjCy - 78 * s)
                    )
                    hatPath.closeSubpath()
                    context.fill(hatPath, with: .color(hatColor))
                    let brimRect = CGRect(x: cx - 22 * s, y: adjCy - 50 * s, width: 44 * s, height: 6 * s)
                    context.fill(RoundedRectangle(cornerRadius: 3 * s).path(in: brimRect), with: .color(hatColor))
                    if let accent = hatItem.secondaryColors.first {
                        let starRect = CGRect(x: cx - 4 * s, y: adjCy - 64 * s, width: 8 * s, height: 8 * s)
                        context.fill(Circle().path(in: starRect), with: .color(accent))
                    }
                case "crown_gold":
                    let baseRect = CGRect(x: cx - 16 * s, y: adjCy - 52 * s, width: 32 * s, height: 8 * s)
                    context.fill(RoundedRectangle(cornerRadius: 2 * s).path(in: baseRect), with: .color(.yellow))
                    for i in 0..<5 {
                        let peakX = cx - 14 * s + CGFloat(i) * 7 * s
                        var peakPath = Path()
                        peakPath.move(to: CGPoint(x: peakX, y: adjCy - 52 * s))
                        peakPath.addLine(to: CGPoint(x: peakX + 3.5 * s, y: adjCy - 62 * s))
                        peakPath.addLine(to: CGPoint(x: peakX + 7 * s, y: adjCy - 52 * s))
                        peakPath.closeSubpath()
                        context.fill(peakPath, with: .color(.yellow))
                    }
                    let gemRect = CGRect(x: cx - 3 * s, y: adjCy - 58 * s, width: 6 * s, height: 6 * s)
                    context.fill(Circle().path(in: gemRect), with: .color(.red))
                case "halo":
                    let haloRect = CGRect(x: cx - 18 * s, y: adjCy - 60 * s, width: 36 * s, height: 10 * s)
                    context.stroke(Ellipse().path(in: haloRect), with: .color(.yellow), lineWidth: 3 * s)
                default: break
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func auraLayer(_ item: SpriteCosmeticItem) -> some View {
        let auraColor = item.colors.first ?? .cyan
        Circle()
            .fill(
                RadialGradient(
                    colors: [auraColor.opacity(0.3), auraColor.opacity(0.1), .clear],
                    center: .center,
                    startRadius: size * 0.15,
                    endRadius: size * 0.55
                )
            )
            .frame(width: size * 1.1, height: size * 1.1)
            .allowsHitTesting(false)
    }
}
