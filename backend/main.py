"""AI Guard demo API used by the Colab/ngrok deployment.

The model is loaded at import time from /content/best_model_merged.pt, matching
the working Colab application. Video jobs and output files are process-local.
"""

from __future__ import annotations

import base64
import logging
import math
import os
import tempfile
import time
import traceback
import uuid
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Lock
from typing import Any

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from scipy.optimize import linear_sum_assignment
from ultralytics import YOLO

logger = logging.getLogger("ai_guard")

MODEL_PATH = "/content/best_model_merged.pt"
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_VIDEO_BYTES = 250 * 1024 * 1024
VIDEO_SUFFIXES = {".mp4", ".mov", ".avi", ".mkv"}

app = FastAPI(title="AI Guard Detection API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# The deployment expects the private weights to be copied into /content first.
model = YOLO(MODEL_PATH)
model_lock = Lock()
logger.info("AI Guard model loaded from configured runtime path")

CLASSES = {
    0: "book_visible",
    1: "passing_note",
    2: "peeking_around",
    3: "person_normal",
    4: "showing_paper",
    5: "using_mobile",
}
VIOLATIONS = {"book_visible", "passing_note", "peeking_around", "using_mobile"}
PERSON_CLASSES = {
    "person_normal",
    "using_mobile",
    "peeking_around",
    "passing_note",
}
SKIP_CLASSES = {"showing_paper"}

# Single source of truth for both image and video accepted-violation filtering.
CONF_THRESHOLDS = {
    "book_visible": 0.55,
    "passing_note": 0.65,
    "peeking_around": 0.65,
    "using_mobile": 0.55,
    "person_normal": 0.45,
}

GRID_SIZE = 100
MAX_STREAK_GAP = 30
MIN_STREAK = 3
COOLDOWN_FRAMES = 45
MAX_SEAT_MATCH_DISTANCE = 150.0

jobs: dict[str, dict[str, Any]] = {}
executor = ThreadPoolExecutor(max_workers=2)


def predict_safely(**kwargs):
    """Serialize calls because the shared Ultralytics predictor has mutable state."""
    with model_lock:
        return model.predict(**kwargs)


def confidence_threshold(class_name: str) -> float:
    """Return the configured class threshold (0.55 for unknown class names)."""
    return CONF_THRESHOLDS.get(class_name, 0.55)


def is_accepted_violation(class_name: str, confidence: float) -> bool:
    """Confidence-only acceptance; video additionally applies streak/cooldown."""
    return class_name in VIOLATIONS and confidence >= confidence_threshold(class_name)


class ViolationStreakTracker:
    """Per-class/grid temporal filter with independent detection and log clocks."""

    def __init__(
        self,
        min_streak: int = MIN_STREAK,
        cooldown_frames: int = COOLDOWN_FRAMES,
        max_gap: int = MAX_STREAK_GAP,
        grid_size: int = GRID_SIZE,
    ) -> None:
        self.min_streak = min_streak
        self.cooldown_frames = cooldown_frames
        self.max_gap = max_gap
        self.grid_size = grid_size
        self.state: dict[
            tuple[str, int | None, int, int], dict[str, int | None]
        ] = {}

    def should_log(
        self,
        class_name: str,
        cx: float,
        cy: float,
        frame_index: int,
        confidence: float,
        track_id: int | None = None,
    ) -> bool:
        if track_id is not None:
            key = (class_name, track_id, 0, 0)
        else:
            key = (
                class_name,
                None,
                int(cx // self.grid_size),
                int(cy // self.grid_size),
            )
        state = self.state.setdefault(
            key, {"streak": 0, "last_seen": None, "last_logged": None}
        )

        last_seen = state["last_seen"]
        if not is_accepted_violation(class_name, confidence):
            state["streak"] = 0
            state["last_seen"] = frame_index
            return False

        if last_seen is None or frame_index - last_seen > self.max_gap:
            state["streak"] = 0
        state["streak"] = int(state["streak"] or 0) + 1
        state["last_seen"] = frame_index

        if state["streak"] < self.min_streak:
            return False
        last_logged = state["last_logged"]
        if last_logged is not None and frame_index - last_logged < self.cooldown_frames:
            return False

        state["last_logged"] = frame_index
        state["streak"] = 0
        return True


def _box_center(box: tuple[float, float, float, float]) -> np.ndarray:
    x1, y1, x2, y2 = box
    return np.array([(x1 + x2) / 2, (y1 + y2) / 2], dtype=float)


def get_anchors(cap: cv2.VideoCapture, n_frames: int = 60, conf: float = 0.35):
    """Estimate fixed seat anchors and align detections to a stable first frame."""
    all_centers: list[list[tuple[float, float]]] = []
    for _ in range(n_frames):
        ret, frame = cap.read()
        if not ret:
            break
        results = predict_safely(source=frame, conf=conf, verbose=False)
        if not results or results[0].boxes is None or not len(results[0].boxes):
            continue

        centers = []
        for box in results[0].boxes:
            class_id = int(box.cls[0])
            class_name = CLASSES.get(class_id, "")
            if class_name not in PERSON_CLASSES:
                continue
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            centers.append(((x1 + x2) / 2, (y1 + y2) / 2))
        centers.sort(key=lambda point: (round(point[1] / 80) * 80, point[0]))
        if centers:
            all_centers.append(centers)

    if not all_centers:
        return []

    count_by_people = Counter(len(centers) for centers in all_centers)
    seat_count = count_by_people.most_common(1)[0][0]
    valid = [centers for centers in all_centers if len(centers) == seat_count]
    reference = np.asarray(valid[0], dtype=float)
    aligned: list[np.ndarray] = []
    for centers in valid:
        points = np.asarray(centers, dtype=float)
        rows, columns = linear_sum_assignment(
            np.linalg.norm(reference[:, None, :] - points[None, :, :], axis=2)
        )
        ordered = np.empty_like(reference)
        ordered[rows] = points[columns]
        aligned.append(ordered)

    means = np.mean(np.stack(aligned), axis=0)
    return [(round(float(x)), round(float(y))) for x, y in means]


class SeatTracker:
    """Associates detections to fixed seats; it is not persistent identity tracking."""

    def __init__(self, anchors):
        self.anchors = {
            index + 1: np.asarray([float(x), float(y)])
            for index, (x, y) in enumerate(anchors)
        }

    def update(self, detections):
        person_ids = list(self.anchors)
        if not detections:
            return []
        if not person_ids:
            return []

        cost = np.full((len(person_ids), len(detections)), 1e6)
        for person_index, person_id in enumerate(person_ids):
            for detection_index, bbox in enumerate(detections):
                distance = np.linalg.norm(
                    self.anchors[person_id] - _box_center(bbox)
                )
                if distance < MAX_SEAT_MATCH_DISTANCE:
                    cost[person_index, detection_index] = distance

        rows, columns = linear_sum_assignment(cost)
        matches = {}
        for row, column in zip(rows, columns):
            if cost[row, column] < MAX_SEAT_MATCH_DISTANCE:
                person_id = person_ids[row]
                matches[column] = person_id

        results = []
        for detection_index, bbox in enumerate(detections):
            person_id = matches.get(detection_index)
            if person_id is not None:
                results.append((*bbox, person_id, detection_index))
        return results


class RiskTracker:
    """Counts accepted incidents; percentage is a display heuristic, not probability."""

    def __init__(self):
        self.viols = defaultdict(list)

    def add(self, track_id, violation):
        self.viols[track_id].append(violation)

    def risk(self, track_id):
        count = len(self.viols[track_id])
        if count >= 6:
            return "HIGH", (0, 0, 255)
        if count >= 3:
            return "MEDIUM", (0, 140, 255)
        return "LOW", (0, 180, 0)

    def summary(self):
        result = []
        for track_id, violations in self.viols.items():
            level, _ = self.risk(track_id)
            last_event = violations[-1] if violations else {}
            result.append(
                {
                    "track_id": f"S{track_id}",
                    "risk_level": level,
                    "risk_pct": min(len(violations) * 10, 100),
                    "last_seen": last_event.get("timestamp"),
                }
            )
        return sorted(result, key=lambda item: item["risk_pct"], reverse=True)


def _draw_box(image, bbox, label, accepted=False):
    x1, y1, x2, y2 = (int(value) for value in bbox)
    color = (0, 0, 210) if accepted else (120, 120, 120)
    cv2.rectangle(image, (x1, y1), (x2, y2), color, 2 if accepted else 1)
    text_y = max(y1 - 7, 16)
    cv2.putText(
        image,
        label,
        (x1, text_y),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        color,
        2 if accepted else 1,
        cv2.LINE_AA,
    )


def _draw_violation_banner(image, bbox, class_name, confidence):
    x1, y1, _, _ = (int(value) for value in bbox)
    label = f"! {class_name.replace('_', ' ').upper()} {confidence:.0%}"
    (width, height), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.45, 2)
    top = max(y1 - height - 22, 0)
    cv2.rectangle(image, (x1, top), (x1 + width + 10, top + height + 12), (0, 0, 200), -1)
    cv2.putText(
        image,
        label,
        (x1 + 5, top + height + 4),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )


@app.get("/health")
async def health():
    return {"status": "ok", "model": Path(MODEL_PATH).name}


@app.post("/detect/image")
async def detect_image(file: UploadFile = File(...)):
    contents = await file.read(MAX_IMAGE_BYTES + 1)
    if not contents:
        raise HTTPException(status_code=400, detail="Uploaded image is empty")
    if len(contents) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image exceeds the 20 MiB limit")

    image = cv2.imdecode(np.frombuffer(contents, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise HTTPException(status_code=400, detail="Uploaded file is not a valid image")

    start = time.time()
    try:
        results = predict_safely(source=image, conf=0.45, verbose=False)
        if not results:
            raise RuntimeError("Model returned no image result")
        annotated = image.copy()
        detections = []
        violations = []

        for result in results:
            if result.boxes is None:
                continue
            for box in result.boxes:
                class_id = int(box.cls[0])
                class_name = CLASSES.get(class_id, "unknown")
                raw_confidence = float(box.conf[0])
                confidence = round(raw_confidence, 3)
                bbox = tuple(box.xyxy[0].tolist())
                accepted = is_accepted_violation(class_name, raw_confidence)
                detections.append(
                    {
                        "class_id": class_id,
                        "class_name": class_name,
                        "confidence": confidence,
                    }
                )
                _draw_box(
                    annotated,
                    bbox,
                    f"{class_name} {confidence:.2f}",
                    accepted=accepted,
                )
                if accepted:
                    violations.append(
                        {"violation": class_name, "confidence": confidence}
                    )

        encoded, buffer = cv2.imencode(
            ".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 85]
        )
        if not encoded:
            raise RuntimeError("OpenCV could not encode the annotated image")
        return {
            "violations_found": bool(violations),
            "total_detections": len(detections),
            "total_violations": len(violations),
            "inference_time_ms": round((time.time() - start) * 1000, 1),
            "violations": violations,
            "detections": detections,
            "annotated_image": base64.b64encode(buffer).decode("ascii"),
        }
    except Exception as error:
        logger.exception("Image inference failed")
        raise HTTPException(status_code=500, detail="Image analysis failed") from error


def process_video(job_id: str, video_path: str):
    output_path = f"/tmp/output_{job_id}.mp4"
    capture_anchors = None
    capture = None
    writer = None
    succeeded = False
    try:
        jobs[job_id] = {
            "status": "processing",
            "progress": 0,
            "message": "Detecting students...",
        }

        capture_anchors = cv2.VideoCapture(video_path)
        if not capture_anchors.isOpened():
            raise ValueError("Uploaded video could not be opened")
        anchors = get_anchors(capture_anchors)
        capture_anchors.release()
        capture_anchors = None

        capture = cv2.VideoCapture(video_path)
        if not capture.isOpened():
            raise ValueError("Uploaded video could not be opened")
        fps = float(capture.get(cv2.CAP_PROP_FPS))
        if not math.isfinite(fps) or fps <= 0:
            fps = 25.0
        total_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
        if total_frames <= 0 or width <= 0 or height <= 0:
            raise ValueError("Uploaded video has no readable frames or dimensions")
        duration = 0.0

        writer = cv2.VideoWriter(
            output_path,
            cv2.VideoWriter_fourcc(*"mp4v"),
            fps,
            (width, height),
        )
        if not writer.isOpened():
            raise RuntimeError("Could not create the annotated MP4 output")

        seat_tracker = SeatTracker(anchors)
        risk_tracker = RiskTracker()
        streak_tracker = ViolationStreakTracker()
        all_violations = []
        frame_count = 0
        jobs[job_id]["message"] = "Processing..."

        while True:
            ret, frame = capture.read()
            if not ret:
                break

            timestamp = round(frame_count / fps, 1)
            results = predict_safely(source=frame, conf=0.40, verbose=False)
            if not results:
                raise RuntimeError("Model returned no video frame result")
            annotated = frame.copy()
            person_boxes = []
            object_boxes = []
            boxes = results[0].boxes
            if boxes is not None:
                for box in boxes:
                    class_id = int(box.cls[0])
                    class_name = CLASSES.get(class_id, "unknown")
                    if class_name in SKIP_CLASSES:
                        continue
                    bbox = tuple(float(value) for value in box.xyxy[0].tolist())
                    raw_confidence = float(box.conf[0])
                    confidence = round(raw_confidence, 3)
                    _draw_box(
                        annotated,
                        bbox,
                        f"{class_name} {confidence:.2f}",
                        accepted=False,
                    )
                    item = (bbox, class_name, raw_confidence)
                    if class_name in PERSON_CLASSES:
                        person_boxes.append(item)
                    elif class_name == "book_visible":
                        object_boxes.append(item)

            person_detection_boxes = [item[0] for item in person_boxes]
            tracked = seat_tracker.update(person_detection_boxes)
            person_ids = {item[5]: item[4] for item in tracked}

            for index, (bbox, class_name, raw_confidence) in enumerate(person_boxes):
                confidence = round(raw_confidence, 3)
                track_id = person_ids.get(index)
                if track_id is not None:
                    level, color = risk_tracker.risk(track_id)
                    x1, y1, _, _ = (int(value) for value in bbox)
                    cv2.putText(
                        annotated,
                        f"S{track_id} {level}",
                        (x1, max(y1 - 8, 16)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.55,
                        color,
                        2,
                    )

                if class_name not in VIOLATIONS:
                    continue
                accepted_event = streak_tracker.should_log(
                    class_name,
                    *_box_center(bbox),
                    frame_count,
                    raw_confidence,
                    track_id=track_id,
                )
                if not accepted_event:
                    continue

                if track_id is not None:
                    risk_tracker.add(
                        track_id,
                        {"violation": class_name, "timestamp": timestamp},
                    )
                # The existing event-level field reflects confidence severity;
                # person_risk_summary separately reflects accumulated counts.
                event_risk = "HIGH" if raw_confidence > 0.75 else "MEDIUM"
                _draw_box(
                    annotated,
                    bbox,
                    f"{class_name} {confidence:.2f}",
                    accepted=True,
                )
                _draw_violation_banner(annotated, bbox, class_name, confidence)
                all_violations.append(
                    {
                        "violation": class_name,
                        "confidence": confidence,
                        "timestamp": timestamp,
                        "track_id": track_id,
                        "risk_level": event_risk,
                    }
                )

            for bbox, class_name, raw_confidence in object_boxes:
                if not streak_tracker.should_log(
                    class_name,
                    *_box_center(bbox),
                    frame_count,
                    raw_confidence,
                ):
                    continue
                confidence = round(raw_confidence, 3)
                _draw_box(annotated, bbox, f"{class_name} {confidence:.2f}", True)
                _draw_violation_banner(annotated, bbox, class_name, confidence)
                all_violations.append(
                    {
                        "violation": class_name,
                        "confidence": confidence,
                        "timestamp": timestamp,
                        "track_id": None,
                        "risk_level": "MEDIUM",
                    }
                )

            writer.write(annotated)
            frame_count += 1
            if frame_count % 100 == 0:
                progress = round(frame_count / max(total_frames, 1) * 100)
                jobs[job_id]["progress"] = min(progress, 99)
                jobs[job_id]["message"] = f"Frame {frame_count}/{total_frames}"

        if frame_count == 0:
            raise ValueError("Uploaded video contains no decodable frames")

        duration = round(frame_count / fps, 1)
        capture.release()
        capture = None
        writer.release()
        writer = None
        if not os.path.isfile(output_path) or os.path.getsize(output_path) == 0:
            raise RuntimeError("OpenCV did not produce an annotated video")
        unique = sorted({item["violation"] for item in all_violations})
        jobs[job_id] = {
            "status": "completed",
            "progress": 100,
            "video_duration_seconds": duration,
            "total_frames": frame_count,
            "total_violations": len(all_violations),
            "violations_found": bool(all_violations),
            "unique_violations": unique,
            "all_violations": all_violations,
            "output_video_path": output_path,
            "person_risk_summary": risk_tracker.summary(),
        }
        succeeded = True
        logger.info("Video job %s completed with %s incidents", job_id, len(all_violations))
    except Exception:
        traceback.print_exc()
        jobs[job_id] = {"status": "error", "message": "Video processing failed"}
    finally:
        if capture_anchors is not None:
            capture_anchors.release()
        if capture is not None:
            capture.release()
        if writer is not None:
            writer.release()
        try:
            os.unlink(video_path)
        except FileNotFoundError:
            pass
        if not succeeded:
            try:
                os.unlink(output_path)
            except FileNotFoundError:
                pass


@app.post("/detect/video")
async def detect_video(file: UploadFile = File(...)):
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in VIDEO_SUFFIXES:
        raise HTTPException(
            status_code=400,
            detail="Choose an MP4, MOV, AVI or MKV video",
        )

    temp_path = None
    size = 0
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix="ai_guard_input_", suffix=suffix, dir="/tmp", delete=False
        ) as temp_file:
            temp_path = temp_file.name
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_VIDEO_BYTES:
                    raise HTTPException(
                        status_code=413, detail="Video exceeds the 250 MiB limit"
                    )
                temp_file.write(chunk)

        if size == 0:
            raise HTTPException(status_code=400, detail="Uploaded video is empty")

        job_id = uuid.uuid4().hex
        jobs[job_id] = {"status": "queued", "progress": 0, "message": "Queued"}
        try:
            executor.submit(process_video, job_id, temp_path)
        except Exception as error:
            jobs.pop(job_id, None)
            raise HTTPException(status_code=503, detail="Video worker is unavailable") from error
        temp_path = None  # Ownership passed to process_video for guaranteed cleanup.
        return {"status": "queued", "job_id": job_id}
    finally:
        if temp_path is not None:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass
        await file.close()


@app.get("/job/{job_id}")
async def get_job(job_id: str):
    job = jobs.get(job_id)
    if job is None:
        return JSONResponse(status_code=404, content={"error": "Job not found"})
    return {key: value for key, value in job.items() if key != "output_video_path"}


@app.get("/video/{job_id}")
async def get_video(job_id: str):
    job = jobs.get(job_id)
    if job is None:
        return JSONResponse(status_code=404, content={"error": "Job not found"})
    if job.get("status") != "completed":
        return JSONResponse(status_code=400, content={"error": "Not ready yet"})
    path = job.get("output_video_path")
    if not path or not os.path.isfile(path):
        return JSONResponse(status_code=404, content={"error": "Video not found"})
    return FileResponse(
        path,
        media_type="video/mp4",
        filename=f"result_{job_id}.mp4",
    )
