import SwiftUI

struct SkeletonOverlayView: View {
    let joints: [String: CGPoint]
    let bodyDetected: Bool
    let accentColor: Color
    let videoAspectRatio: CGFloat

    init(
        joints: [String: CGPoint],
        bodyDetected: Bool,
        accentColor: Color,
        videoAspectRatio: CGFloat = 3.0 / 4.0
    ) {
        self.joints = joints
        self.bodyDetected = bodyDetected
        self.accentColor = accentColor
        self.videoAspectRatio = videoAspectRatio
    }

    private let connections: [(String, String)] = [
        ("leftEar", "leftEye"),
        ("leftEye", "nose"),
        ("rightEar", "rightEye"),
        ("rightEye", "nose"),
        ("nose", "neck"),
        ("neck", "leftShoulder"),
        ("neck", "rightShoulder"),
        ("leftShoulder", "rightShoulder"),
        ("leftShoulder", "leftElbow"),
        ("leftElbow", "leftWrist"),
        ("rightShoulder", "rightElbow"),
        ("rightElbow", "rightWrist"),
        ("neck", "root"),
        ("leftShoulder", "leftHip"),
        ("rightShoulder", "rightHip"),
        ("root", "leftHip"),
        ("root", "rightHip"),
        ("leftHip", "rightHip"),
        ("leftHip", "leftKnee"),
        ("leftKnee", "leftAnkle"),
        ("rightHip", "rightKnee"),
        ("rightKnee", "rightAnkle"),
    ]

    var body: some View {
        Canvas { context, size in
            guard bodyDetected else { return }

            for (a, b) in connections {
                guard let pA = joints[a], let pB = joints[b] else { continue }
                let viewA = visionToView(pA, in: size)
                let viewB = visionToView(pB, in: size)
                var path = Path()
                path.move(to: viewA)
                path.addLine(to: viewB)
                context.stroke(path, with: .color(accentColor.opacity(0.5)), lineWidth: 3)
            }

            for (_, point) in joints {
                let vp = visionToView(point, in: size)
                let rect = CGRect(x: vp.x - 5, y: vp.y - 5, width: 10, height: 10)
                context.fill(Circle().path(in: rect), with: .color(accentColor))
            }
        }
        .allowsHitTesting(false)
    }

    private func visionToView(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }

        let safeAspect = max(videoAspectRatio, 0.0001)
        let viewAspect = size.width / size.height

        if safeAspect > viewAspect {
            let scaledWidth = size.height * safeAspect
            let horizontalCrop = (scaledWidth - size.width) / 2
            return CGPoint(
                x: point.x * scaledWidth - horizontalCrop,
                y: (1 - point.y) * size.height
            )
        } else {
            let scaledHeight = size.width / safeAspect
            let verticalCrop = (scaledHeight - size.height) / 2
            return CGPoint(
                x: point.x * size.width,
                y: (1 - point.y) * scaledHeight - verticalCrop
            )
        }
    }
}
