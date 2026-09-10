# SpeedoTrack

A high-precision GPS **Speedometer & Trip Logger** with a windshield **HUD mode**.
Native iOS, written in **Swift 6** and **SwiftUI**, targeting **iOS 18+**.

## Features

- **Live speedometer** — current / average / max speed in **km/h**, **mph** and **knots**,
  total distance, and GPS signal strength (derived from horizontal accuracy).
- **High-contrast OLED theme** with a smooth animated gauge ring that shifts
  **green → yellow → red** as speed increases.
- **HUD mode** — mirrors the whole interface horizontally
  (`.scaleEffect(x: -1, y: 1)`) so the iPhone can project the speedometer onto a
  car windshield at night.
- **Trip logger** — start / pause / resume / stop recording, live route rendering
  with **MapKit**, and per-trip summaries (moving time, distance, average speed,
  altitude profile) rendered with **Swift Charts**.
- **Trip persistence** — completed trips are stored as JSON in the app's
  Documents directory.

## Project structure

```
.
├── project.yml                       # XcodeGen project definition
├── ExportOptions.plist               # xcodebuild export template
├── .github/workflows/build_ipa.yml   # CI pipeline (manual trigger)
└── SpeedoTrack/
    ├── SpeedoTrackApp.swift
    ├── Models/
    │   ├── Trip.swift
    │   └── TripStore.swift
    ├── Services/
    │   └── GPSManager.swift
    ├── Views/
    │   ├── SpeedometerView.swift
    │   ├── TripTrackerView.swift
    │   └── HUDView.swift
    ├── Assets.xcassets/
    └── Info.plist
```

## Requirements

- Xcode 16+ (iOS 18 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building locally

```bash
xcodegen generate
open SpeedoTrack.xcodeproj
```

The `.xcodeproj` is generated and intentionally not committed to Git.

## CI: building an IPA

The `.github/workflows/build_ipa.yml` workflow runs on `macos-latest` and is
triggered manually (`workflow_dispatch`). It:

1. Checks out the repository and installs XcodeGen.
2. Generates `SpeedoTrack.xcodeproj` with `xcodegen generate`.
3. Imports the signing certificate and provisioning profile into a temporary
   keychain.
4. Archives with `xcodebuild archive`.
5. Exports the IPA with `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist`.
6. Uploads the IPA (and dSYMs) as workflow artifacts.

### Required repository secrets

| Secret | Description |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution certificate |
| `P12_PASSWORD` | Password of the `.p12` certificate |
| `PROVISION_PROFILE_BASE64` | Base64-encoded `.mobileprovision` profile |
| `DEVELOPMENT_TEAM` | Apple Developer team ID |
| `PROVISIONING_PROFILE_NAME` | Name of the provisioning profile |
| `KEYCHAIN_PASSWORD` | (optional) password for the temporary keychain |

`ExportOptions.plist` is a template: the workflow replaces `YOUR_TEAM_ID` and
`YOUR_PROVISIONING_PROFILE_NAME` with the configured secrets before export.
