import Foundation
import CoreLocation

final class QuestAutoCheckInService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var wantsMonitoring = false

    var onLocationUpdate: ((CLLocation) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private(set) var currentLocation: CLLocation?
    private(set) var isMonitoring = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = true
    }

    func startMonitoring() {
        wantsMonitoring = true
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !isMonitoring else {
                if let currentLocation {
                    onLocationUpdate?(currentLocation)
                }
                return
            }
            isMonitoring = true
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            onAuthorizationChange?(status)
        @unknown default:
            onAuthorizationChange?(status)
        }
    }

    func stopMonitoring() {
        wantsMonitoring = false
        guard isMonitoring else { return }
        isMonitoring = false
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.currentLocation = location
            self?.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onAuthorizationChange?(status)
            if self.wantsMonitoring, [.authorizedAlways, .authorizedWhenInUse].contains(status) {
                self.startMonitoring()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
