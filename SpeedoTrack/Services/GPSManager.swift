import Foundation
import CoreLocation
import Combine

/// Preferred speed unit for display.
enum SpeedUnit: String, CaseIterable, Identifiable, Sendable {
    case kilometersPerHour
    case milesPerHour
    case knots

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .kilometersPerHour: return "km/h"
        case .milesPerHour: return "mph"
        case .knots: return "kn"
        }
    }

    /// Converts a meters-per-second value into this unit.
    func convert(metersPerSecond: Double) -> Double {
        switch self {
        case .kilometersPerHour: return metersPerSecond * 3.6
        case .milesPerHour: return metersPerSecond * 2.23694
        case .knots: return metersPerSecond * 1.94384
        }
    }
}

/// Qualitative strength of the GPS fix, derived from horizontal accuracy.
enum GPSSignalQuality: String, Sendable {
    case none
    case poor
    case fair
    case good
    case excellent

    var label: String {
        switch self {
        case .none: return "No signal"
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }

    init(horizontalAccuracy: Double?) {
        guard let accuracy = horizontalAccuracy, accuracy >= 0 else {
            self = .none
            return
        }
        switch accuracy {
        case ..<5: self = .excellent
        case ..<15: self = .good
        case ..<50: self = .fair
        default: self = .poor
        }
    }
}

/// High-precision GPS engine for SpeedoTrack.
///
/// Bridges `CLLocationManager` to SwiftUI using Swift Concurrency: the class is
/// `@MainActor`-isolated and — because `CLLocationManagerDelegate` is annotated
/// `@MainActor` in the iOS 18 SDK — its delegate callbacks are delivered on the
/// main actor, so all observable state is updated safely.
@MainActor
final class GPSManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published state

    /// The most recent valid location fix.
    @Published private(set) var currentLocation: CLLocation?

    /// Current speed in meters per second (canonical value).
    @Published private(set) var speedMetersPerSecond: Double = 0
    @Published private(set) var speedKilometersPerHour: Double = 0
    @Published private(set) var speedMilesPerHour: Double = 0
    @Published private(set) var speedKnots: Double = 0

    /// Session aggregates (since GPS tracking started).
    @Published private(set) var averageSpeedKilometersPerHour: Double = 0
    @Published private(set) var maxSpeedKilometersPerHour: Double = 0
    @Published private(set) var sessionDistanceMeters: Double = 0
    @Published private(set) var sessionMovingSeconds: Double = 0

    /// Horizontal accuracy of the latest fix, in meters (`-1` when unknown).
    @Published private(set) var horizontalAccuracyMeters: Double = -1
    @Published private(set) var signalQuality: GPSSignalQuality = .none

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isUpdating: Bool = false
    @Published private(set) var lastErrorDescription: String?

    /// Display unit preference.
    @Published var preferredUnit: SpeedUnit = .kilometersPerHour

    /// The trip currently being recorded, if any.
    @Published private(set) var activeTrip: Trip?

    // MARK: - Private state

    private let locationManager = CLLocationManager()
    private var sessionStartedAt: Date?
    private var lastLocation: CLLocation?

    // MARK: - Lifecycle

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = 1.0
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Convenience accessors

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    var averageSpeedMetersPerSecond: Double {
        guard sessionMovingSeconds > 0 else { return 0 }
        return sessionDistanceMeters / sessionMovingSeconds
    }

    var maxSpeedMetersPerSecond: Double { maxSpeedKilometersPerHour / 3.6 }

