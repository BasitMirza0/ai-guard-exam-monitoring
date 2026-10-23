# API contract and implementation

This describes the inspected [`backend/main.py`](../backend/main.py) and the
Flutter client. Their JSON shapes match at source level. The Colab runtime,
private weights and playback on physical devices have not been exercised here.

## Configuration and transport

`ApiConfig.baseUrl` reads `--dart-define=API_BASE_URL=...`. Flutter validates
scheme/host and job IDs, and constructs every endpoint from that base URL. Each
analysis screen owns an `ApiService`, closes its HTTP clients on disposal, and
does not send Firebase identity tokens. Thus Firebase sign-in does not protect
the backend API.

| Operation | Flutter bound |
| --- | --- |
| Health | 15 seconds |
| Image | 60 seconds; 20 MiB maximum |
| Video upload | 3 minutes; 250 MiB maximum |
| Job status | 10 seconds per request |
| Polling | 5-second interval, 30-minute total deadline, up to 5 consecutive transient retries |
| JSON response | 40 MiB |
| Player initialization | 30 seconds |

Video uploads are not retried automatically because a timeout may happen after a
job was created. Client disposal stops its own polling but does not cancel server
processing. No API delete/cancel endpoint exists.

## Endpoints

### `GET /health`

Returns `{"status":"ok","model":"best_model_merged.pt"}`. The model is loaded
from `/content/best_model_merged.pt` when the module imports, so a successful
health response means import and weight loading already completed. It does not
measure inference accuracy.

### `POST /detect/image`

Multipart field `file`. The backend reads at most 20 MiB + 1 byte, rejects empty
or undecodable input with 400 and oversize input with 413, then runs YOLO with
base confidence 0.45. It returns:

```json
{
  "violations_found": true,
  "total_detections": 2,
  "total_violations": 1,
  "inference_time_ms": 42.0,
  "violations": [{"violation": "peeking_around", "confidence": 0.65}],
  "detections": [
    {"class_id": 2, "class_name": "peeking_around", "confidence": 0.6},
    {"class_id": 2, "class_name": "peeking_around", "confidence": 0.65}
  ],
  "annotated_image": "<base64 JPEG>"
}
```

The example is illustrative. `detections` are raw model outputs. `violations`
contains only classes in `VIOLATIONS` meeting their threshold. Raw boxes are gray;
accepted violations are red. Image analysis has no temporal streak/cooldown.
`showing_paper` may be in raw image detections but is never an accepted violation.
Model/inference/encoding errors return HTTP 500 with a generic detail; internals
are logged server-side.

### `POST /detect/video`

Multipart field `file`; accepted filename suffixes are `.mp4`, `.mov`, `.avi`, and
`.mkv`, matching Flutter. The backend streams into a generated `/tmp` filename,
rejects empty uploads with 400 and files above 250 MiB with 413, and returns:

```json
{"status": "queued", "job_id": "<32 lowercase hex characters>"}
```

The supplied filename is not used as a filesystem path. Upload media type is not
trusted; OpenCV must be able to open and decode the actual content.

### `GET /job/{job_id}`

States are `queued`, `processing`, `completed`, or `error`. Unknown IDs return
404. `output_video_path` is omitted from public status responses. Processing
messages include frame progress every 100 frames. A successful terminal response
contains:

```json
{
  "status": "completed",
  "progress": 100,
  "video_duration_seconds": 3.2,
  "total_frames": 96,
  "total_violations": 1,
  "violations_found": true,
  "unique_violations": ["peeking_around"],
  "all_violations": [
    {"violation": "peeking_around", "confidence": 0.7,
     "timestamp": 1.0, "track_id": 1, "risk_level": "MEDIUM"}
  ],
  "person_risk_summary": [
    {"track_id": "S1", "risk_level": "LOW", "risk_pct": 10,
     "last_seen": 1.0}
  ]
}
```

An error response has `{"status":"error","message":"Video processing failed"}`.
Flutter requires a boolean `violations_found` and numeric `total_violations` on
completion and defensively handles malformed optional lists. Its timeline accepts
numeric or null track IDs and displays timestamps/confidence from this schema.

The temporal filter uses confidence-qualified observations, resets a class/person
streak on a below-threshold observation or a gap above 30 frames, requires three
observations, then logs at most once per 45 frames for each person/class (or
class/grid for untracked objects). It draws the strong red banner on the event
frame only. Raw detections can still be shown in neutral gray.

An event's `risk_level` is `HIGH` when its confidence is greater than 0.75 and
`MEDIUM` otherwise. The separate person summary derives `risk_level` from the
number of accepted events. `risk_pct` is a capped count heuristic, not a
probability, and `last_seen` is the most recent event timestamp.

### `GET /video/{job_id}`

Unknown jobs return 404; non-completed jobs return 400; missing output files
return 404. Completed output is a `FileResponse` with `video/mp4` and a generated
download filename. OpenCV writes `mp4v` MP4, preserving the existing codec.
Device codec, range/seek support and real Colab playback remain **NOT VERIFIED**.

## State, retention and deployment limits

The job dictionary is in process memory and the thread pool has two workers.
The shared YOLO predictor is protected by a lock, so inference calls are
serialized even when jobs are queued concurrently.
Runtime/process restart loses all job status. Successful annotated videos remain
under `/tmp/output_<job_id>.mp4` until manual/runtime cleanup; there is no TTL or
delete endpoint. Uploaded input is deleted after processing on success or failure.
Failed output is deleted. A worker crash or abrupt runtime stop can leave files
until Colab cleanup.

CORS permits every origin for the current Colab/ngrok demo. CORS is not access
control. The service has no authentication, authorization, rate limit, job
ownership check, durable queue or distributed storage. Do not expose sensitive
exam media or treat this setup as production hosting.
