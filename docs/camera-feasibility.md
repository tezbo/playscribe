# Camera add-flow feasibility (0.5.0 item 12)

Checked 3 Nov 2026 against developer.apple.com DocC JSON (not memory). Verdict: **feasible, zero cost, all on device.**

| Need | API | Availability (Apple docs) | Notes |
|---|---|---|---|
| Live scan of game boxes, spines and screens | VisionKit `DataScannerViewController` (`recognizedDataTypes: [.text()]`) | iOS 16+ | Check `isSupported` (hardware) and `isAvailable` (camera permission, restrictions) before showing it; else fall back to photo or typing. |
| Read text from a photo | Vision `RecognizeTextRequest` | iOS 18+ | Runs on device. Match recognised lines against the catalogue by name. |
| Pick a photo | SwiftUI `PhotosPicker` | iOS 16+ | Runs out of process, needs no photo-library permission. |
| Say it | Speech `SpeechAnalyzer` | iOS 26+ | On device. Needs `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription`. |
| Tidy names / many titles from one read | Foundation Models | iOS 26+ | Optional. Plain fuzzy match on the catalogue works without it. |

## iPhone Duo
- Each display has a camera, and which way a camera faces depends on the display the app is on. Opening or closing the device moves the app to the other display (AVKit: "Choosing a camera by the direction it faces"). `DataScannerViewController` picks its camera itself, so the app must not assume rear vs front; the scan screen follows the pose like any other screen.
- The inner front camera is a reserved region while active; the scanner's own controls stay outside `.occlusion` and `.division` regions, and every control sits on the trailing rail in Tabletop (no tappable element above the fold).
- Only custom `AVCaptureSession` code needs the AVKit coordinator. The scanner and `PhotosPicker` do not.

## Needed in the app
- `NSCameraUsageDescription` (scan), plus the two speech strings for "Say it". No Info.plist usage strings exist yet.
- Camera decline or `isAvailable == false` falls back to From a photo, Say it or Type it. First run with an empty library offers all four.
- Matching: normalise recognised text, fuzzy-match against `Catalog`/`PS5Index` names, show candidates as live chips; never auto-add without a tap.

## Open for Iris and Theo
- Say it needs iOS 26+; the deployment target is iOS 27.1 (`ios/project.yml`), so every API above is available with no fallbacks for older systems.
- Physical Duo needed to judge scanner framing in Tabletop; the simulator camera is not representative.
