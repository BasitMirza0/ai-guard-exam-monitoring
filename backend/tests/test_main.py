import importlib
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import ModuleType, SimpleNamespace

import numpy as np
import pytest
from fastapi.testclient import TestClient


class FakeYOLO:
    def __init__(self, _model_path):
        self.predict = lambda **_kwargs: []


def load_backend(monkeypatch):
    fake_ultralytics = ModuleType("ultralytics")
    fake_ultralytics.YOLO = FakeYOLO
    monkeypatch.setitem(sys.modules, "ultralytics", fake_ultralytics)
    module_name = "ai_guard_backend_test_module"
    source = Path(__file__).resolve().parents[1] / "main.py"
    spec = importlib.util.spec_from_file_location(module_name, source)
    module = importlib.util.module_from_spec(spec)
    monkeypatch.setitem(sys.modules, module_name, module)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def backend(monkeypatch):
    module = load_backend(monkeypatch)
    module.jobs.clear()
    return module


@pytest.fixture
def client(backend):
    return TestClient(backend.app)


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "model": "best_model_merged.pt",
    }


def test_unknown_job_is_404(client):
    response = client.get("/job/missing")
    assert response.status_code == 404
    assert response.json() == {"error": "Job not found"}


def test_video_job_status_hides_internal_output_path(client, backend):
    backend.jobs["queued1"] = {
        "status": "processing",
        "progress": 35,
        "message": "Frame 1500/4303",
        "output_video_path": "/private/path.mp4",
    }
    response = client.get("/job/queued1")
    assert response.status_code == 200
    assert response.json() == {
        "status": "processing",
        "progress": 35,
        "message": "Frame 1500/4303",
    }


def test_video_not_ready_and_completed_missing_file(client, backend, tmp_path):
    backend.jobs["pending1"] = {"status": "queued"}
    assert client.get("/video/pending1").status_code == 400

    backend.jobs["complete1"] = {
        "status": "completed",
        "output_video_path": str(tmp_path / "missing.mp4"),
    }
    response = client.get("/video/complete1")
    assert response.status_code == 404
    assert response.json() == {"error": "Video not found"}


def test_completed_video_is_returned_as_mp4(client, backend, tmp_path):
    output = tmp_path / "done.mp4"
    output.write_bytes(b"mocked mp4 bytes")
    backend.jobs["complete2"] = {
        "status": "completed",
        "output_video_path": str(output),
    }
    response = client.get("/video/complete2")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("video/mp4")
    assert response.content == b"mocked mp4 bytes"


@pytest.mark.parametrize(
    ("class_name", "threshold"),
    [
        ("book_visible", 0.55),
        ("passing_note", 0.65),
        ("peeking_around", 0.65),
        ("using_mobile", 0.55),
        ("person_normal", 0.45),
    ],
)
def test_class_thresholds_are_inclusive(backend, class_name, threshold):
    assert backend.confidence_threshold(class_name) == threshold
    if class_name in backend.VIOLATIONS:
        assert backend.is_accepted_violation(class_name, threshold)
        assert not backend.is_accepted_violation(class_name, threshold - 0.001)
    else:
        assert not backend.is_accepted_violation(class_name, threshold)


def test_person_normal_and_showing_paper_are_not_violations(backend):
    assert not backend.is_accepted_violation("person_normal", 0.99)
    assert not backend.is_accepted_violation("showing_paper", 0.99)
    assert "showing_paper" in backend.SKIP_CLASSES


def test_three_qualified_observations_reach_min_streak(backend):
    streak = backend.ViolationStreakTracker(min_streak=3, cooldown_frames=45)
    assert not streak.should_log("peeking_around", 120, 120, 0, 0.65)
    assert not streak.should_log("peeking_around", 120, 120, 1, 0.70)
    assert streak.should_log("peeking_around", 120, 120, 2, 0.80)
    state = streak.state[("peeking_around", None, 1, 1)]
    assert state == {"streak": 0, "last_seen": 2, "last_logged": 2}


def test_below_threshold_or_long_gap_breaks_a_streak(backend):
    streak = backend.ViolationStreakTracker(min_streak=3, max_gap=2)
    assert not streak.should_log("peeking_around", 120, 120, 0, 0.70)
    assert not streak.should_log("peeking_around", 120, 120, 1, 0.60)
    assert not streak.should_log("peeking_around", 120, 120, 2, 0.70)
    assert not streak.should_log("peeking_around", 120, 120, 5, 0.70)
    assert not streak.should_log("peeking_around", 120, 120, 6, 0.70)
    assert streak.should_log("peeking_around", 120, 120, 7, 0.70)


