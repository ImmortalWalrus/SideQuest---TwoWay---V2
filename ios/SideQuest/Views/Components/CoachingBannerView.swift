import SwiftUI

struct CoachingBannerView: View {
    let hint: PositioningHint
    @State private var visible: Bool = false

    var body: some View {
        Group {
            if hint != .none {
                HStack(spacing: 8) {
                    Image(systemName: hint.icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(hint == .goodPosition ? .green : .orange)

                    Text(hint.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .fill(hint == .goodPosition ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hint)
    }
}
