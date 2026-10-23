> Historical review/setup notes. Source line numbers and earlier findings may be stale. See [the current audit](AUDIT_REPORT.md) for this preparation pass.

# UI and performance review

## Changes

- The startup cover remains visible until initialization and the destination's first frame are ready, then fades out over 240 ms. Reduced-motion settings skip both launch animations. Native Android launch backgrounds already use the same ivory and green palette, including night-mode resources.
- Pre-exam rules replace the camera-check preview. The instructions have no scroll view; the Begin Exam action stays outside the fitted rules area. Short landscape displays use two columns. Camera initialization runs while the user reads; Begin switches directly into the existing exam once the camera is ready. Permission and initialization failures retain a retry action without restoring the camera-check section.
- The exam countdown uses elapsed time rather than counting timer callbacks. Only the header rebuilds for timer ticks. AI diagnostic logging is excluded from profile/release builds. Decorative warning animations stop while the app or route is inactive.
- Live detection now reports missing cameras and initialization failures with a retry action instead of leaving an indefinite loader.
- Account setup guards its asynchronous failure update after disposal.

## App-wide inspection

Authentication, account status, student/teacher/admin workspaces, image and video analysis, live detection, navigation, shared layout widgets, Android launch resources, and the inference and camera lifecycle services were reviewed. Existing adaptive controls, bounded reading widths, lazy lists, local fonts, image decode limits, camera repaint boundaries, frame dropping, background stream suspension, and off-thread JPEG conversion remain in use. Detection thresholds and exam questions are unchanged.

## Verification

- Android release APK compiled successfully at `build/app/outputs/flutter-apk/app-release.apk` (175.7 MB, universal APK).
- 79 Flutter tests passed, including responsive authentication and workspace layouts, back navigation, startup/retry/reduced-motion behavior, camera lifecycle, inference scheduling, and detection behavior.
- New instruction tests cover 240×320, 320×568, 390×844, 844×390, and 600×960 logical pixels at device pixel ratio 2 and text scales 1 and 2. They verify no scrolling, no layout exceptions, an accessible Begin action, and camera retry behavior.
- Analysis of active screens, widgets, startup, AI service, main entry point, and tests reports no issues. Repository-wide analysis still reports 11 pre-existing findings in the unused duplicate `lib/services/ai_handler 2.dart`.

## Practical limits

A fixed, non-scrollable page cannot retain full-size text for unlimited text scaling or arbitrarily small displays. The instructions scale down only when necessary, leaving the 52-pixel primary action anchored. The tested 240×320 viewport at large text settings fits, but the rules become small.

Widget tests do not measure hardware frame times, thermal load, camera driver behavior, or memory consumption. Real-device release/profile measurements and a representative Android device matrix are still required before claiming universal smoothness or production certification. The backend URL is currently an external ngrok endpoint; availability was not established by mocked UI tests. Distribution signing and store deployment are outside this change.