def test_cooldown_uses_last_logged_and_allows_one_event_at_boundary(backend):
    streak = backend.ViolationStreakTracker(min_streak=3, cooldown_frames=5)
    assert not streak.should_log("book_visible", 120, 120, 0, 0.60)
    assert not streak.should_log("book_visible", 120, 120, 1, 0.60)
    assert streak.should_log("book_visible", 120, 120, 2, 0.60)
    assert not streak.should_log("book_visible", 120, 120, 3, 0.60)
    assert not streak.should_log("book_visible", 120, 120, 4, 0.60)
    assert not streak.should_log("book_visible", 120, 120, 5, 0.60)
    assert not streak.should_log("book_visible", 120, 120, 6, 0.60)
    assert streak.should_log("book_visible", 120, 120, 7, 0.60)


def test_streaks_for_classes_and_separate_grids_do_not_share_state(backend):
    streak = backend.ViolationStreakTracker(min_streak=2)
    assert not streak.should_log("book_visible", 120, 120, 0, 0.60)
    assert not streak.should_log("book_visible", 220, 120, 1, 0.60)
    assert not streak.should_log("passing_note", 120, 120, 1, 0.70)
    assert streak.should_log("book_visible", 120, 120, 2, 0.60)


def test_person_streaks_are_keyed_by_track_id(backend):
    streak = backend.ViolationStreakTracker(min_streak=2)
    assert not streak.should_log("peeking_around", 120, 120, 0, 0.70, track_id=1)
    assert not streak.should_log("peeking_around", 120, 120, 0, 0.70, track_id=2)
    assert streak.should_log("peeking_around", 120, 120, 1, 0.70, track_id=1)
    assert streak.should_log("peeking_around", 120, 120, 1, 0.70, track_id=2)


def test_shared_yolo_predict_calls_are_serialized(backend, monkeypatch):
    active = 0
    maximum_active = 0
    guard = threading.Lock()

    def fake_predict(**kwargs):
        nonlocal active, maximum_active
        with guard:
            active += 1
            maximum_active = max(maximum_active, active)
        time.sleep(0.02)
        with guard:
            active -= 1
        return kwargs["source"]

    monkeypatch.setattr(backend.model, "predict", fake_predict)
    sources = [object(), object()]
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(
            executor.map(
                lambda source: backend.predict_safely(source=source), sources
            )
        )
    assert results == sources
    assert maximum_active == 1


def test_seat_tracker_handles_zero_one_multiple_and_lost_detections(backend):
    assert backend.SeatTracker([]).update([(0, 0, 20, 20)]) == []

    one = backend.SeatTracker([(50, 50)])
    matched = one.update([(0, 0, 100, 100)])
    assert matched == [(0, 0, 100, 100, 1, 0)]
    assert one.update([]) == []  # A stale box is not reused as a new detection.
    assert one.update([(0, 0, 100, 100)]) == [(0, 0, 100, 100, 1, 0)]
    assert one.update([(400, 400, 500, 500)]) == []  # Distance gate.

    multiple = backend.SeatTracker([(0, 0), (200, 0)])
    matches = multiple.update(
        [(150, -10, 170, 10), (-10, -10, 10, 10)]
    )
    assert matches == [(150, -10, 170, 10, 2, 0), (-10, -10, 10, 10, 1, 1)]
    assert len({row[4] for row in matches}) == len(matches)


def test_anchor_ordering_uses_hungarian_alignment_across_frames(backend, monkeypatch):
    class AnchorBox:
        def __init__(self, x, y):
            self.cls = [3]
            self.xyxy = [SimpleNamespace(tolist=lambda: [x - 1, y - 1, x + 1, y + 1])]

    frames = iter(
        [
            [AnchorBox(100, 10), AnchorBox(0, 100)],
            [AnchorBox(100, 60), AnchorBox(0, 50)],
        ]
    )
    monkeypatch.setattr(
        backend.model,
        "predict",
        lambda **_kwargs: [SimpleNamespace(boxes=next(frames))],
    )

    class TwoFrameCapture:
        def __init__(self):
            self.frames = iter([np.zeros((2, 2, 3)), np.zeros((2, 2, 3))])

        def read(self):
            frame = next(self.frames, None)
            return (frame is not None, frame)

    assert backend.get_anchors(TwoFrameCapture(), n_frames=3) == [(100, 35), (0, 75)]


