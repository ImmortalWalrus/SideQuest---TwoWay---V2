import SwiftUI
import MapKit
import UIKit

struct ExploreMapView: UIViewRepresentable {
    let centerCoordinate: CLLocationCoordinate2D
    let userCoordinate: CLLocationCoordinate2D?
    let encounters: [ExploreEncounter]
    let districts: [ExploreDistrict]
    let zones: [ExploreZone]
    let routes: [ExploreRoute]
    let selectedEncounterID: String?
    let command: ExploreMapCommand?
    let onSelectEncounter: @MainActor (ExploreEncounter) -> Void
    let onRegionChanged: @MainActor (CLLocationCoordinate2D, Double) -> Void

    func makeCoordinator() -> ExploreMapCoordinator {
        ExploreMapCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = userCoordinate != nil
        mapView.preferredConfiguration = Self.makeMapConfiguration()
        mapView.register(
            ExploreEncounterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: ExploreEncounterAnnotationView.reuseIdentifier
        )
        mapView.register(
            ExploreClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
        mapView.register(
            ExploreDistrictLabelAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: ExploreDistrictLabelAnnotationView.reuseIdentifier
        )
        context.coordinator.configureInitialCamera(on: mapView, center: centerCoordinate)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        mapView.preferredConfiguration = Self.makeMapConfiguration()
        mapView.showsUserLocation = userCoordinate != nil
        context.coordinator.syncMapContent(on: mapView)
        context.coordinator.applySelection(on: mapView)
        context.coordinator.handleCommandIfNeeded(on: mapView)
    }

    private static func makeMapConfiguration() -> MKMapConfiguration {
        let configuration = MKStandardMapConfiguration()
        configuration.pointOfInterestFilter = .excludingAll
        return configuration
    }
}

final class ExploreMapCoordinator: NSObject, MKMapViewDelegate {
    private let enablesCafe3DAnnotations = false
    var parent: ExploreMapView

    private var lastCommandID: UUID?
    private var hasConfiguredInitialCamera: Bool = false
    private var lastEncounterSignature: String?
    private var lastDistrictSignature: String?
    private var lastZoneSignature: String?
    private var lastRouteSignature: String?
    private var zoneStyles: [ObjectIdentifier: ExploreZone] = [:]
    private var districtStyles: [ObjectIdentifier: ExploreDistrict] = [:]
    private var routeStyles: [ObjectIdentifier: ExploreRoute] = [:]
    private var currentZoomScale: CGFloat = 1.0
    private var roadBearingCache: [String: Double] = [:]
    private var hasApplied3DCafe: Bool = false
    weak var mapViewRef: MKMapView?

    init(parent: ExploreMapView) {
        self.parent = parent
    }

    func configureInitialCamera(on mapView: MKMapView, center: CLLocationCoordinate2D) {
        guard !hasConfiguredInitialCamera else { return }
        hasConfiguredInitialCamera = true
        self.mapViewRef = mapView
        let camera = MKMapCamera(
            lookingAtCenter: center,
            fromDistance: 1800,
            pitch: 55,
            heading: 0
        )
        mapView.setCamera(camera, animated: false)
        if enablesCafe3DAnnotations {
            CafeBuildingRenderer.shared.prerenderIfNeeded()
        }
    }

