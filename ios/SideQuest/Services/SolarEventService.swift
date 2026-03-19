import Foundation
import CoreLocation

@Observable
class SolarEventService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var sunrise: Date?
    private(set) var sunset: Date?
    private(set) var userCoordinate: CLLocationCoordinate2D?
    private(set) var isReady: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocationOnce() {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    private func computeSunEvents(for coordinate: CLLocationCoordinate2D, on date: Date) {
        userCoordinate = coordinate
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)

        let n1 = floor(275.0 * Double(month) / 9.0)
        let n2 = floor(Double(month + 9) / 12.0)
        let n3 = 1.0 + floor((Double(year) - 4.0 * floor(Double(year) / 4.0) + 2.0) / 3.0)
        let dayOfYear = n1 - (n2 * n3) + Double(day) - 30.0

        let lat = coordinate.latitude
        let lng = coordinate.longitude

        sunrise = calculateEvent(dayOfYear: dayOfYear, latitude: lat, longitude: lng, isSunrise: true, date: date)
        sunset = calculateEvent(dayOfYear: dayOfYear, latitude: lat, longitude: lng, isSunrise: false, date: date)
        isReady = true
    }

    private func calculateEvent(dayOfYear: Double, latitude: Double, longitude: Double, isSunrise: Bool, date: Date) -> Date? {
        let zenith = 90.833
        let lngHour = longitude / 15.0
        let t: Double
        if isSunrise {
            t = dayOfYear + (6.0 - lngHour) / 24.0
        } else {
            t = dayOfYear + (18.0 - lngHour) / 24.0
        }

        let sunMeanAnomaly = (0.9856 * t) - 3.289
        var sunLong = sunMeanAnomaly + (1.916 * sin(sunMeanAnomaly * .pi / 180.0)) + (0.020 * sin(2.0 * sunMeanAnomaly * .pi / 180.0)) + 282.634
        sunLong = normalizeAngle(sunLong)

        var ra = atan(0.91764 * tan(sunLong * .pi / 180.0)) * 180.0 / .pi
        ra = normalizeAngle(ra)

        let lQuadrant = floor(sunLong / 90.0) * 90.0
        let raQuadrant = floor(ra / 90.0) * 90.0
        ra += (lQuadrant - raQuadrant)
        ra /= 15.0

        let sinDec = 0.39782 * sin(sunLong * .pi / 180.0)
        let cosDec = cos(asin(sinDec))

        let latRad = latitude * .pi / 180.0
        let cosH = (cos(zenith * .pi / 180.0) - (sinDec * sin(latRad))) / (cosDec * cos(latRad))

        guard cosH >= -1.0 && cosH <= 1.0 else { return nil }

        var h: Double
        if isSunrise {
            h = 360.0 - acos(cosH) * 180.0 / .pi
        } else {
            h = acos(cosH) * 180.0 / .pi
        }
        h /= 15.0

        let localMeanTime = h + ra - (0.06571 * t) - 6.622
        var utHours = localMeanTime - lngHour
        utHours = utHours.truncatingRemainder(dividingBy: 24.0)
        if utHours < 0 { utHours += 24.0 }

        let utHour = Int(utHours)
        let utMinute = Int((utHours - Double(utHour)) * 60.0)

        let cal = Calendar.current
        var comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        comps.hour = utHour
        comps.minute = utMinute
        comps.second = 0

        guard let utcDate = Calendar(identifier: .gregorian).date(from: comps) else { return nil }
        return utcDate
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360.0)
        if a < 0 { a += 360.0 }
        return a
    }

    var sunriseHour: Int? {
        guard let sunrise else { return nil }
        return Calendar.current.component(.hour, from: sunrise)
    }

    var sunriseMinute: Int? {
        guard let sunrise else { return nil }
        return Calendar.current.component(.minute, from: sunrise)
    }

    var sunsetHour: Int? {
        guard let sunset else { return nil }
        return Calendar.current.component(.hour, from: sunset)
    }

    var sunsetMinute: Int? {
        guard let sunset else { return nil }
        return Calendar.current.component(.minute, from: sunset)
    }

    func sunriseWindowStart() -> (hour: Int, minute: Int)? {
        guard let sunrise else { return nil }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .minute, value: -30, to: sunrise) else { return nil }
        return (cal.component(.hour, from: start), cal.component(.minute, from: start))
    }

    func sunriseWindowEnd() -> (hour: Int, minute: Int)? {
        guard let sunrise else { return nil }
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .minute, value: 30, to: sunrise) else { return nil }
        return (cal.component(.hour, from: end), cal.component(.minute, from: end))
    }

    func sunsetWindowStart() -> (hour: Int, minute: Int)? {
        guard let sunset else { return nil }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .minute, value: -60, to: sunset) else { return nil }
        return (cal.component(.hour, from: start), cal.component(.minute, from: start))
    }

    func sunsetWindowEnd() -> (hour: Int, minute: Int)? {
        guard let sunset else { return nil }
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .minute, value: 30, to: sunset) else { return nil }
        return (cal.component(.hour, from: end), cal.component(.minute, from: end))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.computeSunEvents(for: location.coordinate, on: Date())
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
