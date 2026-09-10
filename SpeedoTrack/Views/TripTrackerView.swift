import SwiftUI
import MapKit
import Charts

/// Trip logger: recording controls, live route on MapKit, per-trip summary
/// statistics with a Swift Charts altitude profile, and the saved-trip list.
struct TripTrackerView: View {
    @EnvironmentObject private var gps: GPSManager
    @EnvironmentObject private var store: TripStore

    @State private var tripName: String = ""
    @State private var selectedTripID: UUID?
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    private var activeTrip: Trip? { gps.activeTrip }

    /// The trip currently shown on the map and in the summary cards.
    private var displayedTrip: Trip? {
        if let activeTrip { return activeTrip }
        if let selectedTripID, let trip = store.trips.first(where: { $0.id == selectedTripID }) {
            return trip
        }
        return store.trips.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    recordingCard
                    mapCard
                    if let trip = displayedTrip {
                        summaryCard(for: trip)
                        if trip.altitudeSamples.count > 1 {
                            altitudeChart(for: trip)
                        }
                    }
                    savedTripsSection
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Trip Tracker")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Recording controls

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Recording")

            if let trip = activeTrip {
                HStack {
                    statusPill(trip.status)
                    Spacer()
                    if trip.status == .recording {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text("LIVE")
                                .font(.caption2.bold())
                                .foregroundStyle(.red)
                        }
                    }
                }

                Text(trip.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                HStack(spacing: 24) {
                    liveMetric("Distance", Formatting.distance(meters: trip.distanceMeters))
                    liveMetric("Moving time", Formatting.duration(trip.movingSeconds))
                }

                HStack(spacing: 12) {
                    Button {
                        if trip.status == .recording {
                            gps.pauseTrip()
                        } else {
                            gps.resumeTrip()
                        }
                    } label: {
                        Label(trip.status == .recording ? "Pause" : "Resume",
                              systemImage: trip.status == .recording ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button(role: .destructive) {
                        if let finished = gps.finishTrip() {
                            store.add(finished)
                            selectedTripID = finished.id
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                TextField("Trip name (e.g. Morning commute)", text: $tripName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                Button {
                    gps.startTrip(named: tripName)
                    tripName = ""
                } label: {
                    Label("Start Trip", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.speedAccent)
            }
        }
        .card()
    }

    // MARK: - Map

    private var mapCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                if let trip = displayedTrip, trip.points.count > 1 {
                    MapPolyline(coordinates: trip.routeCoordinates)
                        .stroke(
                            Color.speedAccent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }

                if let trip = displayedTrip, let last = trip.points.last {
                    Annotation("", coordinate: last.coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.speedAccent)
                            .shadow(radius: 3)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                cameraPosition = .userLocation(fallback: .automatic)
            } label: {
                Image(systemName: "location.fill")
                    .font(.headline)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .foregroundStyle(Color.speedAccent)
            }
            .padding(12)
        }
    }

    // MARK: - Summary

    private func summaryCard(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(trip.status == .completed ? "Trip summary" : "Live summary")

            HStack(alignment: .firstTextBaseline) {
                Text(trip.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let ended = trip.endedAt {
                    Text(ended, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                SummaryMetric(title: "Moving", value: Formatting.duration(trip.movingSeconds))
                SummaryMetric(title: "Distance", value: Formatting.distance(meters: trip.distanceMeters))
                SummaryMetric(title: "Avg speed", value: String(format: "%.1f km/h", trip.averageSpeedKilometersPerHour))
                SummaryMetric(title: "Max speed", value: String(format: "%.0f km/h", trip.maxSpeedKilometersPerHour))
                SummaryMetric(title: "Ascent", value: String(format: "%.0f m", trip.totalAscentMeters))
                SummaryMetric(title: "Descent", value: String(format: "%.0f m", trip.totalDescentMeters))
            }
        }
        .card()
    }

    // MARK: - Altitude chart

    private func altitudeChart(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Altitude profile")

            Chart(trip.altitudeSamples) { sample in
                AreaMark(
                    x: .value("Distance", sample.distanceKilometers),
                    y: .value("Altitude", sample.altitudeMeters)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.speedAccent.opacity(0.45), Color.speedAccent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Distance", sample.distanceKilometers),
                    y: .value("Altitude", sample.altitudeMeters)
                )
                .foregroundStyle(Color.speedAccent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxisLabel("Distance (km)")
            .chartYAxisLabel("Altitude (m)")
            .frame(height: 200)
        }
        .card()
    }

    // MARK: - Saved trips

    private var savedTripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Saved trips")
                Spacer()
                if !store.trips.isEmpty {
                    Button("Clear") {
                        store.clearAll()
                        selectedTripID = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            if store.trips.isEmpty {
                Text("No saved trips yet. Start a trip and stop it to see it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.trips) { trip in
                    tripRow(trip)
                }
            }
        }
        .card()
    }

    private func tripRow(_ trip: Trip) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedTripID = trip.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trip.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text(trip.startedAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatting.distance(meters: trip.distanceMeters))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.speedAccent)
                    Image(systemName: selectedTripID == trip.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedTripID == trip.id ? Color.speedAccent : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                store.delete(trip)
                if selectedTripID == trip.id {
                    selectedTripID = nil
                }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Small building blocks

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .kerning(1.1)
            .textCase(.uppercase)
    }

    private func statusPill(_ status: TripStatus) -> some View {
        Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(statusColor(status).opacity(0.2)))
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: TripStatus) -> Color {
        switch status {
        case .recording: return .green
        case .paused: return .orange
        case .completed: return .blue
        }
    }

    private func liveMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Summary metric tile

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .kerning(1)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Card container

private extension View {
    func card() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }
}
