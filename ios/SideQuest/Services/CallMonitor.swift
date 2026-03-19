import CallKit
import Combine

@Observable
final class CallMonitor: NSObject {
    private(set) var isOnCall: Bool = false
    private let observer = CXCallObserver()

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }
}

extension CallMonitor: CXCallObserverDelegate {
    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let active = callObserver.calls.contains { !$0.hasEnded }
        Task { @MainActor in
            self.isOnCall = active
        }
    }
}
