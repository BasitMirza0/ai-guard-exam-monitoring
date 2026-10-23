# Exam phone detection

The exam's phone recognition runs locally in `lib/services/ai_handler.dart`.
Head movement is handled by a separate face detector, so working head tracking
does not establish that the image labeler is recognizing the phone. The exam
does not use the external YOLO API used by the Live Detection screen.

## Reproduced failures and fixes

Four regression cases failed before the fix and passed afterward:

1. A `Mobile phone` confidence of 0.95 combined with `Room` and `Desk` labels
   was multiplied by 0.60 and 0.70, producing 0.399. That fell below the 0.55
   phone threshold despite strong direct phone evidence. Context penalties
   no longer reduce the phone score.
2. A phone could be discarded when a different object scored higher. Image
   labels can describe multiple objects in the same frame; direct phone
   evidence now takes priority once it crosses the existing threshold.
3. The old head calibration branch returned before image labeling. Phone
   recognition now runs during calibration, publishes results, and is checked
   before the screen's head-calibration guard. This starts only after Begin Exam;
   the instructions screen still does not stream inference frames.
4. An exception from object localization discarded the entire frame result.
   Confirmed label evidence now survives localization failure, using the existing
   estimated-box fallback. Such a box is not proof of the phone's actual location.

Phone confirmation still requires a score of at least 0.55 on two consecutive
processed frames. Weak labels and an isolated positive frame do not confirm it.
The existing exam policy terminates on the first confirmed phone result.
This is an image classifier score, not a measured probability of cheating.

## Test on the actual device

Stop the old debug session, then run from the project root:

```sh
flutter devices
flutter run -d <device-id> --dart-define=TRACE_DETECTION=true
```

Replace `<device-id>` with the phone running the exam. In Android Studio, the
same define can be added under Run > Edit Configurations > Flutter configuration
> Additional run args. Restart the app after changing this compile-time define.

Begin an exam, let calibration complete, and show a second phone clearly within
the exam camera's field of view. The phone running the exam cannot see itself.
Repeat with the second phone's screen and back facing the camera, and inspect
the Run console for `[PhoneDetection]` lines. No image data is written by these
diagnostics; they print labels, scores and counters in debug builds.

Example output (illustrative, not a captured device result):

```text
[PhoneDetection] phone=0.91 threshold=0.55 candidate=Phone consecutive=2 calibrated=true labels=[mobile phone:0.91, room:0.83]
```

- `phone=0.00`: none of the recognized phone labels was returned by the labeler
  above its 0.30 output threshold. The image model may be missing the phone.
- Phone score below `0.55`: the label is too weak to confirm under the existing
  rule. Do not assume lowering the threshold is an accuracy fix.
- `candidate=Phone consecutive=1`: one qualifying frame; a second consecutive
  qualifying frame is required.
- `candidate=Phone consecutive=2` or more: confirmed and published to the exam.
- `Image labeling failed`: native label inference raised an error; the stability
  counter resets. `Object localization failed` does not discard confirmed labels.

The tests mock native ML Kit results. They validate processing and enforcement
inputs, not recognition accuracy on camera images. No real-device phone
recognition result was captured during this fix.

## Model limitation

Google's default [image label map](https://developers.google.com/ml-kit/vision/image-labeling/label-map)
includes `Mobile phone` (index 257). The default
[object detector](https://developers.google.com/ml-kit/vision/object-detection)
only classifies broad categories such as home goods and fashion goods. It does
not independently recognize a cell-phone class or establish who is holding it.
If the native labeler still misses the phone, a dedicated phone object-detection
model and representative device images are needed to improve and measure recall.
The fixes here remove demonstrated logic failures without claiming universal
phone recognition or validated holding/ownership detection.
