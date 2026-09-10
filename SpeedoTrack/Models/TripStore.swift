import Foundation
import Combine

/// Persists completed trips to disk as JSON and publishes them for the UI.
@MainActor
final class TripStore: ObservableObject {

    /// Saved trips, newest first.
    @Published private(set) var trips: [Trip] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileName: String = "speedotrack-trips.json") {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = documents.appendingPathComponent(fileName)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    // MARK: - Public API

    func add(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        trips.append(trip)
        trips.sort { $0.startedAt > $1.startedAt }
        persist()
    }

    func delete(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        persist()
    }

    func clearAll() {
        trips.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try encoder.encode(trips)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("SpeedoTrack: failed to persist trips — \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            trips = try decoder.decode([Trip].self, from: data)
            trips.sort { $0.startedAt > $1.startedAt }
        } catch {
            print("SpeedoTrack: failed to load trips — \(error)")
        }
    }
}