def test_risk_levels_counts_heuristic_and_last_seen(backend):
    tracker = backend.RiskTracker()
    assert tracker.risk(1)[0] == "LOW"
    for index in range(3):
        tracker.add(1, {"violation": "book_visible", "timestamp": index + 1})
    assert tracker.risk(1)[0] == "MEDIUM"
    for index in range(3, 6):
        tracker.add(1, {"violation": "using_mobile", "timestamp": index + 1})
    assert tracker.risk(1)[0] == "HIGH"
    assert tracker.summary() == [
        {"track_id": "S1", "risk_level": "HIGH", "risk_pct": 60, "last_seen": 6}
    ]


def test_invalid_image_returns_400(client):
    response = client.post(
        "/detect/image",
        files={"file": ("invalid.jpg", b"not an image", "image/jpeg")},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Uploaded file is not a valid image"


def test_image_response_separates_raw_detections_from_accepted(backend):
    image = np.zeros((12, 12, 3), dtype=np.uint8)
    ok, encoded = backend.cv2.imencode(".jpg", image)
    assert ok

    class FakeBox:
        def __init__(self, class_id, confidence):
            self.cls = [class_id]
            self.conf = [confidence]
            self.xyxy = [SimpleNamespace(tolist=lambda: [1, 1, 8, 8])]

    backend.model.predict = lambda **_kwargs: [
        SimpleNamespace(
            boxes=[
                FakeBox(2, 0.60),  # Raw only: under the accepted 0.65 cutoff.
                FakeBox(2, 0.65),  # Accepted at the inclusive threshold.
                FakeBox(4, 0.99),  # showing_paper is never a violation.
            ]
        )
    ]
    response = TestClient(backend.app).post(
        "/detect/image",
        files={"file": ("sample.jpg", encoded.tobytes(), "image/jpeg")},
    )
    assert response.status_code == 200
    result = response.json()
    assert result["total_detections"] == 3
    assert result["total_violations"] == 1
    assert result["violations_found"] is True
    assert result["violations"] == [
        {"violation": "peeking_around", "confidence": 0.65}
    ]
    assert [item["confidence"] for item in result["detections"]] == [0.6, 0.65, 0.99]
    assert backend.base64.b64decode(result["annotated_image"])


def test_yolo_failure_returns_server_error_not_success(backend):
    backend.model.predict = lambda **_kwargs: (_ for _ in ()).throw(RuntimeError("private path"))
    image = np.zeros((12, 12, 3), dtype=np.uint8)
    ok, encoded = backend.cv2.imencode(".jpg", image)
    assert ok
    response = TestClient(backend.app).post(
        "/detect/image",
        files={"file": ("sample.jpg", encoded.tobytes(), "image/jpeg")},
    )
    assert response.status_code == 500
    assert response.json() == {"detail": "Image analysis failed"}


def test_empty_or_unsupported_video_upload_is_rejected(client, tmp_path):
    response = client.post(
        "/detect/video", files={"file": ("empty.mp4", b"", "video/mp4")}
    )
    assert response.status_code == 400


def test_video_upload_limit_is_enforced(client, backend, monkeypatch):
    monkeypatch.setattr(backend, "MAX_VIDEO_BYTES", 3)
    response = client.post(
        "/detect/video", files={"file": ("input.mp4", b"four", "video/mp4")}
    )
    assert response.status_code == 413
    response = client.post(
        "/detect/video", files={"file": ("input.exe", b"x", "application/octet-stream")}
    )
    assert response.status_code == 400


def test_video_upload_uses_generated_safe_temp_name_and_queues(backend, monkeypatch):
    submitted = {}

    class DeferredExecutor:
        def submit(self, function, job_id, path):
            submitted.update(function=function, job_id=job_id, path=path)

    monkeypatch.setattr(backend, "executor", DeferredExecutor())
    response = TestClient(backend.app).post(
        "/detect/video",
        files={"file": ("../../private-name.mp4", b"video bytes", "video/mp4")},
    )
    assert response.status_code == 200
    job_id = response.json()["job_id"]
    assert response.json()["status"] == "queued"
    assert submitted["job_id"] == job_id
    assert os.path.basename(submitted["path"]).startswith("ai_guard_input_")
    assert os.path.isfile(submitted["path"])
    os.unlink(submitted["path"])


def test_video_worker_failure_marks_error_and_removes_input(backend, monkeypatch, tmp_path):
    input_path = tmp_path / "bad.mp4"
    input_path.write_bytes(b"not a video")

    class ClosedCapture:
        def __init__(self, _path):
            pass

        def isOpened(self):
            return False

        def release(self):
            pass

    monkeypatch.setattr(backend.cv2, "VideoCapture", ClosedCapture)
    backend.jobs["failure1"] = {"status": "queued"}
    backend.process_video("failure1", str(input_path))
    assert backend.jobs["failure1"] == {
        "status": "error",
        "message": "Video processing failed",
    }
    assert not input_path.exists()


def test_video_writer_failure_marks_job_error_and_removes_input(
    backend, monkeypatch, tmp_path
):
    input_path = tmp_path / "writer-failure.mp4"
    input_path.write_bytes(b"mock video")

    class OpenCapture:
        def __init__(self, _path):
            pass

        def isOpened(self):
            return True

        def get(self, prop):
            return {
                backend.cv2.CAP_PROP_FPS: 25.0,
                backend.cv2.CAP_PROP_FRAME_COUNT: 1,
                backend.cv2.CAP_PROP_FRAME_WIDTH: 20,
                backend.cv2.CAP_PROP_FRAME_HEIGHT: 20,
            }[prop]

        def release(self):
            pass

    class ClosedWriter:
        def __init__(self, *_args):
            pass

        def isOpened(self):
            return False

        def release(self):
            pass

    monkeypatch.setattr(backend.cv2, "VideoCapture", OpenCapture)
    monkeypatch.setattr(backend.cv2, "VideoWriter", ClosedWriter)
    monkeypatch.setattr(backend, "get_anchors", lambda _capture: [])
    backend.jobs["writerfail"] = {"status": "queued"}
    backend.process_video("writerfail", str(input_path))
    assert backend.jobs["writerfail"]["status"] == "error"
    assert not input_path.exists()
    assert not Path("/tmp/output_writerfail.mp4").exists()


@pytest.mark.parametrize(("confidence", "expected_events"), [(0.60, 0), (0.70, 1)])
def test_video_red_banner_and_incident_require_threshold_and_streak(
    backend, monkeypatch, tmp_path, confidence, expected_events
):
    source = tmp_path / "input.mp4"
    source.write_bytes(b"mocked input")
    output = "/tmp/output_render.mp4"
    if os.path.exists(output):
        os.unlink(output)

    class Capture:
        def __init__(self, _path):
            self.frames = iter([np.zeros((20, 20, 3), dtype=np.uint8) for _ in range(3)])

        def isOpened(self):
            return True

        def get(self, prop):
            return {
                backend.cv2.CAP_PROP_FPS: 25.0,
                backend.cv2.CAP_PROP_FRAME_COUNT: 3,
                backend.cv2.CAP_PROP_FRAME_WIDTH: 20,
                backend.cv2.CAP_PROP_FRAME_HEIGHT: 20,
            }[prop]

        def read(self):
            frame = next(self.frames, None)
            return (frame is not None, frame)

        def release(self):
            pass

    class Writer:
        def __init__(self, path, *_args):
            self.path = path
            with open(path, "wb") as output_file:
                output_file.write(b"mocked output")

        def isOpened(self):
            return True

        def write(self, _frame):
            pass

        def release(self):
            pass

    class FakeBox:
        cls = [2]
        conf = [confidence]
        xyxy = [SimpleNamespace(tolist=lambda: [2, 2, 15, 15])]

    monkeypatch.setattr(backend.cv2, "VideoCapture", Capture)
    monkeypatch.setattr(backend.cv2, "VideoWriter", Writer)
    monkeypatch.setattr(backend, "get_anchors", lambda _capture: [])
    monkeypatch.setattr(
        backend.model,
        "predict",
        lambda **_kwargs: [SimpleNamespace(boxes=[FakeBox()])],
    )
    banners = []
    monkeypatch.setattr(
        backend,
        "_draw_violation_banner",
        lambda *_args: banners.append(True),
    )

    backend.jobs["render"] = {"status": "queued"}
    backend.process_video("render", str(source))
    assert backend.jobs["render"]["status"] == "completed"
    assert backend.jobs["render"]["total_violations"] == expected_events
    assert backend.jobs["render"]["violations_found"] is (expected_events == 1)
    assert len(banners) == expected_events
    assert not source.exists()
    os.unlink(output)
