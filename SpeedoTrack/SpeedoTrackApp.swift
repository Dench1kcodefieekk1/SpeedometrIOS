import SwiftUI

@main
@MainActor
struct SpeedoTrackApp: App {
    @StateObject private var gpsManager = GPSManager()
    @StateObject private var tripStore = TripStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gpsManager)
                .environmentObject(tripStore)
                .preferredColorScheme(.dark)
        }
    }
}

/// Top-level tab container for the app.
struct RootView: View {
    @EnvironmentObject private var gps: GPSManager

    var body: some View {
        TabView {
            SpeedometerView()
                .tabItem {
                    Label("Speedometer", systemImage: "speedometer")
                }

            TripTrackerView()
                .tabItem {
                    Label("Trips", systemImage: "map.fill")
                }
        }
        .tint(Color.speedAccent)
        .onAppear { gps.start() }
    }
}
