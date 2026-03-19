import SwiftUI
import MapKit

struct SessionSummaryView: View {
    let session: TrackingSession
    let quest: Quest
    var isGroupRun: Bool = false
    var handshakeVerified: Bool = false
    var groupSize: Int = 1
    let onSubmit: () -> Void
    let onDiscard: () -> Void
    @State private var showDiscardConfirm: Bool = false

    private var pathColor: Color {
        PathColorHelper.color(for: quest.path)
    }

    private var routeRegion: MKCoordinateRegion {
        guard !session.routePoints.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        let lats = session.routePoints.map(\.latitude)
        let lons = session.routePoints.map(\.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (lats.max()! - lats.min()!) * 1.5),
            longitudeDelta: max(0.005, (lons.max()! - lons.min()!) * 1.5)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                mapThumbnail
                statsGrid
                if isGroupRun {
                    groupBonusSection
                }
                integritySection
                actionButtons
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Session Summary")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Discard Session?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) { onDiscard() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Your tracking data will be permanently lost.")
        }
    }

    private var mapThumbnail: some View {
        Map(position: .constant(.region(routeRegion)), interactionModes: []) {
            if session.coordinates.count >= 2 {
                MapPolyline(coordinates: session.coordinates)
                    .stroke(pathColor.gradient, lineWidth: 4)
            }
            if let start = session.coordinates.first {
                Annotation("Start", coordinate: start) {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Circle().stroke(.white, lineWidth: 2)
                        }
                }
            }
            if let end = session.coordinates.last, session.coordinates.count > 1 {
                Annotation("End", coordinate: end) {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(pathColor)
                        .padding(4)
                        .background(.white, in: Circle())
                }
            }
        }
        .mapStyle(.standard)
        .frame(height: 220)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(String(format: "%.2f", session.totalEstimatedDistanceMiles))
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("miles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Text(formatDuration(session.durationSeconds))
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("duration")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Text(formatPace(session.averagePaceMinutesPerMile))
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("avg pace")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var integritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.wasDisqualified {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disqualified")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.red)
                        Text("This session cannot be submitted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(session.integrityFlags, id: \.self) { flag in
                            Label(flagDescription(flag), systemImage: flag.isCritical ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(flag.isCritical ? .red : .orange)
                        }
                        if session.maxRecordedSpeedMph > 0 {
                            Text("Peak speed: \(Int(session.maxRecordedSpeedMph)) mph")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if session.isValid {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session Valid")
                            .font(.subheadline.weight(.semibold))
                        Text("No integrity issues detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Issues Detected")
                            .font(.subheadline.weight(.semibold))
                        ForEach(session.integrityFlags, id: \.self) { flag in
                            Label(flagDescription(flag), systemImage: flag.isCritical ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(flag.isCritical ? .red : .orange)
                        }
                    }
                }
            }

            if let timeVerified = session.timeWindowVerified {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: timeVerified ? "clock.badge.checkmark.fill" : "clock.badge.exclamationmark.fill")
                        .font(.title3)
                        .foregroundStyle(timeVerified ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeVerified ? "Time Window Verified" : "Outside Time Window")
                            .font(.subheadline.weight(.semibold))
                        if let start = session.startedAt, let end = session.endedAt {
                            let formatter = DateFormatter()
                            let _ = formatter.dateFormat = "h:mm a"
                            Text("\(formatter.string(from: start)) \u{2013} \(formatter.string(from: end))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var groupBonusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Group Run")
                        .font(.subheadline.weight(.bold))
                    Text("\(groupSize) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("1.2x")
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.blue)
                    Text("Group")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 28)

                VStack(spacing: 2) {
                    Text(handshakeVerified ? "+5%" : "—")
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(handshakeVerified ? .green : .secondary)
                    Text("Handshake")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 28)

                VStack(spacing: 2) {
                    let mult = handshakeVerified ? 1.26 : 1.2
                    Text("\(String(format: "%.2f", mult))x")
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.orange)
                    Text("Total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if handshakeVerified {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("NFC Handshake verified — +5% bonus active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Paths will be compared for 70%+ similarity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if session.wasDisqualified {
                Button {
                    onDiscard()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
            } else {
                Button {
                    onSubmit()
                } label: {
                    Label("Submit for Verification", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(pathColor)

                Button(role: .destructive) {
                    showDiscardConfirm = true
                } label: {
                    Text("Discard")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private func flagDescription(_ flag: IntegrityFlag) -> String {
        switch flag {
        case .teleportDetected: "GPS teleport detected — possible spoofing"
        case .carSpeedDetected: "Vehicle speed detected"
        case .sustainedDriving: "Sustained vehicle speed over multiple readings"
        case .excessivePause: "Excessive pause time"
        case .weakGPS: "Weak GPS signal"
        case .sessionTooShort: "Session completed too quickly"
        case .outsideTimeWindow: "Session outside required time window"
        case .timeLimitExpired: "Time limit expired before goal reached"
        case .clockManipulated: "Clock manipulation detected — time integrity failed"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func formatPace(_ minutesPerMile: Double?) -> String {
        guard let pace = minutesPerMile else { return "--'--\"" }
        let m = Int(pace)
        let s = Int((pace - Double(m)) * 60)
        return String(format: "%d'%02d\"", m, s)
    }
}
