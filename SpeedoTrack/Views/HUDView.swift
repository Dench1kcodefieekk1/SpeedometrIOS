import SwiftUI

/// Full-screen, horizontally mirrored display for projecting onto a car
/// windshield at night. The entire interface is flipped with
/// `.scaleEffect(x: -1, y: 1)` so it reads correctly when reflected.
struct HUDView: View {
    @EnvironmentObject private var gps: GPSManager
    @Environment(\.dismiss) private var dismiss

    private var speedValue: Double { gps.speed(in: gps.preferredUnit) }
    private var fraction: Double { gps.speedFraction(in: gps.preferredUnit) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text(String(format: "%.0f", speedValue))
                    .font(.system(size: 210, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.speedColor(fraction: fraction))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)

                Text(gps.preferredUnit.abbreviation)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Label("Tap anywhere to exit", systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 32)
            }
            .padding(24)
        }
        // Mirror the entire UI horizontally for windshield projection.
        .scaleEffect(x: -1, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .persistentSystemOverlays(.hidden)
    }
}
