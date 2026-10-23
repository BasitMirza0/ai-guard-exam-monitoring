# AI Guard project audit

This report covers the Flutter application, the supplied real backend source at
`backend/main.py`, tests, Android configuration, publication files and Git
metadata. The working Colab runtime, private model weights and Firebase rules
were not supplied for execution or review.

## Architecture

- The exam camera runs on-device Google ML Kit face detection, pose, image labels
  and coarse object localization. The separate Live Detection and
  Image/Video Analysis paths upload media to the FastAPI service; YOLO is not
  running inside Flutter.
- The backend loads Ultralytics YOLO at import from
  `/content/best_model_merged.pt`. Image inference is synchronous. Video
  processing uses OpenCV `VideoCapture`, a two-worker `ThreadPoolExecutor`, an
  in-memory job dictionary, and OpenCV `VideoWriter` using `mp4v`; the shared
  YOLO predictor is serialized with a lock. Status and output use `/job/{job_id}`
  and `/video/{job_id}`.
- Firebase Auth covers email/password and Google Sign-In. Firestore holds
  profiles and incident-related views. Deployed Firestore rules and account
  approval security are **NOT VERIFIED**.

## Backend implementation findings

The model class map is `0 book_visible`, `1 passing_note`, `2 peeking_around`,
`3 person_normal`, `4 showing_paper`, `5 using_mobile`. Source thresholds are
`book_visible=0.55`, `passing_note=0.65`, `peeking_around=0.65`,
`using_mobile=0.55`, `person_normal=0.45`. Image and video use the same
`CONF_THRESHOLDS` and compare unrounded confidence. `person_normal` is never a
violation, and its mapped 0.45 does not filter video raw candidates (model floor
0.40; anchor sampling floor 0.35). `showing_paper` is explicitly in `SKIP_CLASSES`: video processing
skips it; image output may list it as a neutral raw detection, never as a
violation.

The original video banner was drawn for every non-normal person class before
confidence/streak checks. Its single `_last` dictionary also served as a
last-detection and last-log clock, so gaps reset a three-frame streak each
frame. The backend now uses `ViolationStreakTracker` with separate `last_seen`
and `last_logged`, resets below threshold and after a gap above 30 frames,
requires `MIN_STREAK=3`, and applies `COOLDOWN_FRAMES=45`. Person streaks key by
seat track ID and class; untracked object detections key by class and 100-pixel
center grid. Neutral boxes may show raw detections; only accepted logged event
frames receive red boxes/banners, risk increments and event records. Image
analysis uses confidence thresholds only, without a temporal filter.

`get_anchors` samples up to 60 frames and now aligns seat ordering against the
first valid sample with Hungarian assignment before averaging. `SeatTracker`
uses Hungarian matching with a 150-pixel center-distance gate. It handles zero
anchors and zero detections, returns only currently matched boxes (no stale box
reuse), and maps each returned detection by index. IDs are fixed seat slots,
not identities. The strict matching gate is below 150 pixels. A person outside
the gate or no anchors can yield an unassigned event; person-specific risk is
then unavailable. Hungarian matching prevents duplicate seat assignment within
one frame, but crossings/occlusions can still swap seat labels.
Anchors never expire: if someone leaves and another person later occupies a
nearby anchor, the seat slot and its accumulated risk count are reused. There
is no lost-track timeout or re-identification.

`RiskTracker` counts accepted events: LOW below 3, MEDIUM 3–5, HIGH at 6+.
`risk_pct=min(event_count*10,100)` is a count heuristic, not a probability.
`last_seen` is the last event timestamp. Per-event `risk_level` is HIGH above
0.75 confidence and MEDIUM otherwise, separate from the count-derived summary.
Cooldown prevents duplicate incident spam for a person/class or object grid;
events during cooldown do not inflate risk.

Image input is bounded to 20 MiB and invalid/empty images return 400; model or
encoding errors return 500 instead of a false HTTP 200. Video accepts the
Flutter-supported MP4/MOV/AVI/MKV suffixes, streams to a generated safe temp
path, rejects empty/oversized files, validates OpenCV capture/writer state, and
cleans input on worker success/failure. Failed output is removed and jobs become
`error`, not `completed`. Duration uses actual decoded frame count and valid FPS
(fallback 25 only for invalid FPS). Completed `mp4v` outputs remain in `/tmp`
without TTL/delete; worker restarts lose job state and the runtime is not durable.

## Flutter parity and limitations

Source-level JSON parity is verified for `/health`, `/detect/image`,
`/detect/video`, `/job/{job_id}`, and `/video/{job_id}`. Job IDs are now 32
hexadecimal characters and satisfy Flutter validation. Image keys/types match
`DetectionResult`; video completion includes the boolean and numeric summary the
poller requires, plus timeline/risk fields consumed by the screen. Video media is
`video/mp4` via `FileResponse`. Runtime range/seek behavior and actual model
results are **NOT VERIFIED**.

