import SwiftUI

/// Main dashboard: high-contrast OLED speedometer with an animated gauge ring,
/// unit toggle and a shortcut into windshield HUD mode.
struct SpeedometerView: View {
    @EnvironmentObject private var gps: GPSManager
    @Environment(\.openURL) private var openURL

    @State private var isHUDVisible = false

    private var speedValue: Double { gps.speed(in: gps.preferredUnit) }
    private var fraction: Double { gps.speedFraction(in: gps.preferredUnit) }
    private var accentColor: Color { Color.speedColor(fraction: fraction) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                topBar

                Spacer(minLength: 8)

                gauge

                Spacer(minLength: 8)

                statsGrid

                permissionBanner
            }
            .padding(20)
        }
        .fullScreenCover(isPresented: $isHUDVisible) {
            HUDView()
                .environmentObject(gps)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            signalIndicator
            Spacer()
            unitToggle
            Spacer()
            hudButton
        }
    }

    private var signalIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(signalColor)
                .frame(width: 8, height: 8)
            Text(gps.signalQuality.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var signalColor: Color {
        switch gps.signalQuality {
        case .none: return .gray
        case .poor: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .excellent: return .green
        }
    }

    private var unitToggle: some View {
        Button {
            withAnimation(.snappy) {
                gps.preferredUnit = (gps.preferredUnit == .kilometersPerHour)
                    ? .milesPerHour
                    : .kilometersPerHour
            }
        } label: {
            Text(gps.preferredUnit.abbreviation)
                .font(.subheadline.bold())
                .monospacedDigit()
                .frame(width: 58, height: 30)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var hudButton: some View {
        Button {
            isHUDVisible = true
        } label: {
            Label("HUD", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gauge

    private var gauge: some View {
        SpeedGauge(
            fraction: fraction,
            text: String(format: "%.0f", speedValue),
            unit: gps.preferredUnit.abbreviation,
            color: accentColor
        )
        .padding(.horizontal, 24)
        .frame(maxWidth: 440)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            StatCard(
                title: "Average",
                value: String(format: "%.0f", gps.preferredUnit.convert(metersPerSecond: gps.averageSpeedMetersPerSecond)),
                subtitle: gps.preferredUnit.abbreviation
            )
            StatCard(
                title: "Max",
                value: String(format: "%.0f", gps.preferredUnit.convert(metersPerSecond: gps.maxSpeedMetersPerSecond)),
                subtitle: gps.preferredUnit.abbreviation
            )
            StatCard(
                title: "Distance",
                value: Formatting.distance(meters: gps.sessionDistanceMeters),
                subtitle: "since start"
            )
            StatCard(
                title: "GPS accuracy",
                value: gps.horizontalAccuracyMeters >= 0
                    ? String(format: "±%.0f m", gps.horizontalAccuracyMeters)
                    : "—",
                subtitle: gps.signalQuality.label
            )
        }
    }

    // MARK: - Permission banner

    @ViewBuilder
    private var permissionBanner: some View {
        switch gps.authorizationStatus {
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Label("Location access is off. Enable it in Settings to measure speed.",
                      systemImage: "location.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Open Settings") {
                    if let url = URL(string: "app-settings:") {
                        openURL(url)
                    }
                }
                .font(.footnote.bold())
                .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .notDetermined:
            Label("Waiting for location permission…", systemImage: "location")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }
}

// MARK: - Speed gauge

/// Circular progress ring with the speed read-out in the center.
private struct SpeedGauge: View {
    let fraction: Double
    let text: String
    let unit: String
    let color: Color

    private let lineWidth: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.07),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 12)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)

            VStack(spacing: 2) {
                Text(text)
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: text)

                Text(unit)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Stat card

/// A single metric tile on the dashboard.
private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .kerning(1.2)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Speed color scale

private struct RGBA {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

extension Color {
    /// Brand accent color used throughout the app.
    static let speedAccent = Color(red: 0.20, green: 0.85, blue: 0.36)

    private init(_ rgba: RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// Maps a 0...1 progress onto a green -> yellow -> red scale.
    static func speedColor(fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        let stops: [(Double, RGBA)] = [
            (0.0, RGBA(red: 0.20, green: 0.85, blue: 0.36, alpha: 1.0)),
            (0.5, RGBA(red: 1.00, green: 0.80, blue: 0.15, alpha: 1.0)),
            (1.0, RGBA(red: 1.00, green: 0.20, blue: 0.20, alpha: 1.0))
        ]

        for index in 0..<(stops.count - 1) {
            let lower = stops[index]
            let upper = stops[index + 1]
            if f >= lower.0 && f <= upper.0 {
                let span = upper.0 - lower.0
                let t = span > 0 ? (f - lower.0) / span : 0
                let mixed = RGBA(
                    red: lower.1.red + (upper.1.red - lower.1.red) * t,
                    green: lower.1.green + (upper.1.green - lower.1.green) * t,
                    blue: lower.1.blue + (upper.1.blue - lower.1.blue) * t,
                    alpha: lower.1.alpha + (upper.1.alpha - lower.1.alpha) * t
                )
                return Color(mixed)
            }
        }
        return Color(stops.last!.1)
    }
}
