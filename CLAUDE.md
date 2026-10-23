# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**AI Guard Pro** — a Flutter mobile app that proctors online exams using Google ML Kit. It monitors students via the front camera and flags cheating behaviours in real time.

## Commands

```bash
# Run on connected device / emulator
flutter run

# Run on Android specifically
flutter run -d android

# Build release APK
flutter build apk --release

# Analyze for lint errors
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Get packages after pubspec changes
flutter pub get
```

## Architecture

### Entry point — `lib/main.dart`
- Initializes Firebase, then calls `AiHandler().initModel()` **before** `runApp` so all four ML engines are warm when the exam starts.
- Auth gate: `StreamBuilder` on `FirebaseAuth.authStateChanges` routes to `LoginScreen` or `DashboardScreen`.

### AI engine — `lib/services/ai_handler.dart` (singleton)
The core detection pipeline. Four ML Kit engines run sequentially per frame:

| Engine | Purpose |
|--------|---------|
| `FaceDetector` | Face count, head Euler angles (yaw/pitch/roll), eye-open probability |
| `FaceMeshDetector` | 468-landmark iris gaze — used only when head is nearly forward (±10°) |
| `ImageLabeler` | Scene-level device detection (phone/laptop/monitor/book) |
| `ObjectDetector` | Bounding box for detected devices |

**Axis correction (critical knowledge):**
ML Kit's front-camera Euler angles are not intuitive:
- `headEulerAngleY` (yaw): positive = face turned **LEFT** (mirror effect) → negated to get student-perspective right.
- `headEulerAngleX` (pitch): positive = looking **UP** (already correct, v7 had this wrong).
- Correction: `correctedYaw = -(rawYaw - yawBaseline)`, `correctedPitch = +(rawPitch - pitchBaseline)`.

**Calibration:** First 15 frames with a visible face collect baseline yaw/pitch (median). No violations are raised during calibration.

**Gaze thresholds (post-correction):**
- `correctedYaw > +20°` → looking Right; `< -20°` → looking Left
- `correctedPitch > +15°` → looking Up; `< -20°` → looking Down

**Eye-only gaze** (`_computeEyeOnlyGaze`): Uses iris X position relative to eye corners via face mesh landmarks 33/133/263/362. Only overrides head-pose result for strong sideways movement when head is within ±10°.

**Frame rate:** Throttled to 150 ms intervals in `CameraScreen._onCameraFrame`. The `_mlBusy` flag prevents overlapping pipeline runs.

**Attention score (0–100):** Deducts points for gaze away, head turned, eyes closed, suspicious rapid gaze switching (>6 direction changes in 30 frames), no face, or multiple faces.

### Camera screen — `lib/screens/dashboard/camera_screen.dart`
- Selects front camera, sets rotation via `AiHandler.setCameraRotation`.
- Uses `ResolutionPreset.medium` + `ImageFormatGroup.nv21` for Android.
- `_BBoxPainter` draws normalized `Rect` objects (0–1 coordinates) scaled to widget size, accounting for camera aspect ratio.
- Violation thresholds: 6 gaze-away frames → terminate; 5 head-turn frames → terminate; 5 device frames → terminate; 40 no-face frames → terminate; 15 multi-person frames → terminate.

### Auth — `lib/services/auth_service.dart`
Thin wrapper around `FirebaseAuth` (email/password sign-up and login). Google Sign-In stub is not implemented.

### Navigation flow
`LoginScreen` / `SignupScreen` → `DashboardScreen` → `CameraScreen` (exam session)

## Key dependencies

- `google_mlkit_face_detection ^0.11.0` — Euler angles, eye probability, landmarks
- `google_mlkit_face_mesh_detection ^0.1.0` — 468-point mesh for iris gaze
- `google_mlkit_object_detection ^0.12.0` — stream mode bounding boxes
- `google_mlkit_image_labeling ^0.12.0` — scene-level labels
- All ML Kit packages share `google_mlkit_commons ^0.7.x` — keep versions in sync.

## Android-specific notes

- `google-services.json` is at `android/app/google-services.json` (required for Firebase).
- Camera image format is `nv21` on Android; BGRA8888 single-plane path exists for iOS.
- `_toInputImage` in `AiHandler` manually packs NV21 (interleaved VU) from YUV planes when 3 planes are present.
- Sensor orientation is passed from `CameraDescription.sensorOrientation` to set the correct `InputImageRotation`.
