# Architecture discovered in the source

## Flutter structure and state

`main.dart` mounts `AiCheatApp` and an `AppLaunch` initialization gate. Firebase
initializes before an auth stream selects login or a Firestore profile stream.
Profiles route pending/rejected accounts to status screens and approved accounts
to student/teacher workspaces or the web-admin dashboard. Unknown approval values
now fail closed as pending. Client navigation is not server-side authorization.

State is local `StatefulWidget`/`setState`, `StreamBuilder` for Firebase, and
`ValueNotifier` for the exam timer. There is no Provider/BLoC/Riverpod layer and
no need to introduce one for this audit. Shared visual components, route observers,
responsive wrappers and the existing cream/green theme are retained.

## Identity and persistence

- Firebase Auth handles email/password, Google credentials (popup on web),
  password-reset email and native auth-session persistence.
- Firestore `users/{uid}` stores identity/profile, role, approval status and
  creation time. Student/teacher registration requests start pending.
- `violations` receives local-exam termination metadata: student ID/email,
  reason, counters, pose/gaze/attention and timestamp. Teacher/admin screens read
  incident lists; student queries filter by their user ID.
- Teacher views also read `dvr_alerts`. No local writer for those external records
  was found. Media analysis screens do not write image/video incidents to Firebase.
- No custom local database/preferences layer was found. Selected media, remote
  job state, warning buffers and completion scores are in-memory. Firebase SDK
  caching/session behavior must not be confused with a durable local job system.
- Firestore rules/indexes and the live project configuration are external;
  deployed authorization and end-to-end account approval are **NOT VERIFIED**.

## Exam pipeline (on device)

Rules → camera ready → Begin Exam → collect 15 single-face pose observations →
median calibration baseline → start 30-minute clock → monitor while answering
three fixed questions → finish locally or terminate on the existing policy.

`CameraScreen` owns a session-scoped `AiHandler`, `FrameProcessor`, `ExamMonitor`,
camera controller and timer. `FrameProcessor` drops work while busy rather than
queuing every preview frame (80 ms minimum interval with additional headroom).
Preview and AI inference rates are distinct.

`AiHandler` runs ML Kit face detection, image labeling and candidate object
localization; Android also attempts face mesh. Normalized pose uses calibration
baselines, smoothing and per-signal consecutive counters. Default image labeling
provides phone/book/device evidence; ML Kit's default object detector supplies
coarse boxes, not a custom phone classifier. Fallback boxes are estimates, not
localized YOLO output.

Current local policy includes phone score ≥0.55 for two samples, three-sample
stability for other device candidates, separate device/presence/pose counters,
and termination on configured thresholds. These are **not the remote YOLO
per-class thresholds**. Phone confirmation can terminate even during calibration;
that pre-existing strict demo behavior is retained.

`ExamMonitor` evaluates device, presence, head and gaze signals independently and
prioritizes terminating/critical warnings while retaining concurrent details.
Tests cover distinct classifications so unrelated activities are not all labeled
“Head Turn.” Missing/multiple faces suppress head/gaze display.

The mesh plugin's 468 landmarks cannot satisfy the legacy 478-point iris branch.
The code explicitly reports iris unavailable. iOS skips mesh entirely. Do not
advertise validated eye-only iris tracking. Attention score is a hand-tuned
penalty metric; blink/pose data are observations rather than verified cheating.

Termination attempts one Firestore incident write and shows a review message.
Saving can fail and is not guaranteed by the dialog. Normal finish/time expiry
stops the timer and image stream and shows a local answer summary. There is no
server-side question bank, grade persistence or secure timed-exam enforcement.

## Remote analysis

`ApiService` is owned by each analysis screen and uses `ApiConfig` as the default
endpoint source. It validates response structure, bounds requests and closes I/O
on disposal. It does not contain API credentials.

- **Image:** gallery/camera → bounded image bytes → multipart POST → JSON parsing
  → base64 JPEG annotation → raw detections and accepted-violation list. The
  backend now draws raw boxes neutrally and accepted confidence-qualified image
  violations in red. Image analysis has no temporal streak requirement.
- **Live Detection:** separate screen → low-resolution camera → isolate JPEG
  conversion → at most one remote image request at a time, spaced by at least a
  second → server annotation/raw detections/accepted list. The event counter is
  repeated accepted observations, not distinct backend student-risk incidents.
- **Video:** selected path and local preview → streamed mobile upload (web bytes)
  → returned job ID → bounded serial polling → progress → `/video/{id}` player.
  The server draws neutral raw boxes and adds strong red banners only when the
  per-class confidence threshold, three-observation streak and 45-frame cooldown
  all allow an accepted event.

The inspected backend is `backend/main.py`: FastAPI + Ultralytics YOLO + OpenCV,
NumPy and SciPy. Image inference is synchronous. Video uploads create in-memory
jobs handled by a two-worker `ThreadPoolExecutor`; OpenCV decodes frames, writes
annotated MP4 (`mp4v`), and progress is exposed through `/job/{id}`. Calls to the
shared Ultralytics predictor are serialized with a lock to avoid concurrent use
of its mutable predictor state. Fixed seat
anchors are estimated from the first 60 frames and matched by Hungarian
assignment with a strict center-distance gate below 150 pixels. The person risk
summary counts accepted incidents associated with each fixed seat; its
percentage is a capped count heuristic, not calibrated probability.
Anchors do not expire; a new person near a prior seat can inherit its slot and
risk count.

The backend source is present, but the real weights and deployed Colab runtime
are not. Source behavior can be unit-tested with mocked inference; actual model,
Colab parity, media codec support on devices, and runtime performance remain
**NOT VERIFIED**.

`showing_paper` is in `SKIP_CLASSES`. It is excluded from video detections and
violations; image responses may contain it as a neutral raw detection, but never
as an accepted violation. The configured violation list has no `person_normal`.

## Lifecycle and platform support

`CameraActivity` observes app and route state; inference streams suspend in the
background or when covered. `releaseCamera` serializes cleanup and now releases
resources even when pending startup failed. `AiHandler.dispose` waits for native
inference before closing detectors. Hardware resume/driver behavior still needs
Android/iOS testing; stopping a stream is not full release of the native camera
on every platform.

Video selection is locked during analysis; new player sessions use generation
checks and captured controller references. Controllers and polling clients close
on disposal; playback pauses while hidden. Native playback and changing codecs
need device tests. The remote job itself is not cancelled by client navigation.

Android is the primary exam target. iOS has explicit BGRA handling and ML Kit
compatibility patches. Web admin works through Flutter/Firebase; camera/ML Kit
mobile paths are not a general desktop/web implementation. Other platform folders
are scaffolding, not proof of supported proctoring on those platforms.

## Retained historical material

`lib/services/ai_handler_legacy.dart` is the unused older implementation, renamed
from an invalid spaced filename and cleaned without deleting its behavior.
`assets/models/detection_result.dart` is an unused historical DTO. Local weight/
export artifacts remain on disk but are excluded from publication. Older audit
notes are marked historical; their line numbers and old findings may be stale.
