import SwiftUI

enum ToastStyle {
    case error
    case warning
    case success
    case offline

    var icon: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .offline: return "wifi.slash"
        }
    }

    var tint: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .success: return .green
        case .offline: return .orange
        }
    }
}

struct ToastItem: Identifiable, Equatable {
    let id: String = UUID().uuidString
    let style: ToastStyle
    let title: String
    let message: String
    let duration: Double

    init(style: ToastStyle, title: String, message: String, duration: Double = 3.5) {
        self.style = style
        self.title = title
        self.message = message
        self.duration = duration
    }

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct ToastOverlayView: View {
    let toast: ToastItem
    let onDismiss: () -> Void

    @State private var isVisible: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.style.icon)
                .font(.title3)
                .foregroundStyle(toast.style.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(toast.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(toast.style.tint.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .offset(y: isVisible ? 0 : -80)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                isVisible = true
            }
            Task {
                try? await Task.sleep(for: .seconds(toast.duration))
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            isVisible = false
        }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            onDismiss()
        }
    }
}

struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption.weight(.semibold))
            Text("No Connection")
                .font(.caption.weight(.semibold))
            Text("· Some features unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.12), in: Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