    func syncMapContent(on mapView: MKMapView) {
        let encounterSignature = parent.encounters.map { encounter in
            "\(encounter.id)_\(encounter.kind.rawValue)_\(encounter.coordinate.latitude)_\(encounter.coordinate.longitude)_\(encounter.countdownText ?? "")_\(encounter.mapPinAssetName ?? "")"
        }.joined(separator: "|")
        let districtSignature = parent.districts.map { district in
            let firstCoordinate = district.coordinates.first
            return "\(district.id)_\(firstCoordinate?.latitude ?? 0)_\(firstCoordinate?.longitude ?? 0)"
        }.joined(separator: "|")
        let zoneSignature = parent.zones.map { zone in
            "\(zone.id)_\(zone.centerCoordinate.latitude)_\(zone.centerCoordinate.longitude)_\(zone.radius)"
        }.joined(separator: "|")
        let routeSignature = parent.routes.map { route in
            let firstCoordinate = route.coordinates.first
            return "\(route.id)_\(firstCoordinate?.latitude ?? 0)_\(firstCoordinate?.longitude ?? 0)_\(route.coordinates.count)"
        }.joined(separator: "|")

        guard encounterSignature != lastEncounterSignature
            || districtSignature != lastDistrictSignature
            || zoneSignature != lastZoneSignature
            || routeSignature != lastRouteSignature
        else {
            return
        }

        lastEncounterSignature = encounterSignature
        lastDistrictSignature = districtSignature
        lastZoneSignature = zoneSignature
        lastRouteSignature = routeSignature

        let existingCustomAnnotations = mapView.annotations.filter {
            !($0 is MKUserLocation)
        }
        mapView.removeAnnotations(existingCustomAnnotations)

        zoneStyles.removeAll(keepingCapacity: true)
        districtStyles.removeAll(keepingCapacity: true)
        routeStyles.removeAll(keepingCapacity: true)
        mapView.removeOverlays(mapView.overlays)

        let encounterAnnotations: [ExploreEncounterAnnotation] = parent.encounters.map { encounter in
            ExploreEncounterAnnotation(encounter: encounter)
        }
        let districtAnnotations: [ExploreDistrictLabelAnnotation] = parent.districts.map { district in
            ExploreDistrictLabelAnnotation(district: district)
        }
        mapView.addAnnotations(encounterAnnotations)
        mapView.addAnnotations(districtAnnotations)

        hasApplied3DCafe = false
        if enablesCafe3DAnnotations {
            fetchCafeRoadBearings(for: parent.encounters, on: mapView)
        }

        if enablesCafe3DAnnotations && CafeBuildingRenderer.shared.isReady {
            hasApplied3DCafe = true
        }

        for district in parent.districts {
            var coordinates = district.coordinates
            let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
            districtStyles[ObjectIdentifier(polygon)] = district
            mapView.addOverlay(polygon, level: .aboveRoads)
        }

        for route in parent.routes {
            var coordinates = route.coordinates
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            routeStyles[ObjectIdentifier(polyline)] = route
            mapView.addOverlay(polyline, level: .aboveRoads)
        }

        for zone in parent.zones {
            let circle = MKCircle(center: zone.centerCoordinate, radius: zone.radius)
            zoneStyles[ObjectIdentifier(circle)] = zone
            mapView.addOverlay(circle, level: .aboveRoads)
        }
    }

    func applySelection(on mapView: MKMapView) {
        guard let selectedEncounterID = parent.selectedEncounterID else {
            for annotation in mapView.selectedAnnotations {
                mapView.deselectAnnotation(annotation, animated: true)
            }
            return
        }

        let matchingAnnotation = mapView.annotations.first { annotation in
            guard let encounterAnnotation = annotation as? ExploreEncounterAnnotation else {
                return false
            }
            return encounterAnnotation.encounter.id == selectedEncounterID
        }

        if let matchingAnnotation {
            if !(mapView.selectedAnnotations.contains { ($0 as? ExploreEncounterAnnotation)?.encounter.id == selectedEncounterID }) {
                mapView.selectAnnotation(matchingAnnotation, animated: true)
            }
        } else {
            for annotation in mapView.selectedAnnotations {
                mapView.deselectAnnotation(annotation, animated: true)
            }
        }
    }

