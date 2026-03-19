import SwiftUI
import MapKit

struct SuggestedLocationsSection: View {
    let quest: Quest
    let appState: AppState
    @State private var poiService = MapPOIService()
    @State private var nearbyPOIs: [MapPOI] = []
    @State private var isLoading: Bool = false
    @State private var hasFetched: Bool = false

    private var mapCategory: MapQuestCategory? {
        quest.requiredPlaceType?.mapQuestCategory
    }

    private var categoryColor: Color {
        mapCategory?.mapColor ?? .blue
    }

    var body: some View {
        if let category = mapCategory {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.headline)
                        .foregroundStyle(categoryColor)
                    Text("Suggested Locations")
                        .font(.headline)
                    Spacer()
                    Button {
                        appState.pendingMapCategory = category
                        appState.selectedTab = 2
                    } label: {
                        HStack(spacing: 4) {
                            Text("View Map")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(categoryColor)
                    }
                }

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding nearby \(category.rawValue.lowercased()) locations...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                } else if nearbyPOIs.isEmpty && hasFetched {
                    VStack(spacing: 8) {
                        Image(systemName: "location.slash")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("No \(category.rawValue.lowercased()) locations found nearby")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            appState.pendingMapCategory = category
                            appState.selectedTab = 2
                        } label: {
                            Label("Search on Map", systemImage: "map.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(categoryColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(nearbyPOIs.prefix(4).enumerated()), id: \.element.id) { index, poi in
                            poiRow(poi: poi)
                            if index < min(nearbyPOIs.count, 4) - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))

                    if nearbyPOIs.count > 4 {
                        Button {
                            appState.pendingMapCategory = category
                            appState.selectedTab = 2
                        } label: {
                            HStack {
                                Image(systemName: "map.fill")
                                    .font(.caption)
                                Text("See all \(nearbyPOIs.count) locations on map")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(categoryColor)
                    }
                }
            }
            .task {
                guard !hasFetched else { return }
                await fetchNearbyPOIs(for: category)
            }
        }
    }

    private func poiRow(poi: MapPOI) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mapCategory?.icon ?? "mappin")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(categoryColor, in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let address = poi.address {
                    Text(address)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let distance = poi.distance {
                Text(formatDistance(distance))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                openInMaps(poi: poi)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(.blue.opacity(0.1), in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func fetchNearbyPOIs(for category: MapQuestCategory) async {
        isLoading = true
        if poiService.locationAuthorized {
            poiService.requestLocation()
            try? await Task.sleep(for: .seconds(2))
        }
        await poiService.searchPOIs(for: category)
        nearbyPOIs = poiService.pois
        isLoading = false
        hasFetched = true
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }

    private func openInMaps(poi: MapPOI) {
        let placemark = MKPlacemark(coordinate: poi.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = poi.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
