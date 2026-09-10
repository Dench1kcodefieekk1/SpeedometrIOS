import Foundation
import CoreLocation

/// Represents the recording status of a trip.
enum TripStatus: String, Codable, CaseIterable, Sendable {
    case recording
    case paused
    case completed

    var title: String {
        switch self {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .completed: return "Completed"
        }
    }
}

/// A single geo-located sample captured while a trip is being recorded.
struct TripPoint: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    /// Speed reported by the GPS receiver, in meters per second.
    let speed: Double
    /// Course over ground in degrees (0 = north, 90 = east).
    let course: Double
    /// Horizontal accuracy in meters.
    let horizontalAccuracy: Double
    /// Vertical accuracy in meters.
    let verticalAccuracy: Double

    init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        speed: Double,
        course: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
    }

    /// Core Location coordinate used for MapKit rendering.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var speedKilometersPerHour: Double { speed * 3.6 }
    var speedMilesPerHour: Double { speed * 2.23694 }
    var speedKnots: Double { speed * 1.94384 }
}

/// A single sample used by Swift Charts to render the altitude profile.
struct AltitudeSample: Identifiable, Hashable, Sendable {
    let id: Int
    /// Cumulative distance from the trip start, in kilometers.
    let distanceKilometers: Double
    /// Altitude in meters.
    let altitudeMeters: Double
}

/// A complete trip: the recorded route plus its live and computed statistics.
struct Trip: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let startedAt: Date
    var endedAt: Date?
    var status: TripStatus

    /// Captured route samples, ordered by timestamp.
    var points: [TripPoint]

    /// Accumulated route length in meters.
    var distanceMeters: Double
    /// Time (seconds) actually spent moving (speed >= moving threshold).
    var movingSeconds: Double
    /// Time (seconds) spent paused.
    var pausedSeconds: Double
    /// Highest speed observed, in meters per second.
    var maxSpeedMetersPerSecond: Double
    /// Cumulative climb in meters.
    var totalAscentMeters: Double
    /// Cumulative descent in meters.
    var totalDescentMeters: Double

    init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: TripStatus = .recording
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.points = []
        self.distanceMeters = 0
        self.movingSeconds = 0
        self.pausedSeconds = 0
        self.maxSpeedMetersPerSecond = 0
        self.totalAscentMeters = 0
        self.totalDescentMeters = 0
    }

    // MARK: - Recording

    /// Appends a new GPS sample and updates the rolling statistics.
    mutating func record(_ point: TripPoint) {
        guard status == .recording else { return }

        if let previous = points.last {
            let deltaTime = point.timestamp.timeIntervalSince(previous.timestamp)
            let deltaDistance = Self.distanceBetween(
                latitude: previous.latitude, longitude: previous.longitude,
                andLatitude: point.latitude, longitude: point.longitude
            )

            // Ignore stale samples and obvious GPS glitches.
            if deltaTime > 0, deltaTime < 300, point.horizontalAccuracy <= 50 {
                distanceMeters += deltaDistance

                if point.speed >= Self.movingSpeedThreshold {
                    movingSeconds += deltaTime
                }

                if point.speed >= 0 {
                    maxSpeedMetersPerSecond = max(maxSpeedMetersPerSecond, point.speed)
                }

                let altitudeDelta = point.altitude - previous.altitude
                if altitudeDelta > 0 {
                    totalAscentMeters += altitudeDelta
                } else {
                    totalDescentMeters += abs(altitudeDelta)
                }
            }
        }

        points.append(point)
    }

    // MARK: - Summary

    /// Wall-clock duration of the trip, excluding pauses.
    var elapsedSeconds: Double {
        let end = endedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds)
    }

    var currentSpeedMetersPerSecond: Double { points.last?.speed ?? 0 }
    var currentSpeedKilometersPerHour: Double { currentSpeedMetersPerSecond * 3.6 }

    var averageSpeedMetersPerSecond: Double {
        guard movingSeconds > 0 else { return 0 }
        return distanceMeters / movingSeconds
    }

    var averageSpeedKilometersPerHour: Double { averageSpeedMetersPerSecond * 3.6 }
    var averageSpeedMilesPerHour: Double { averageSpeedMetersPerSecond * 2.23694 }
    var averageSpeedKnots: Double { averageSpeedMetersPerSecond * 1.94384 }

    var maxSpeedKilometersPerHour: Double { maxSpeedMetersPerSecond * 3.6 }
    var maxSpeedMilesPerHour: Double { maxSpeedMetersPerSecond * 2.23694 }
    var maxSpeedKnots: Double { maxSpeedMetersPerSecond * 1.94384 }

    /// Distance-based altitude profile used by the summary charts.
    var altitudeSamples: [AltitudeSample] {
        var samples: [AltitudeSample] = []
        var cumulativeDistance = 0.0
        var previous: TripPoint?

        for (index, point) in points.enumerated() {
            if let previous {
                cumulativeDistance += Self.distanceBetween(
                    latitude: previous.latitude, longitude: previous.longitude,
                    andLatitude: point.latitude, longitude: point.longitude
                )
            }
            samples.append(
                AltitudeSample(
                    id: index,
                    distanceKilometers: cumulativeDistance / 1000,
                    altitudeMeters: point.altitude
                )
            )
            previous = point
        }
        return samples
    }

    /// Route coordinates for MapKit rendering.
    var routeCoordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    // MARK: - Helpers

    /// Below this speed (m/s) the vehicle is considered stationary.
    static let movingSpeedThreshold = 0.5

    /// Great-circle distance between two coordinates using the haversine formula.
    static func distanceBetween(
        latitude lat1: Double, longitude lon1: Double,
        andLatitude lat2: Double, longitude lon2: Double
    ) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

/// Small shared formatting helpers used across the UI.
enum Formatting {
    /// Formats a duration as `mm:ss` or `h:mm:ss`.
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Formats a distance in meters as meters or kilometers.
    static func distance(meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
