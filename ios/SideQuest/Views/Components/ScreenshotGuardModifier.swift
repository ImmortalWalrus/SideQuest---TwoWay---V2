import SwiftUI
import UIKit

struct ScreenshotGuardModifier: ViewModifier {
    let onCapture: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                NotificationCenter.default.addObserver(
                    forName: UIApplication.userDidTakeScreenshotNotification,
                    object: nil,
                    queue: .main
                ) { _ in onCapture() }

                NotificationCenter.default.addObserver(
                    forName: UIScreen.capturedDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    if UIScreen.main.isCaptured {
                        onCapture()
                    }
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(
                    self,
                    name: UIApplication.userDidTakeScreenshotNotification,
                    object: nil
                )
                NotificationCenter.default.removeObserver(
                    self,
                    name: UIScreen.capturedDidChangeNotification,
                    object: nil
                )
            }
    }
}

extension View {
    func screenshotGuard(onCapture: @escaping () -> Void) -> some View {
        modifier(ScreenshotGuardModifier(onCapture: onCapture))
    }
}
