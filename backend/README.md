# FastAPI + YOLO backend

[`main.py`](main.py) is the actual FastAPI implementation used by the working
Colab deployment. It loads `/content/best_model_merged.pt` at import time. The
weights are intentionally external and are not needed for mock-based unit tests.

## Local/Colab setup

Use Python 3.10+ in a clean environment, install
[`requirements.txt`](requirements.txt), copy the private model to the expected
path, then run from this directory:

```sh
python -m pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

The Colab flow is documented in [`../colab/README.md`](../colab/README.md).
`pyngrok` is notebook/tunnel startup tooling and is intentionally absent from
the backend runtime requirements. Store its token in Colab Secrets as
`NGROK_AUTHTOKEN`.

## Actual service behavior

- `GET /health` returns `status: ok` and the configured model filename after
  import-time weight loading succeeds.
- `POST /detect/image` decodes one image, returns raw detections separately from
  threshold-accepted violations, and emits a base64 JPEG annotation.
- `POST /detect/video` accepts MP4/MOV/AVI/MKV uploads up to 250 MiB and queues
  work in a two-thread in-memory executor.
- `GET /job/{job_id}` returns queued/processing/completed/error state and hides
  its internal output path.
- `GET /video/{job_id}` streams a completed annotated MP4 response.

See [`../docs/API.md`](../docs/API.md) for the response fields, thresholds,
streak/cooldown, tracking, retention and Flutter parity details.

## Tests

Tests mock the Ultralytics model and do not load weights. Create a test
environment and run:

```sh
python -m pip install -r requirements-test.txt
python -m pytest tests -q
```

The test requirements include FastAPI/OpenCV/SciPy for the service and tracker
tests but deliberately exclude Ultralytics/PyTorch. `requirements.txt` contains
the full runtime dependencies. Dependency ranges are compatibility bounds, not
a lockfile or proof of the versions installed in the current Colab session.

## Demo-only security and operations

CORS is wildcard for the current Colab/ngrok demo. The service has no API auth,
job ownership, rate limiting, persistent job store, bounded queue or automatic
successful-output deletion. Process/runtime restart loses all job state; outputs
remain under `/tmp` until runtime cleanup. Do not use this as a production
service or send private exam data. Successful MP4 output uses the existing
OpenCV `mp4v` codec; validate playback/seeking on target devices.

The shared YOLO predictor is protected by a lock because its internal prediction
state is mutable and should not be called concurrently from multiple threads.
Video jobs can overlap during non-inference work, but model inference is
serialized. See the [Ultralytics threading guide](https://github.com/ultralytics/ultralytics/blob/main/docs/en/guides/yolo-thread-safe-inference.md).

The Ultralytics dependency is published as AGPLv3-or-later. Review its terms and
the model-weight terms before redistribution. No weights, tokens or service
credentials belong in this directory.
