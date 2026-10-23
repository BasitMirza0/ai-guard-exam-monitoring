# Model classes, thresholds and limits

## Model and class map

The actual backend loads `best_model_merged.pt` using Ultralytics YOLO at startup.
The weights are kept in Google Drive and copied by the Colab deployment to
`/content/best_model_merged.pt`; they are not present in this repository. Their
size, architecture, provenance, dataset rights, evaluation metrics and
distribution license remain **NOT VERIFIED**.

| ID | Model class | Confidence threshold | Violation behavior |
| --- | --- | ---: | --- |
| 0 | `book_visible` | 0.55 | Violation candidate |
| 1 | `passing_note` | 0.65 | Violation candidate |
| 2 | `peeking_around` | 0.65 | Violation candidate |
| 3 | `person_normal` | 0.45 | Person/seat candidate; never itself a violation |
| 4 | `showing_paper` | n/a | In `SKIP_CLASSES`; excluded from video processing and violations. It may remain a neutral raw image detection. |
| 5 | `using_mobile` | 0.55 | Violation candidate |

`CONF_THRESHOLDS` is the backend's single threshold mapping used by image and
video violation acceptance. Comparisons use unrounded YOLO confidence.
`person_normal` has a configured 0.45 value but is absent from `VIOLATIONS`, so
that value does not create an accepted incident. Raw normal-person candidates
use the endpoint model-level confidence (0.45 for image, 0.40 for video, 0.35
while sampling anchors). Unknown class threshold lookup defaults to 0.55;
unknown classes are not violations.

Image analysis requires only the threshold. Video analysis also needs three
confidence-qualified observations, with a maximum 30-frame gap, followed by a
45-frame per-person/class cooldown (or per-class/grid for object detections).
Person streaks are keyed by seat track ID; non-person object streaks are keyed
by a 100-pixel center grid. Below-threshold observations reset their streak.
Strong red video banners and incident records are created on accepted event
frames only. Other raw boxes are gray.

The video tracker associates people to fixed seat anchors derived from the first
60 frames. SciPy Hungarian assignment uses a 150-pixel maximum center distance.
These `S1`, `S2`, ... labels represent approximate seat slots, not verified
student identities. People outside the matching gate are unassigned and receive
no person-risk summary; their qualifying violation can still be logged with a
null `track_id`.
Anchors do not expire, so a person entering a previously used seat can inherit
that seat slot and its accumulated risk summary. The tracker does not perform
identity recognition or re-identification.

## Risk interpretation

`RiskTracker` counts accepted incident events associated with a seat: LOW below
3, MEDIUM at 3–5, HIGH at 6+. `risk_pct` is `min(event_count * 10, 100)` and
`last_seen` is the last incident timestamp. This count-derived display score is
not a calibrated probability, model confidence or scientific measure of
cheating. Object-only events have no person seat attribution.

Per-event `all_violations[].risk_level` is separate: it is HIGH when the event
confidence exceeds 0.75 and MEDIUM otherwise. It does not represent the
person's accumulated risk summary.

## Rendering and model limitations

Image and video outputs distinguish neutral raw detections from accepted
violations. Image output has no streak rule. Video raw boxes use a neutral gray;
red violation styling is drawn only after threshold, streak and cooldown checks
allow a new event. `showing_paper` is not promoted to a violation.

Model confidence is not proof of misconduct. Occlusion, lighting, viewpoint,
camera quality, training data and class overlap can produce false positives and
false negatives. There is no verified held-out evaluation, precision, recall,
mAP or subgroup analysis. Human review remains necessary; detections must not be
the sole basis for academic disciplinary action.

The local exam's ML Kit face/pose/label heuristics are a separate on-device path.
Its attention score is a hand-written penalty score and is not this remote YOLO
risk tracker. The Ultralytics package is distributed under AGPLv3 or later on
PyPI; review license compatibility and the actual weights' terms before
redistributing the backend or model. [Ultralytics on PyPI](https://pypi.org/project/ultralytics/).
