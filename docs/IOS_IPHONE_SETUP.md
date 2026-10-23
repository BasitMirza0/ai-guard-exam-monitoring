> Historical review/setup notes. Source line numbers and earlier findings may be stale. See [the current audit](AUDIT_REPORT.md) for this preparation pass.

# AI Guard on iPhone 14 Pro Max

Audit and preparation: 9 October 2026. The Flutter code is prepared for iOS,
but a native iOS build and a real-device run have **not** been completed.

## What was inspected

The active app starts in `lib/main.dart`, initializes Firebase through
`DefaultFirebaseOptions.currentPlatform`, and uses `lib/services/ai_handler.dart`
for exam monitoring. `lib/services/ai_handler 2.dart` is an unimported duplicate;
it was left untouched. Live/image/video analysis screens use the external HTTPS
API in `lib/services/api_service.dart`. The Python environment and YOLO model
files in the repository are not Flutter native dependencies or bundled iOS models.

Versions come from the actual lockfile and installed package source, rather than
just the ranges in pubspec.yaml:

| Dependency | Installed/locked version | iOS integration |
| --- | --- | --- |
| Flutter / Dart | 3.29.2 / 3.7.2 | Installed at `<flutter-sdk>` |
| camera | 0.11.2+1 | camera_avfoundation 0.9.21+2; AVFoundation |
| camera Android backend | camera_android_camerax 0.6.19+1 | Android implementation retained |
| firebase_core | 3.15.2 | Firebase/CoreOnly, SDK 11.15.0 |
| firebase_auth | 5.7.0 | Firebase/Auth, SDK 11.15.0 |
| cloud_firestore | 5.6.12 | Firebase/Firestore, SDK 11.15.0 |
| google_sign_in | 6.3.0 | google_sign_in_ios 5.9.0; GoogleSignIn ~8.0, AppAuth, GTMSessionFetcher |
| google_mlkit_commons | 0.7.1 | Native MLKitVision bridge |
| google_mlkit_face_detection | 0.11.0 | Local original plugin with iOS pod requirements patched |
| google_mlkit_image_labeling | 0.12.0 | Local original plugin with iOS pod requirements patched |
| google_mlkit_object_detection | 0.12.1 | Local original plugin with iOS pod requirements patched |
| google_mlkit_face_mesh_detection | 0.1.1 | Android implementation; iOS inference is a stub |
| image_picker | 1.2.1 | image_picker_ios 0.8.13; photo/video selection and camera |
| video_player | 2.10.1 | video_player_avfoundation 2.8.4; AVPlayer |
| path_provider | 2.1.5 | path_provider_foundation 2.4.2 |
| image | 4.8.0 | Dart JPEG encoding; no native model runtime |

Other HTTP, UI, font and utility dependencies remain locked. No broad package
upgrade was performed. There is no tflite_flutter interpreter integration in
the active app.

## Feature support and limitations

| Feature used by this app | iOS status |
| --- | --- |
| Face count, bounding boxes, tracking, landmarks | ML Kit Face Detection supports iOS |
| Head yaw/pitch/roll; eye-open probabilities | Supported outputs used by existing monitoring heuristics; calibrate and verify on the physical phone |
| Head-pose-based looking-away checks | Retained; this infers direction from head angles |
| Image labels | ML Kit Image Labeling supports iOS |
| Object boxes, tracking and coarse categories | ML Kit Object Detection supports iOS; existing device-label heuristics and fallback boxes retained |
| Face mesh | **Unavailable on iOS** in the installed plugin and ML Kit API |
| Eye-only iris gaze | **Unavailable on iOS**; also not established on Android with this plugin |
| Live/image/video server analysis | Runs through the external API; needs an available server and internet |
| Firebase email/password and Firestore | iOS dependencies and local configuration exist; service settings/rules still require a real sign-in test |
| Google authentication | Requires the real iOS OAuth client ID and callback scheme; current Firebase plist lacks them |

Google's [face mesh documentation](https://developers.google.com/ml-kit/vision/face-mesh-detection)
provides an Android API and 468 points. The installed face-mesh plugin's iOS
`handleDetection` returns `FlutterMethodNotImplemented`. The app now only creates
and invokes that detector on Android, and discloses the missing feature in the
iPhone exam instructions. The dependency and Android implementation remain.