    func handleCommandIfNeeded(on mapView: MKMapView) {
        guard let command = parent.command else { return }
        guard command.id != lastCommandID else { return }
        lastCommandID = command.id

        let camera = mapView.camera
        switch command.action {
        case .recenter:
            let target = parent.userCoordinate ?? parent.centerCoordinate
            let updatedCamera = MKMapCamera(
                lookingAtCenter: target,
                fromDistance: max(camera.centerCoordinateDistance * 0.92, 1200),
                pitch: 55,
                heading: 0
            )
            mapView.setCamera(updatedCamera, animated: true)
        case .zoomIn:
            let updatedCamera = MKMapCamera(
                lookingAtCenter: camera.centerCoordinate,
                fromDistance: max(camera.centerCoordinateDistance * 0.72, 600),
                pitch: 55,
                heading: 0
            )
            mapView.setCamera(updatedCamera, animated: true)
        case .zoomOut:
            let updatedCamera = MKMapCamera(
                lookingAtCenter: camera.centerCoordinate,
                fromDistance: min(camera.centerCoordinateDistance * 1.28, 9000),
                pitch: 55,
                heading: 0
            )
            mapView.setCamera(updatedCamera, animated: true)
        case .focusObjectives:
            let focusAnnotations = mapView.annotations.compactMap { annotation -> ExploreEncounterAnnotation? in
                guard let encounterAnnotation = annotation as? ExploreEncounterAnnotation else {
                    return nil
                }
                return encounterAnnotation.encounter.kind.isHighPriority ? encounterAnnotation : nil
            }
            guard !focusAnnotations.isEmpty else { return }
            let mapRect = focusAnnotations.reduce(MKMapRect.null) { partialResult, annotation in
                let point = MKMapPoint(annotation.coordinate)
                let rect = MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0))
                return partialResult.union(rect)
            }
            mapView.setVisibleMapRect(
                mapRect,
                edgePadding: UIEdgeInsets(top: 140, left: 70, bottom: 280, right: 70),
                animated: true
            )
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        MainActor.assumeIsolated {
            if annotation is MKUserLocation {
                return nil
            }

            if let encounterAnnotation = annotation as? ExploreEncounterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: ExploreEncounterAnnotationView.reuseIdentifier,
                    for: encounterAnnotation
                )
                guard let encounterView = view as? ExploreEncounterAnnotationView else {
                    return view
                }
                encounterView.configure(with: encounterAnnotation.encounter)
                let encounter = encounterAnnotation.encounter
                if enablesCafe3DAnnotations && encounter.poi.category == .cafe && CafeBuildingRenderer.shared.isReady {
                    let bearing = roadBearingForPOI(encounter.poi)
                    encounterView.applyCafe3DImage(bearing: bearing, zoomScale: currentZoomScale)
                }
                return encounterView
            }