The API is unauthenticated, has no job ownership or rate limiting, permits
wildcard CORS for Colab/ngrok demo use, has an unbounded in-memory jobs map/queue
and retains successful output files. It is not production-secure. Uploaded input
is removed after normal worker execution but abrupt process/runtime termination
can leave temporary files until runtime cleanup.

## Flutter fixes retained from the prior audit

The exam now completes on final answer or timer expiry, calibration gates start,
video polling and player lifecycle are bounded, image/video errors are handled,
API base URL is centralized, raw remote live detections are neutral, and local
exam camera resources are released on error/disposal. The app retains its
existing visual system. Screenshots have not been fabricated.

## Security and publication

The local Git database has no commits, refs or reflog, but contains 34,143
unreachable blobs and two temporary objects. Do not copy `.git` to a public
repository. Local Firebase configuration, signing material, logs and machine
paths are ignored. The source-only candidate scan reports no heuristic findings;
the 38 retained binaries are listed in [`BINARY_ASSETS.md`](BINARY_ASSETS.md),
consist of platform icons, launch artwork and a licensed font, and contain no
identified private media. The model weights are absent and remain ignored. No
credentials or public repository/push were created.

Ultralytics is an AGPLv3-or-later dependency according to its
[PyPI project page](https://pypi.org/project/ultralytics/); review compatibility
before backend redistribution. Weight and training-data rights are separate and
unverified. During final local publication preparation, the owner selected
[AGPL-3.0](../LICENSE) for the source snapshot. The standard GNU license text was
added unchanged; third-party notices remain intact and weights remain excluded.

## Validation

Final local publication checks use a temporary copy of the publication snapshot
with the compile-only Firebase example. Private Firebase configuration and model
weights are not needed for these checks. Runtime/device checks are separate.

- `flutter pub get`: **PASS**; 71 newer package versions are outside current
  dependency constraints and were not mass-upgraded.
- `dart format --set-exit-if-changed .`: **PASS**, 65 Dart files checked,
  unchanged in the isolated validation copy.
- `flutter analyze`: **PASS**, no issues.
- `flutter test --reporter expanded`: **PASS**, 128 passed, 0 skipped, 0 failed.
- `python3 -m compileall backend`: **PASS**.
- `pytest backend/tests -q`: **PASS**, 30 passed, no warnings. Tests used an
  isolated Python 3.11.4 environment and a mocked YOLO import; private weights
  and Ultralytics/PyTorch were not installed for this test run.
- `pip check` in that test environment: **PASS** in the preceding backend audit,
  no broken requirements.
- `python3 -B tool/check_publication.py`: **PASS**, current source documentation
  links resolve.
- Publication check: **PASS**, 277 source candidates and local documentation
  links resolve. The final snapshot contains 277 files and no Git metadata.
- Publication candidate secret scan: **PASS**, 277 inspected, 239 text-scanned,
  38 binaries skipped, zero findings and zero oversized/unreadable files. Binary
  files are inventoried separately in [`BINARY_ASSETS.md`](BINARY_ASSETS.md).
- Three GitHub Actions YAML files parse successfully. Hosted GitHub Actions
  execution was not run.
- `git diff --check`: no whitespace diagnostics; this repository has no HEAD,
  so Git cannot report a tracked-file diff.
- Android `:app:assembleDebug` passed in the preceding audit. It was not rerun
  because Android files did not change during final publication preparation. iOS device
  builds and physical camera/media playback are **NOT VERIFIED**.

Backend tests cover health, unknown/not-ready/completed-missing video jobs,
image decode/response/error behavior, exact thresholds, showing_paper exclusion,
three-frame streak, low-confidence and gap resets, cooldown boundary, per-person
state, Hungarian anchor ordering, seat matching/lost behavior, risk summary,
safe video queue filenames/input cleanup, worker failure state, red-banner/event
threshold behavior, writer failure cleanup and serialized YOLO calls. Tests
mock inference and do not measure detector accuracy. Actual Colab/weights/Firebase integration, output
codec/range behavior and deployed response parity remain **NOT VERIFIED**.

## Screenshots to supply

Place genuine sanitized captures in `docs/screenshots/`: `01_login.png`,
`02_workspace.png`, `03_exam_rules.png`, `04_exam_monitoring.png`,
`05_image_analysis.png`, `06_video_analysis.png`, `07_video_processing.png`,
`08_video_result.png`. Use a demo account and remove personal profiles, emails,
incidents and tokens.

Recommended repository name: `ai-guard-exam-monitoring`. See
[`PUBLIC_REPOSITORY_AUDIT.md`](PUBLIC_REPOSITORY_AUDIT.md) for snapshot and
fresh-repository commands. The development `.git` must remain private.