The existing iris code requires 478 points, including iris-center indices 468 and
473. The installed ML Kit mesh supplies 468 points numbered 0–467. Its guard
therefore reports iris data unavailable; head pose continues independently.
The app does not currently integrate MediaPipe refined iris landmarks. Equivalent
eye-only tracking needs a separate cross-platform landmark implementation and
validation; it cannot be enabled by a permission or Podfile setting.

See the official iOS guides for [face detection](https://developers.google.com/ml-kit/vision/face-detection/ios),
[image labeling](https://developers.google.com/ml-kit/vision/image-labeling/ios), and
[object detection](https://developers.google.com/ml-kit/vision/object-detection/ios).
Native API support does not prove the app's proctoring accuracy. Phone/book/laptop
classification uses heuristics; some displayed boxes are inferred fallback boxes.

## Changes and Android preservation

- Added `ios/Podfile`, CocoaPods xcconfig includes, automatic signing mode and
  consistent iOS 15.5 deployment targets in Runner and AppFrameworkInfo.plist.
  armv7/i386 are excluded; the iPhone uses arm64. No development team was invented.
- Added camera and photo library usage descriptions. Added microphone description
  for video capture permission requirements; both streamed cameras still have
  `enableAudio: false`. No library-write permission is needed because the app
  does not save images into Photos. Local-network description supports Flutter
  debugging. The existing backend is HTTPS; no broad ATS exemption was added.
- Both iOS streams explicitly request single-plane BGRA8888. The ML Kit path
  retains actual dimensions and native row stride. The installed AVFoundation
  backend already rotates capture buffers with device orientation, and the
  installed ML Kit iOS byte bridge ignores rotation metadata. Extra sensor
  rotation and width/height swapping are therefore avoided on iOS.
- Live server frames now encode BGRA with padded rows and correct color order.
  Android keeps its YUV-to-JPEG conversion and sensor rotation.
- Android exam frames keep NV21 and the existing YUV packing with chroma strides.
  A single-plane NV21 frame is now correctly labeled NV21, instead of being
  mislabeled BGRA based solely on plane count.
- iPhone instructions disclose unavailable face mesh/eye-only gaze. Saved exam
  results also record `faceMeshSupported` and `irisAvailable`.
- Missing iOS Google OAuth setup produces a visible configuration message before
  calling the native sign-in SDK. Email/password is still available.

Three small plugin copies in `third_party/` preserve the installed Dart, Android
and Objective-C implementation files byte for byte, including Android Gradle
dependencies. Their iOS podspecs alone move to GoogleMLKit 7.0.x and iOS 15.5.
Licenses and patch notes are included. Package versions stay 0.11.0, 0.12.0 and
0.12.1. Keep these directories alongside pubspec.yaml and pubspec.lock.

This fixes two inspected native dependency conflicts: GoogleMLKit 5.x versus
6.x root-pod requirements, and MLKitCommon 11's GoogleUtilities <8 versus
Firebase 11/GoogleSignIn 8's GoogleUtilities 8 requirements. The
[ML Kit September 2024 release](https://developers.google.com/ml-kit/release-notes)
uses GoogleMLKit 7, MLKitCommon 12, GoogleUtilities 8, and a minimum iOS 15.5.
The Objective-C bridges match the corresponding newer upstream plugin bridges.
CocoaPods has not resolved the final native dependency graph on this Mac yet.

The resulting application minimum is **iOS 15.5**. The original project claimed
iOS 12, while Firebase 11 needs iOS 13. The iOS native update needs 15.5.
ML Kit 7 needs Xcode 15.3+, but installed Firebase SDK 11.15.0 needs
**Xcode 16.2+**, per [Firebase release notes](https://firebase.google.com/support/release-notes/ios).
Use Xcode that also supports the phone's actual installed iOS version.

## Firebase and signing audit

`ios/Runner/GoogleService-Info.plist` is included in Runner's Resources build phase.
Its project, app ID, sender ID, API key, storage bucket and bundle ID match the iOS
entry in `lib/firebase_options.dart`. The bundle ID is `com.example.aicheat` and
the Firebase project is `aicheatdetection`. Android configuration was retained.
Firebase initializes using the correct platform options. Server-side provider
settings and Firestore access rules were not accessed or changed.

The plist has neither `CLIENT_ID` nor `REVERSED_CLIENT_ID`, and Info.plist has no
Google callback scheme. `IS_SIGNIN_ENABLED` alone does not configure Google OAuth.
No real OAuth credentials can be derived safely from the Firebase app ID.

Runner now uses automatic signing, but has **no DEVELOPMENT_TEAM**. A development
team, Apple certificate and device provisioning profile must be selected in
Xcode using your Apple account. An unsigned build cannot be installed on iPhone.

## Exact Mac preparation steps

1. Install full **Xcode 16.2 or newer**, with support for the iPhone's installed
   iOS, from the App Store or Apple's developer downloads. Command Line Tools
   alone do not include the iOS SDK. Open Xcode once and complete first launch.
2. Run in Terminal, accepting licenses after reviewing them:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   sudo xcodebuild -license
   xcodebuild -version
   ```

3. In Xcode Settings > Components (or Platforms), install iOS platform support
   if Xcode requests it. Newer Xcode versions also offer
   `xcodebuild -downloadPlatform iOS`.
4. Homebrew is already installed here. Install CocoaPods and verify:

   ```sh
   brew install cocoapods
   pod --version
   ```

   See the [Homebrew formula](https://formulae.brew.sh/formula/cocoapods) and
   [CocoaPods installation guide](https://guides.cocoapods.org/using/getting-started.html).
5. Resolve packages and native pods using the existing lockfile:

   ```sh
   cd <project-root>
   flutter doctor -v
   flutter pub get
   cd ios
   pod install --repo-update
   cd ..
   flutter build ios --debug --no-codesign
   ```

   Keep the generated `ios/Podfile.lock` once resolution succeeds. The unsigned
   build checks native compilation; signing is configured next. If Xcode cannot
   support your phone's iOS, use a compatible Xcode/macOS combination. Flutter
   3.29.2 is old; if that Xcode/iOS combination requires a newer Flutter, use a
   separate Flutter SDK for iOS and recheck both platforms before replacing your
   working Android SDK. Do not run a broad pub upgrade to fix CocoaPods conflicts.

## Exact Xcode and iPhone steps

1. Connect the iPhone 14 Pro Max to the Mac by USB, unlock it, and tap **Trust**
   when prompted. In Xcode, Window > Devices and Simulators, select the iPhone
   and let device preparation finish.
2. On the phone, Settings > Privacy & Security > Developer Mode > On; restart
   and confirm. If the option is absent, pair with Xcode first.
3. In Xcode Settings > Accounts, add your Apple ID. A Personal Team can be used
   for development on your own phone; paid membership is used for distribution.
4. Open **`<project-root>/ios/Runner.xcworkspace`** with Xcode
   after pod installation. Opening just Runner.xcodeproj omits the Pods project.
5. Select Runner in the project navigator, then TARGETS > Runner > Signing &
   Capabilities. Turn on **Automatically manage signing**, select your Team,
   and confirm Bundle Identifier **`com.example.aicheat`**. Apply the team to
   RunnerTests if running native tests. Check General > Minimum Deployments is
   iOS 15.5. Leave arm64 enabled.
6. If your team cannot provision `com.example.aicheat`, choose a bundle ID you
   control, such as `com.yourname.aiguard`, **and** register a new iOS app with
   that exact ID in Firebase project `aicheatdetection`. Replace the iOS plist,
   and update only `DefaultFirebaseOptions.ios` using the new app's values
   (including appId, apiKey and iosBundleId). Do not merely change Xcode while
   leaving the old Firebase iOS registration. Preserve the Android options.
7. Select scheme **Runner**, destination **your iPhone 14 Pro Max**, and Product
   > Run (Cmd-R). Let Xcode create/download the development profile. If the
   phone reports an untrusted developer, go to Settings > General > VPN & Device
   Management and trust your development certificate if offered.
8. Allow camera access when using monitoring/capture, Photos access when choosing
   media, and local-network access for Flutter debugging. If previously denied,
   enable the relevant permission under Settings > Apps > AI Guard.

These device requirements follow the [Flutter physical-device setup](https://docs.flutter.dev/platform-integration/ios/setup).

## Exact Android Studio steps

1. Open Android Studio > Open and select **`<project-root>`**,
   the Flutter project root containing pubspec.yaml. Use the Flutter and Dart
   plugins (Settings > Plugins). Do not open only the `android` directory.
2. Settings > Languages & Frameworks > Flutter: set the SDK path to
   **`<flutter-sdk>`**, or your separately chosen
   compatible iOS SDK. Set the Dart SDK to that Flutter SDK's
   `bin/cache/dart-sdk` if it is not detected automatically.
3. Run `flutter pub get` in Android Studio's Terminal. Complete Xcode signing
   above once; Android Studio depends on Xcode for iOS compilation and signing.
4. Keep the unlocked, trusted iPhone connected. Run `flutter devices` in the
   Terminal; the phone should appear with an iOS device ID. If absent, inspect
   Xcode Devices and Simulators and `flutter doctor -v`.
5. In the toolbar choose the Flutter run configuration targeting **lib/main.dart**
   (Run > Edit Configurations > + > Flutter if missing). Select **iPhone 14 Pro
   Max** from the device selector and press Run or Debug.
6. The equivalent command from the project root is:

   ```sh
   flutter run -d <iphone-device-id>
   ```

   Substitute the actual ID printed by `flutter devices`. Hot reload works while
   the debug session is connected. If local-network permission was denied,
   enable it on the phone as explained in [Flutter's debugging guide](https://docs.flutter.dev/platform-integration/ios/ios-debugging).

## Enable Google sign-in when needed

1. Firebase console > `aicheatdetection` > Authentication > Sign-in method >
   Google: enable it and select the support email.
2. Project Settings > Your apps > the iOS app with your exact Runner bundle ID:
   download a fresh `GoogleService-Info.plist` and replace
   `ios/Runner/GoogleService-Info.plist`. Confirm it contains `CLIENT_ID` and
   `REVERSED_CLIENT_ID`. If absent, configure the matching iOS OAuth client in
   the project's Google Cloud credentials before downloading again.
3. From the project root, for the current `com.example.aicheat` registration:

   ```sh
   python3 tool/configure_ios_google_sign_in.py
   ```

   This copies real `CLIENT_ID` into Info.plist's `GIDClientID` and adds the real
   `REVERSED_CLIENT_ID` callback scheme. It refuses missing or mismatched values.
   If you changed the bundle ID, adapt the script's expected ID only after all
   Firebase/Xcode iOS identifiers match, or enter those two Info.plist values
   manually following the [installed sign-in plugin's guide](https://pub.dev/packages/google_sign_in_ios/versions/5.9.0).
4. Rebuild and reinstall. An Info.plist or native change needs a rebuild, not
   hot reload. Ensure the Firebase provider is enabled before testing login.

## Verification and remaining errors

- `flutter pub get --offline`: succeeds with the installed cache and local patches.
- `flutter test --reporter expanded`: **85 tests passed**, including six new
  iOS/platform tests for BGRA stride/color/size, NV21 metadata, Android YUV packing,
  JPEG rotation, mesh suppression and the visible iPhone limitation notice.
- Android, Dart and Objective-C source equality against the original three
  plugin packages: verified byte for byte.
- Podfile Ruby syntax and Xcode/Info plists: valid.
- `flutter analyze`: no compile errors in changed code. The remaining 11
  diagnostics (3 warnings, 8 informational lints) are in the pre-existing,
  unimported `lib/services/ai_handler 2.dart`. Full-project analysis exits 1.
- `flutter build ios --debug --no-codesign`: exits 1 before native compilation
  with **`Application not configured for iOS`**. The iOS project is present;
  Flutter cannot resolve its build-variable bundle ID through Xcode because
  full Xcode is absent. `xcodebuild -version` reports that the active developer
  directory `/Library/Developer/CommandLineTools` is a Command Line Tools instance.
- `flutter doctor -v`: full Xcode missing, CocoaPods missing; no iPhone detected.
  The device list contains only macOS and Chrome. Some Android SDK licenses are
  also pending; those were not changed as part of iOS preparation.

There is no produced .app/IPA, Podfile.lock, verified Apple signing certificate,
provisioning profile, native dependency resolution, or real iPhone inference
result. Native compiler/linker errors cannot be assessed until Xcode and
CocoaPods are installed. No Android native build was performed; regression
tests pass and native Android implementations/dependency versions were preserved.

After installing on the phone, test email login/Firestore access; front and rear
live cameras; portrait and both landscape orientations; head direction and
eye-closure calibration; photo/video selection; permission denial and retry;
background/resume and camera switching; object overlays; and Google login after
OAuth setup. Verify head-direction labels and boxes against the actual mirrored
front-camera preview, since native camera behavior has only been inspected,
not tested on this iPhone. The external ngrok API's availability and its video
codec/HEIC handling were not verified. iPhone media processing depends on that
server; local ML Kit exam inference does not depend on it.