            if let districtAnnotation = annotation as? ExploreDistrictLabelAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: ExploreDistrictLabelAnnotationView.reuseIdentifier,
                    for: districtAnnotation
                )
                guard let districtView = view as? ExploreDistrictLabelAnnotationView else {
                    return view
                }
                districtView.configure(with: districtAnnotation.district)
                return districtView
            }

            if let clusterAnnotation = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: clusterAnnotation
                )
                guard let clusterView = view as? ExploreClusterAnnotationView else {
                    return view
                }
                clusterView.configure(with: clusterAnnotation)
                return clusterView
            }

            return nil
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        MainActor.assumeIsolated {
            if let zone = zoneStyles[ObjectIdentifier(overlay as AnyObject)], let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let color = zone.category.uiColor
                renderer.fillColor = color.withAlphaComponent(zone.kind == .limitedEvent ? 0.12 : 0.06)
                renderer.strokeColor = color.withAlphaComponent(zone.kind == .limitedEvent ? 0.55 : 0.34)
                renderer.lineWidth = zone.kind.isHighPriority ? 2.0 : 1.0
                renderer.lineDashPattern = zone.kind == .limitedEvent ? [8, 6] : nil
                return renderer
            }

            if let district = districtStyles[ObjectIdentifier(overlay as AnyObject)], let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                let color = district.path.uiColor
                renderer.fillColor = color.withAlphaComponent(0.04)
                renderer.strokeColor = color.withAlphaComponent(0.16)
                renderer.lineWidth = 0.9
                renderer.lineDashPattern = [6, 6]
                return renderer
            }

            if let route = routeStyles[ObjectIdentifier(overlay as AnyObject)], let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = route.path.uiColor.withAlphaComponent(0.72)
                renderer.lineWidth = 3.5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                renderer.lineDashPattern = [2, 10]
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        MainActor.assumeIsolated {
            let center = mapView.centerCoordinate
            let region = mapView.region
            let radiusMeters = region.span.latitudeDelta * 111_320 / 2
            parent.onRegionChanged(center, radiusMeters)

            if enablesCafe3DAnnotations && CafeBuildingRenderer.shared.isReady && !hasApplied3DCafe {
                hasApplied3DCafe = true
                applyCafe3DImages(on: mapView)
            }

            let distance = mapView.camera.centerCoordinateDistance
            let referenceDistance: Double = 3000
            let newScale = CGFloat(pow(distance / referenceDistance, 0.18))
            let clampedScale = min(max(newScale, 0.85), 1.35)
            if enablesCafe3DAnnotations && abs(clampedScale - currentZoomScale) > 0.03 {
                currentZoomScale = clampedScale
                updateCafeAnnotationScales(on: mapView)
            }
        }
    }

    private func roadBearingForPOI(_ poi: MapPOI) -> Double {
        if let cached = roadBearingCache[poi.id] { return cached }
        let bearing = CafeBuildingRenderer.estimateRoadBearing(at: poi.coordinate)
        roadBearingCache[poi.id] = bearing
        return bearing
    }

    private func fetchCafeRoadBearings(for encounters: [ExploreEncounter], on mapView: MKMapView) {
        let cafes = encounters.filter { $0.poi.category == .cafe }
        for encounter in cafes {
            let poi = encounter.poi
            let alreadyCached = roadBearingCache[poi.id] != nil
            if !alreadyCached {
                roadBearingCache[poi.id] = CafeBuildingRenderer.estimateRoadBearing(at: poi.coordinate)
            }
            Task {
                let bearing = await CafeBuildingRenderer.fetchRoadBearing(for: poi.coordinate)
                let old = roadBearingCache[poi.id]
                roadBearingCache[poi.id] = bearing
                guard old != bearing || !alreadyCached else { return }
                guard let annotation = mapView.annotations.compactMap({ $0 as? ExploreEncounterAnnotation }).first(where: { $0.encounter.poi.id == poi.id }),
                      let view = mapView.view(for: annotation) as? ExploreEncounterAnnotationView else { return }
                view.applyCafe3DImage(bearing: bearing, zoomScale: currentZoomScale)
            }
        }
    }

    private func applyCafe3DImages(on mapView: MKMapView) {
        for annotation in mapView.annotations {
            guard let encounterAnnotation = annotation as? ExploreEncounterAnnotation,
                  encounterAnnotation.encounter.poi.category == .cafe,
                  let view = mapView.view(for: annotation) as? ExploreEncounterAnnotationView else { continue }
            let bearing = roadBearingForPOI(encounterAnnotation.encounter.poi)
            view.applyCafe3DImage(bearing: bearing, zoomScale: currentZoomScale)
        }
    }

    private func updateCafeAnnotationScales(on mapView: MKMapView) {
        for annotation in mapView.annotations {
            guard let encounterAnnotation = annotation as? ExploreEncounterAnnotation,
                  encounterAnnotation.encounter.poi.category == .cafe,
                  let view = mapView.view(for: annotation) as? ExploreEncounterAnnotationView else { continue }
            view.updateCafeZoomScale(currentZoomScale)
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        MainActor.assumeIsolated {
            if let clusterAnnotation = view.annotation as? MKClusterAnnotation {
                let rect = clusterAnnotation.memberAnnotations.reduce(MKMapRect.null) { partialResult, member in
                    let point = MKMapPoint(member.coordinate)
                    let rect = MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0))
                    return partialResult.union(rect)
                }
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 140, left: 70, bottom: 250, right: 70),
                    animated: true
                )
                mapView.deselectAnnotation(clusterAnnotation, animated: false)
                return
            }

            guard let encounterAnnotation = view.annotation as? ExploreEncounterAnnotation else {
                return
            }
            let encounter = encounterAnnotation.encounter
            parent.onSelectEncounter(encounter)

            let camera = MKMapCamera(
                lookingAtCenter: encounter.coordinate,
                fromDistance: max(encounter.zoneRadius * 5.2, 900),
                pitch: 55,
                heading: 0
            )
            mapView.setCamera(camera, animated: true)
        }
    }
}

nonisolated final class ExploreEncounterAnnotation: NSObject, MKAnnotation {
    let encounter: ExploreEncounter
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { encounter.title }
    var subtitle: String? { encounter.subtitle }

    init(encounter: ExploreEncounter) {
        self.encounter = encounter
        self.coordinate = encounter.coordinate
    }
}