    var sessionElapsedSeconds: Double {
        guard let startedAt = sessionStartedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    /// Speed converted into the requested unit.
    func speed(in unit: SpeedUnit) -> Double {
        unit.convert(metersPerSecond: speedMetersPerSecond)
    }

    /// 0...1 progress against a unit-appropriate full-scale value.
    func speedFraction(in unit: SpeedUnit) -> Double {
        let value = speed(in: unit)
        let fullScale: Double
        switch unit {
        case .kilometersPerHour: fullScale = 200
        case .milesPerHour: fullScale = 124
        case .knots: fullScale = 108
        }
        return min(max(value / fullScale, 0), 1)
    }

    // MARK: - Tracking control

    /// Requests location permission (if needed) and starts delivering updates.
    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            lastErrorDescription = "Location services are disabled on this device."
            return
        }

        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        guard isAuthorized else { return }
        beginUpdates()
    }

    /// Stops delivering location updates.
    func stop() {
        endUpdates()
    }

    private func beginUpdates() {
        guard !isUpdating else { return }
        if sessionStartedAt == nil {
            sessionStartedAt = Date()
        }
        isUpdating = true
        locationManager.startUpdatingLocation()
    }

    private func endUpdates() {
        guard isUpdating else { return }
        locationManager.stopUpdatingLocation()
        isUpdating = false
    }

    // MARK: - Trip recording

    func startTrip(named name: String) {
        guard activeTrip == nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTrip = Trip(name: trimmed.isEmpty ? "Trip" : trimmed)
    }

    func pauseTrip() {
        guard activeTrip != nil else { return }
        activeTrip?.status = .paused
    }

    func resumeTrip() {
        guard activeTrip?.status == .paused else { return }
        activeTrip?.status = .recording
    }

    /// Finalizes the active trip and hands it back to the caller for storage.
    func finishTrip() -> Trip? {
        guard var trip = activeTrip else { return nil }
        trip.status = .completed
        trip.endedAt = Date()
        activeTrip = nil
        return trip
    }

    // MARK: - Sample processing

    private func process(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return }

        let speedMS = location.speed >= 0 ? location.speed : computedSpeed(for: location)

        // Session distance & moving time.
        if let previous = lastLocation, location.timestamp >= previous.timestamp {
            let delta = location.distance(from: previous)
            let deltaTime = location.timestamp.timeIntervalSince(previous.timestamp)
            if deltaTime > 0, deltaTime < 300, location.horizontalAccuracy <= 50 {
                sessionDistanceMeters += delta
                if speedMS >= Trip.movingSpeedThreshold {
                    sessionMovingSeconds += deltaTime
                }
            }
        }

        lastLocation = location
        currentLocation = location
        horizontalAccuracyMeters = location.horizontalAccuracy
        signalQuality = GPSSignalQuality(horizontalAccuracy: location.horizontalAccuracy)

        speedMetersPerSecond = speedMS
        speedKilometersPerHour = speedMS * 3.6
        speedMilesPerHour = speedMS * 2.23694
        speedKnots = speedMS * 1.94384
        maxSpeedKilometersPerHour = max(maxSpeedKilometersPerHour, speedKilometersPerHour)

        updateSessionAverage()

        // Feed the active trip.
        if var trip = activeTrip {
            let point = TripPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speed: speedMS,
                course: location.course,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy
            )
            trip.record(point)
            activeTrip = trip
        }
    }

    /// Fallback speed estimate derived from the last two fixes when the
    /// receiver does not report a speed (e.g. simulated locations).
    private func computedSpeed(for location: CLLocation) -> Double {
        guard let previous = lastLocation else { return 0 }
        let delta = location.distance(from: previous)
        let deltaTime = location.timestamp.timeIntervalSince(previous.timestamp)
        guard deltaTime > 0 else { return 0 }
        return min(delta / deltaTime, 130) // cap at 130 m/s to filter glitches
    }

    private func updateSessionAverage() {
        // Keep the published km/h value consistent with `averageSpeedMetersPerSecond`,
        // which is based on moving time rather than raw wall-clock time.
        averageSpeedKilometersPerHour = averageSpeedMetersPerSecond * 3.6
    }
}

// MARK: - CLLocationManagerDelegate

extension GPSManager {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            beginUpdates()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            endUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        process(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .locationUnknown {
            // Transient failure; the GPS is still trying to acquire a fix.
            return
        }
        lastErrorDescription = error.localizedDescription
    }
}