nonisolated final class ExploreDistrictLabelAnnotation: NSObject, MKAnnotation {
    let district: ExploreDistrict
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { district.name }

    init(district: ExploreDistrict) {
        self.district = district
        self.coordinate = district.labelCoordinate
    }
}

final class ExploreEncounterAnnotationView: MKAnnotationView {
    static let reuseIdentifier: String = "ExploreEncounterAnnotationView"

    private let buildingImageView = UIImageView()
    private let iconBadge = UIView()
    private let iconImageView = UIImageView()
    private let iconLabel = UILabel()
    private let badgeStack = UIStackView()
    private let glowRing = UIView()
    private let auraRing = UIView()
    private var iconBadgeWidthConstraint: NSLayoutConstraint?
    private var isCafeWith3D: Bool = false
    private var cafeZoomScale: CGFloat = 1.0

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -40)
        collisionMode = .circle
        displayPriority = .defaultHigh
        frame = CGRect(x: 0, y: 0, width: 64, height: 88)
        backgroundColor = .clear
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        layer.removeAllAnimations()
        glowRing.layer.removeAllAnimations()
        auraRing.layer.removeAllAnimations()
        iconBadge.layer.removeAllAnimations()
        buildingImageView.layer.removeAllAnimations()
        isCafeWith3D = false
        cafeZoomScale = 1.0
        iconLabel.text = nil
        iconLabel.isHidden = true
        iconBadgeWidthConstraint?.constant = 24
        iconBadge.layer.cornerRadius = 12
        transform = .identity
        centerOffset = CGPoint(x: 0, y: -40)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let selectionScale: CGFloat = selected ? 1.18 : 1.0
        let composedScale = selectionScale * (isCafeWith3D ? cafeZoomScale : 1.0)
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.6) {
                self.transform = CGAffineTransform(scaleX: composedScale, y: composedScale)
            }
        } else {
            transform = CGAffineTransform(scaleX: composedScale, y: composedScale)
        }
    }

    func applyCafe3DImage(bearing: Double, zoomScale: CGFloat) {
        guard let image = CafeBuildingRenderer.shared.image(forBearing: bearing) else { return }
        buildingImageView.image = image
        isCafeWith3D = true
        cafeZoomScale = zoomScale
        let composedScale = (isSelected ? 1.18 : 1.0) * zoomScale
        transform = CGAffineTransform(scaleX: composedScale, y: composedScale)
        centerOffset = CGPoint(x: 0, y: -40 * zoomScale)
    }

    func updateCafeZoomScale(_ scale: CGFloat) {
        guard isCafeWith3D else { return }
        cafeZoomScale = scale
        let composedScale = (isSelected ? 1.18 : 1.0) * scale
        UIView.animate(withDuration: 0.15) {
            self.transform = CGAffineTransform(scaleX: composedScale, y: composedScale)
            self.centerOffset = CGPoint(x: 0, y: -40 * scale)
        }
    }

    func configure(with encounter: ExploreEncounter) {
        let category = encounter.poi.category
        let color = category.uiColor
        let isHigh = encounter.kind.isHighPriority
        let isVisited = encounter.kind == .visitedShrine

        let buildingSize = CGSize(width: 72, height: 84)
        if let assetName = encounter.mapPinAssetName,
           let customImage = IsometricBuildingRenderer.render(
                assetName: assetName,
                color: color,
                size: buildingSize,
                isVisited: isVisited
           ) {
            buildingImageView.image = customImage
        } else {
            let buildingStyle = IsometricBuildingStyle(category: category)
            buildingImageView.image = IsometricBuildingRenderer.render(
                style: buildingStyle,
                color: color,
                size: buildingSize,
                isVisited: isVisited
            )
        }

        let icon = isVisited ? "checkmark.seal.fill" : category.icon
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = .white

        iconBadge.backgroundColor = isVisited ? UIColor(white: 0.4, alpha: 0.9) : color.withAlphaComponent(0.92)
        iconBadge.layer.borderColor = UIColor.white.withAlphaComponent(isHigh ? 0.95 : 0.6).cgColor
        if let countdownText = encounter.countdownText, !countdownText.isEmpty {
            iconImageView.image = UIImage(systemName: "clock.fill")
            iconLabel.text = countdownText
            iconLabel.isHidden = false
            iconBadgeWidthConstraint?.constant = max(44, min(74, countdownText.size(withAttributes: [.font: iconLabel.font as Any]).width + 26))
            iconBadge.layer.cornerRadius = 11
        } else {
            iconLabel.text = nil
            iconLabel.isHidden = true
            iconBadgeWidthConstraint?.constant = 24
            iconBadge.layer.cornerRadius = 12
        }

        glowRing.isHidden = !isHigh
        glowRing.backgroundColor = color.withAlphaComponent(0.16)
        glowRing.layer.borderColor = color.withAlphaComponent(0.55).cgColor

        auraRing.isHidden = isVisited
        auraRing.backgroundColor = color.withAlphaComponent(isHigh ? 0.2 : 0.1)
        auraRing.layer.borderColor = color.withAlphaComponent(isHigh ? 0.42 : 0.24).cgColor

        layer.shadowColor = color.cgColor
        layer.shadowRadius = isHigh ? 18 : 10
        layer.shadowOpacity = isHigh ? 0.42 : 0.22
        layer.shadowOffset = CGSize(width: 0, height: 8)

        if isVisited {
            buildingImageView.alpha = 0.68
            let visitedScale: CGFloat = 0.9
            buildingImageView.transform = CGAffineTransform(scaleX: visitedScale, y: visitedScale)
        } else {
            buildingImageView.alpha = 1.0
            buildingImageView.transform = .identity
        }

        let isCafe = encounter.poi.category == .cafe
        displayPriority = isHigh ? .required : (isCafe ? .defaultHigh : .defaultLow)
        clusteringIdentifier = (encounter.kind.isClusterable && !isCafe) ? "rpg-node" : nil

        animateStructure(highPriority: isHigh)
    }

    private func setupViews() {
        [auraRing, glowRing, buildingImageView, iconBadge, iconImageView, iconLabel, badgeStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        addSubview(auraRing)
        addSubview(glowRing)
        addSubview(buildingImageView)
        addSubview(iconBadge)
        iconBadge.addSubview(badgeStack)

        buildingImageView.contentMode = .scaleAspectFit

        auraRing.layer.cornerRadius = 24
        auraRing.layer.borderWidth = 1.5
        auraRing.alpha = 0.9

        iconBadge.layer.cornerRadius = 12
        iconBadge.layer.borderWidth = 1.5
        iconBadge.layer.shadowColor = UIColor.black.cgColor
        iconBadge.layer.shadowOpacity = 0.3
        iconBadge.layer.shadowRadius = 4
        iconBadge.layer.shadowOffset = CGSize(width: 0, height: 2)

        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        iconImageView.contentMode = .scaleAspectFit
        iconLabel.font = .systemFont(ofSize: 9, weight: .heavy)
        iconLabel.textColor = .white
        iconLabel.textAlignment = .center
        iconLabel.isHidden = true

        badgeStack.axis = .horizontal
        badgeStack.alignment = .center
        badgeStack.distribution = .fill
        badgeStack.spacing = 4
        badgeStack.addArrangedSubview(iconImageView)
        badgeStack.addArrangedSubview(iconLabel)

        glowRing.layer.cornerRadius = 18
        glowRing.layer.borderWidth = 1.5
        glowRing.isHidden = true

        iconBadgeWidthConstraint = iconBadge.widthAnchor.constraint(equalToConstant: 24)

        NSLayoutConstraint.activate([
            buildingImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            buildingImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            auraRing.centerXAnchor.constraint(equalTo: centerXAnchor),
            auraRing.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            auraRing.widthAnchor.constraint(equalToConstant: 48),
            auraRing.heightAnchor.constraint(equalToConstant: 48),

            buildingImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            buildingImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            buildingImageView.widthAnchor.constraint(equalToConstant: 72),
            buildingImageView.heightAnchor.constraint(equalToConstant: 84),

            iconBadge.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconBadge.bottomAnchor.constraint(equalTo: buildingImageView.topAnchor, constant: 14),
            iconBadge.heightAnchor.constraint(equalToConstant: 24),
            iconBadgeWidthConstraint!,

            badgeStack.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            badgeStack.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            badgeStack.leadingAnchor.constraint(greaterThanOrEqualTo: iconBadge.leadingAnchor, constant: 6),
            badgeStack.trailingAnchor.constraint(lessThanOrEqualTo: iconBadge.trailingAnchor, constant: -6),

            iconImageView.widthAnchor.constraint(equalToConstant: 10),
            iconImageView.heightAnchor.constraint(equalToConstant: 10),

            glowRing.centerXAnchor.constraint(equalTo: centerXAnchor),
            glowRing.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            glowRing.widthAnchor.constraint(equalToConstant: 36),
            glowRing.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func animateStructure(highPriority: Bool) {
        buildingImageView.layer.removeAllAnimations()
        glowRing.layer.removeAllAnimations()
        auraRing.layer.removeAllAnimations()
        iconBadge.layer.removeAllAnimations()

        let hover = CABasicAnimation(keyPath: "transform.translation.y")
        hover.fromValue = 0
        hover.toValue = -2
        hover.duration = 2.0
        hover.repeatCount = .infinity
        hover.autoreverses = true
        hover.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        buildingImageView.layer.add(hover, forKey: "hover")

        let auraPulse = CABasicAnimation(keyPath: "transform.scale")
        auraPulse.fromValue = highPriority ? 0.92 : 0.96
        auraPulse.toValue = highPriority ? 1.08 : 1.03
        auraPulse.duration = highPriority ? 1.8 : 2.4
        auraPulse.repeatCount = .infinity
        auraPulse.autoreverses = true
        auraPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        auraRing.layer.add(auraPulse, forKey: "auraPulse")

        let auraFade = CABasicAnimation(keyPath: "opacity")
        auraFade.fromValue = highPriority ? 0.45 : 0.22
        auraFade.toValue = highPriority ? 0.9 : 0.42
        auraFade.duration = highPriority ? 1.5 : 2.2
        auraFade.repeatCount = .infinity
        auraFade.autoreverses = true
        auraFade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        auraRing.layer.add(auraFade, forKey: "auraFade")

        guard highPriority else { return }

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.85
        pulse.toValue = 1.1
        pulse.duration = 1.4
        pulse.repeatCount = .infinity
        pulse.autoreverses = true
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowRing.layer.add(pulse, forKey: "pulse")

        let badgePulse = CABasicAnimation(keyPath: "transform.scale")
        badgePulse.fromValue = 1.0
        badgePulse.toValue = 1.12
        badgePulse.duration = 1.6
        badgePulse.repeatCount = .infinity
        badgePulse.autoreverses = true
        badgePulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconBadge.layer.add(badgePulse, forKey: "badgePulse")
    }
}

final class ExploreClusterAnnotationView: MKAnnotationView {
    private let coreView = UIView()
    private let glowView = UIView()
    private let countLabel = UILabel()
    private let iconView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -18)
        collisionMode = .circle
        displayPriority = .required
        frame = CGRect(x: 0, y: 0, width: 92, height: 92)
        backgroundColor = .clear
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with cluster: MKClusterAnnotation) {
        let annotations = cluster.memberAnnotations.compactMap { $0 as? ExploreEncounterAnnotation }
        let prominent = annotations.sorted { lhs, rhs in
            lhs.encounter.kind.isHighPriority && !rhs.encounter.kind.isHighPriority
        }.first
        let color = prominent?.encounter.poi.category.uiColor ?? .systemBlue
        glowView.backgroundColor = color.withAlphaComponent(0.24)
        glowView.layer.borderColor = color.withAlphaComponent(0.75).cgColor
        coreView.backgroundColor = UIColor(white: 0.08, alpha: 0.92)
        coreView.layer.borderColor = color.withAlphaComponent(0.95).cgColor
        countLabel.text = "\(cluster.memberAnnotations.count)"
        iconView.image = UIImage(systemName: prominent?.encounter.kind.systemImageName ?? "sparkles")
        iconView.tintColor = color
    }

    private func setupViews() {
        [glowView, coreView, countLabel, iconView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        addSubview(glowView)
        addSubview(coreView)
        addSubview(countLabel)
        addSubview(iconView)

        glowView.layer.cornerRadius = 28
        glowView.layer.borderWidth = 2
        coreView.layer.cornerRadius = 24
        coreView.layer.borderWidth = 2
        coreView.layer.shadowColor = UIColor.black.cgColor
        coreView.layer.shadowOpacity = 0.28
        coreView.layer.shadowRadius = 14
        coreView.layer.shadowOffset = CGSize(width: 0, height: 8)
        countLabel.font = UIFont.systemFont(ofSize: 18, weight: .heavy)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        iconView.contentMode = .scaleAspectFit

        NSLayoutConstraint.activate([
            glowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glowView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            glowView.widthAnchor.constraint(equalToConstant: 56),
            glowView.heightAnchor.constraint(equalToConstant: 56),

            coreView.centerXAnchor.constraint(equalTo: centerXAnchor),
            coreView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            coreView.widthAnchor.constraint(equalToConstant: 48),
            coreView.heightAnchor.constraint(equalToConstant: 48),

            countLabel.centerXAnchor.constraint(equalTo: coreView.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: coreView.centerYAnchor, constant: 3),

            iconView.centerXAnchor.constraint(equalTo: coreView.centerXAnchor),
            iconView.bottomAnchor.constraint(equalTo: coreView.topAnchor, constant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }
}

final class ExploreDistrictLabelAnnotationView: MKAnnotationView {
    static let reuseIdentifier: String = "ExploreDistrictLabelAnnotationView"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stackView = UIStackView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        collisionMode = .rectangle
        displayPriority = .defaultLow
        backgroundColor = .clear
        centerOffset = CGPoint(x: 0, y: -18)
        frame = CGRect(x: 0, y: 0, width: 132, height: 54)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with district: ExploreDistrict) {
        titleLabel.text = district.name.uppercased()
        subtitleLabel.text = district.subtitle
        let tint = district.path.uiColor
        stackView.backgroundColor = tint.withAlphaComponent(0.14)
        stackView.layer.borderColor = tint.withAlphaComponent(0.4).cgColor
    }

    private func setupViews() {
        titleLabel.font = UIFont.systemFont(ofSize: 10, weight: .heavy)
        titleLabel.textColor = UIColor(white: 0.96, alpha: 0.96)
        subtitleLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        subtitleLabel.textColor = UIColor(white: 0.82, alpha: 0.95)

        stackView.axis = .vertical
        stackView.spacing = 1
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layer.cornerRadius = 12
        stackView.layer.borderWidth = 1
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

extension MapQuestCategory {
    var uiColor: UIColor {
        switch self {
        case .cafe: UIColor(red: 0.60, green: 0.42, blue: 0.23, alpha: 1)
        case .gym: .systemOrange
        case .park: .systemGreen
        case .library: .systemIndigo
        case .trail: .systemMint
        case .pool: .systemCyan
        case .bookstore: .systemPurple
        case .museum: .systemTeal
        case .beach: UIColor(red: 0.93, green: 0.76, blue: 0.25, alpha: 1)
        case .basketballCourt: .systemOrange
        case .yogaStudio: .systemPink
        case .restaurant: .systemRed
        case .farmersMarket: UIColor(red: 0.28, green: 0.70, blue: 0.33, alpha: 1)
        case .dogPark: UIColor(red: 0.63, green: 0.45, blue: 0.24, alpha: 1)
        case .skatePark: .systemGray
        case .rockClimbingGym: UIColor(red: 0.84, green: 0.52, blue: 0.22, alpha: 1)
        case .bowlingAlley: .systemBlue
        case .artGallery: .systemPurple
        case .communityCenter: .systemTeal
        case .placeOfWorship: .systemIndigo
        case .volunteerCenter: .systemPink
        case .danceStudio: UIColor(red: 0.72, green: 0.33, blue: 0.70, alpha: 1)
        case .martialArts: .systemRed
        case .tennisCourt: UIColor(red: 0.40, green: 0.72, blue: 0.26, alpha: 1)
        case .lake: .systemBlue
        case .bikePath: UIColor(red: 0.19, green: 0.70, blue: 0.43, alpha: 1)
        }
    }
}

extension QuestPath {
    var uiColor: UIColor {
        switch self {
        case .warrior: .systemRed
        case .explorer: .systemGreen
        case .mind: .systemIndigo
        }
    }
}
