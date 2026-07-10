#!/usr/bin/env python3
"""Basler speckle capture utility using pypylon.

The capture path supports either a fixed exposure or a camera-side Basler
Sequencer cycle.  Chunk data is kept beside every successfully saved frame.
When ``frames_per_file`` is set, bounded producer/consumer buffering keeps
only the current frame chunk and a small, bounded number of writer jobs in
memory while acquisition continues.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import queue
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable

import numpy as np
import yaml
from pypylon import genicam, pylon


DEFAULT_PROGRESS_INTERVAL_S = 5.0
DEFAULT_WRITER_QUEUE_MAX_CHUNKS = 2
FIXED_SEQUENCER_SET_ID = -1


class SequencerConfigurationError(RuntimeError):
    """Raised when reliable camera-side exposure sequencing is unavailable."""


def _is_writable(node: object) -> bool:
    try:
        return bool(genicam.IsWritable(node))
    except Exception:
        return False


def _is_readable(node: object) -> bool:
    try:
        return bool(genicam.IsReadable(node))
    except Exception:
        return False


@dataclass
class CaptureConfig:
    output_dir: str
    camera_index: int = 0
    timeout_ms: int = 5000

    # Stop conditions: at least one must be provided.
    frame_count: int | None = None
    measurement_duration_s: float | None = None

    width: int | None = None
    height: int | None = None
    offset_x: int | None = None
    offset_y: int | None = None
    pixel_format: str | None = None
    gain: float | None = None
    exposure_time: float | None = None
    exposure_times_us: list[float] | None = None
    black_level: float | None = None
    trigger_mode: str | None = None
    trigger_source: str | None = None
    trigger_delay: float | None = None
    enable_acquisition_frame_rate: bool | None = None
    acquisition_frame_rate: float | None = None
    trigger_activation: str | None = None

    # Streaming save controls.
    frames_per_file: int | None = None
    writer_queue_max_chunks: int = DEFAULT_WRITER_QUEUE_MAX_CHUNKS
    progress_interval_s: float = DEFAULT_PROGRESS_INTERVAL_S


def load_config(path: Path) -> CaptureConfig:
    raw_text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".yaml", ".yml"}:
        data = yaml.safe_load(raw_text)
    else:
        data = json.loads(raw_text)

    if not isinstance(data, dict):
        raise ValueError("Config file root must be a dictionary/object")

    cfg = CaptureConfig(**data)
    validate_capture_config(cfg)
    return cfg


def validate_exposure_times(
    values: Iterable[float],
    minimum_us: float | None = None,
    maximum_us: float | None = None,
) -> list[float]:
    if isinstance(values, (str, bytes)):
        raise ValueError("exposure_times_us must be a non-empty numeric array")
    try:
        result = [float(value) for value in values]
    except (TypeError, ValueError) as exc:
        raise ValueError("exposure_times_us must be a non-empty numeric array") from exc
    if not result:
        raise ValueError("exposure_times_us must not be empty")
    for index, value in enumerate(result):
        if not math.isfinite(value) or value <= 0:
            raise ValueError(f"exposure_times_us[{index}] must be finite and > 0, got {value!r}")
        if minimum_us is not None and value < minimum_us:
            raise ValueError(
                f"exposure_times_us[{index}]={value:g} us is below the camera minimum "
                f"of {minimum_us:g} us"
            )
        if maximum_us is not None and value > maximum_us:
            raise ValueError(
                f"exposure_times_us[{index}]={value:g} us is above the camera maximum "
                f"of {maximum_us:g} us"
            )
    return result


def validate_capture_config(cfg: CaptureConfig) -> None:
    if cfg.frame_count is None and cfg.measurement_duration_s is None:
        raise ValueError("Either frame_count or measurement_duration_s must be set.")
    if cfg.frame_count is not None and cfg.frame_count <= 0:
        raise ValueError("frame_count must be > 0 when specified")
    if cfg.measurement_duration_s is not None and cfg.measurement_duration_s <= 0:
        raise ValueError("measurement_duration_s must be > 0 when specified")
    if cfg.frames_per_file is not None and cfg.frames_per_file <= 0:
        raise ValueError("frames_per_file must be > 0 when specified")
    if cfg.writer_queue_max_chunks <= 0:
        raise ValueError("writer_queue_max_chunks must be > 0")
    if not math.isfinite(cfg.progress_interval_s) or cfg.progress_interval_s <= 0:
        raise ValueError("progress_interval_s must be finite and > 0")
    if cfg.exposure_time is not None:
        fixed = float(cfg.exposure_time)
        if not math.isfinite(fixed) or fixed <= 0:
            raise ValueError("exposure_time must be finite and > 0 when specified")
    if cfg.exposure_times_us is not None:
        cfg.exposure_times_us = validate_exposure_times(cfg.exposure_times_us)


def resolve_exposure_request(cfg: CaptureConfig) -> tuple[str, list[float] | None]:
    """Return (mode, requested values), applying the documented precedence."""
    if cfg.exposure_times_us is not None:
        if cfg.exposure_time is not None:
            print(
                "[WARN] Both exposure_times_us and exposure_time are set; "
                "exposure_times_us takes precedence and the fixed value is ignored."
            )
        if len(cfg.exposure_times_us) == 1:
            print(
                "[INFO] exposure_times_us contains one value. The camera Sequencer is still "
                "used, but the exposure is equivalent to a fixed-exposure recording."
            )
        return "sequencer", list(cfg.exposure_times_us)
    return "fixed", None if cfg.exposure_time is None else [float(cfg.exposure_time)]


def _get_node_safe(camera: pylon.InstantCamera, name: str) -> object | None:
    try:
        return camera.GetNodeMap().GetNode(name)
    except Exception:
        return None


def set_feature(camera: pylon.InstantCamera, name: str, value: Any) -> bool:
    """Set an optional feature and return whether the write succeeded."""
    if value is None:
        return False
    node = _get_node_safe(camera, name)
    if node is None:
        print(f"[WARN] Feature not found: {name}")
        return False
    if not _is_writable(node):
        print(f"[WARN] Feature exists but is not writable: {name}")
        return False
    try:
        getattr(camera, name).SetValue(value)
        return True
    except Exception as exc:
        print(f"[WARN] Failed to set {name}={value!r}: {exc}")
        return False


def _set_required_feature(camera: pylon.InstantCamera, name: str, value: Any) -> None:
    node = _get_node_safe(camera, name)
    if node is None:
        raise SequencerConfigurationError(f"Required GenICam node is unavailable: {name}")
    if not _is_writable(node):
        raise SequencerConfigurationError(f"Required GenICam node is not writable: {name}")
    try:
        getattr(camera, name).SetValue(value)
    except Exception as exc:
        raise SequencerConfigurationError(f"Failed to set {name}={value!r}: {exc}") from exc


def try_execute_command(camera: pylon.InstantCamera, name: str) -> bool:
    node = _get_node_safe(camera, name)
    if node is None or not _is_writable(node):
        return False
    try:
        getattr(camera, name).Execute()
        return True
    except Exception:
        return False


def _execute_required_command(camera: pylon.InstantCamera, name: str) -> None:
    node = _get_node_safe(camera, name)
    if node is None:
        raise SequencerConfigurationError(f"Required GenICam command is unavailable: {name}")
    if not _is_writable(node):
        raise SequencerConfigurationError(f"Required GenICam command is not executable: {name}")
    try:
        getattr(camera, name).Execute()
    except Exception as exc:
        raise SequencerConfigurationError(f"Failed to execute {name}: {exc}") from exc


def _read_feature_value(camera: pylon.InstantCamera, name: str) -> Any | None:
    node = _get_node_safe(camera, name)
    if node is None or not _is_readable(node):
        return None
    try:
        return getattr(camera, name).GetValue()
    except Exception:
        return None


def get_exposure_range_us(camera: pylon.InstantCamera) -> tuple[float, float]:
    node = _get_node_safe(camera, "ExposureTime")
    if node is None or not _is_readable(node):
        raise SequencerConfigurationError("ExposureTime is unavailable or unreadable")
    try:
        feature = getattr(camera, "ExposureTime")
        return float(feature.GetMin()), float(feature.GetMax())
    except Exception as exc:
        raise SequencerConfigurationError(f"Could not read ExposureTime range: {exc}") from exc


def enable_frame_chunks(camera: pylon.InstantCamera, sequencer_required: bool) -> dict[str, bool]:
    """Enable supported frame chunks, requiring set IDs for sequencer capture."""
    states = {"timestamp": False, "exposure_time": False, "sequencer_set_active": False}
    mode_node = _get_node_safe(camera, "ChunkModeActive")
    selector_node = _get_node_safe(camera, "ChunkSelector")
    enable_node = _get_node_safe(camera, "ChunkEnable")
    if (
        mode_node is None
        or selector_node is None
        or enable_node is None
        or not _is_writable(mode_node)
        or not _is_writable(selector_node)
        or not _is_writable(enable_node)
    ):
        if sequencer_required:
            raise SequencerConfigurationError(
                "Sequencer capture requires writable ChunkModeActive, ChunkSelector, and "
                "ChunkEnable nodes so each saved image can be matched to SequencerSetActive."
            )
        print("[WARN] Camera chunk data is unavailable; timestamps will use the host timer.")
        return states

    _set_required_feature(camera, "ChunkModeActive", True)
    selectors = (
        ("timestamp", "Timestamp"),
        ("exposure_time", "ExposureTime"),
        ("sequencer_set_active", "SequencerSetActive"),
    )
    for key, selector in selectors:
        try:
            getattr(camera, "ChunkSelector").SetValue(selector)
            getattr(camera, "ChunkEnable").SetValue(True)
            states[key] = True
            print(f"[INFO] Enabled chunk: {selector}")
        except Exception as exc:
            print(f"[WARN] Chunk {selector} is not available: {exc}")

    if sequencer_required and not states["sequencer_set_active"]:
        raise SequencerConfigurationError(
            "The camera does not provide the SequencerSetActive chunk. Reliable per-frame "
            "exposure matching cannot be guaranteed, so software/index fallback is refused."
        )
    return states


def configure_exposure_sequencer(
    camera: pylon.InstantCamera,
    exposure_times_us: Iterable[float],
) -> dict[int, float]:
    """Configure a cyclic, FrameStart-driven Basler USB-style sequencer.

    The acA1440-220um uses the ``Sequencer*`` SFNC nodes.  The function is
    intentionally strict: it never falls back to writing ExposureTime in the
    host acquisition loop.
    """
    minimum_us, maximum_us = get_exposure_range_us(camera)
    requested = validate_exposure_times(exposure_times_us, minimum_us, maximum_us)
    required_nodes = (
        "SequencerMode",
        "SequencerConfigurationMode",
        "SequencerSetSelector",
        "SequencerSetSave",
        "SequencerSetLoad",
        "SequencerPathSelector",
        "SequencerTriggerSource",
        "SequencerSetNext",
        "ExposureTime",
    )
    missing = [name for name in required_nodes if _get_node_safe(camera, name) is None]
    if missing:
        raise SequencerConfigurationError(
            "Camera does not support the required Basler exposure Sequencer nodes: "
            + ", ".join(missing)
            + ". No software exposure-switching fallback will be used."
        )

    try:
        selector = getattr(camera, "SequencerSetSelector")
        minimum_set_id = int(selector.GetMin())
        maximum_set_id = int(selector.GetMax())
    except Exception as exc:
        raise SequencerConfigurationError(
            f"Could not read SequencerSetSelector range: {exc}"
        ) from exc
    if minimum_set_id != 0:
        raise SequencerConfigurationError(
            f"SequencerSetSelector minimum is {minimum_set_id}, but a zero-based continuous "
            "set range is required"
        )
    if len(requested) > maximum_set_id + 1:
        raise ValueError(
            f"exposure_times_us contains {len(requested)} values, but this camera supports "
            f"at most {maximum_set_id + 1} Sequencer Sets"
        )

    # Auto exposure would override values stored in the sets.
    set_feature(camera, "ExposureAuto", "Off")
    set_feature(camera, "GainAuto", "Off")

    applied: dict[int, float] = {}
    try:
        _set_required_feature(camera, "SequencerMode", "Off")
        _set_required_feature(camera, "SequencerConfigurationMode", "On")

        for set_id, requested_us in enumerate(requested):
            _set_required_feature(camera, "SequencerSetSelector", set_id)
            _set_required_feature(camera, "ExposureTime", requested_us)
            actual_us = _read_feature_value(camera, "ExposureTime")
            if actual_us is None:
                raise SequencerConfigurationError("ExposureTime could not be read back")

            # Path 1 advances on every camera-side FrameStart.  Every set gets an
            # explicit next target, including the last-to-first closing edge.
            _set_required_feature(camera, "SequencerPathSelector", 1)
            _set_required_feature(camera, "SequencerTriggerSource", "FrameStart")
            _set_required_feature(camera, "SequencerSetNext", (set_id + 1) % len(requested))
            _execute_required_command(camera, "SequencerSetSave")
            applied[set_id] = float(actual_us)

        # Load set 0 before leaving configuration mode, then enable operation.
        _set_required_feature(camera, "SequencerSetSelector", 0)
        _execute_required_command(camera, "SequencerSetLoad")
        _set_required_feature(camera, "SequencerConfigurationMode", "Off")
        _set_required_feature(camera, "SequencerMode", "On")
    except Exception:
        # Leave the camera in a predictable non-sequencing state after failure.
        try:
            set_feature(camera, "SequencerMode", "Off")
            set_feature(camera, "SequencerConfigurationMode", "Off")
        finally:
            raise

    for set_id, actual_us in applied.items():
        print(
            f"[SEQUENCER] set={set_id} exposure={actual_us:g} us "
            f"next={(set_id + 1) % len(applied)} trigger=FrameStart"
        )
    return applied


def get_timestamp_tick_frequency_hz(
    camera: pylon.InstantCamera,
    model_name: str | None = None,
) -> float | None:
    candidates = (
        "GevTimestampTickFrequency",
        "GevTimestampTickFrequencyAbs",
        "TimestampTickFrequency",
    )
    for name in candidates:
        value = _read_feature_value(camera, name)
        if value is not None:
            try:
                value_f = float(value)
                if value_f > 0:
                    return value_f
            except (TypeError, ValueError):
                pass
    # Basler documents a fixed 1 GHz timestamp clock for acA1440-220um USB.
    if model_name and model_name.lower() == "aca1440-220um":
        return 1_000_000_000.0
    return None


def apply_camera_settings(
    camera: pylon.InstantCamera,
    cfg: CaptureConfig,
    exposure_mode: str,
) -> None:
    set_feature(camera, "TriggerMode", "Off")
    set_feature(camera, "Width", cfg.width)
    set_feature(camera, "Height", cfg.height)
    set_feature(camera, "OffsetX", cfg.offset_x)
    set_feature(camera, "OffsetY", cfg.offset_y)
    set_feature(camera, "PixelFormat", cfg.pixel_format)
    set_feature(camera, "Gain", cfg.gain)
    if exposure_mode == "fixed":
        set_feature(camera, "ExposureTime", cfg.exposure_time)
    set_feature(camera, "BlackLevel", cfg.black_level)
    set_feature(camera, "AcquisitionFrameRateEnable", cfg.enable_acquisition_frame_rate)
    set_feature(camera, "AcquisitionFrameRate", cfg.acquisition_frame_rate)
    set_feature(camera, "TriggerSource", cfg.trigger_source)
    set_feature(camera, "TriggerDelay", cfg.trigger_delay)
    set_feature(camera, "TriggerActivation", cfg.trigger_activation)
    set_feature(camera, "TriggerMode", cfg.trigger_mode)


def get_camera_identity(camera: pylon.InstantCamera) -> dict[str, str | None]:
    serial_number = None
    model_name = None
    vendor_name = None
    try:
        dev = camera.GetDeviceInfo()
        serial_number = dev.GetSerialNumber() or None
        model_name = dev.GetModelName() or None
        vendor_name = dev.GetVendorName() or None
    except Exception:
        pass
    return {
        "serial_number": serial_number,
        "model_name": model_name,
        "vendor_name": vendor_name,
    }


def should_stop_capture(
    cfg: CaptureConfig,
    capture_start_monotonic_s: float,
    captured_frames: int,
) -> bool:
    if cfg.frame_count is not None and captured_frames >= cfg.frame_count:
        return True
    if cfg.measurement_duration_s is not None:
        elapsed_s = time.perf_counter() - capture_start_monotonic_s
        if elapsed_s >= cfg.measurement_duration_s:
            return True
    return False


def _read_chunk_value(result: object, attribute_names: Iterable[str]) -> Any | None:
    for name in attribute_names:
        try:
            feature = getattr(result, name)
            if hasattr(feature, "Value"):
                return feature.Value
            if hasattr(feature, "GetValue"):
                return feature.GetValue()
            return feature
        except Exception:
            continue
    return None


def resolve_frame_exposure_us(
    chunk_exposure_us: Any | None,
    sequencer_set_id: int,
    set_exposure_map: dict[int, float],
    fixed_exposure_us: float,
) -> float:
    """Prefer measured ChunkExposureTime, then map the measured set ID."""
    if chunk_exposure_us is not None:
        try:
            value = float(chunk_exposure_us)
            if math.isfinite(value) and value > 0:
                return value
        except (TypeError, ValueError):
            pass
    if sequencer_set_id in set_exposure_map:
        return float(set_exposure_map[sequencer_set_id])
    return float(fixed_exposure_us)


@dataclass
class FrameChunk:
    start_index: int
    frames: np.ndarray
    timestamps_camera_us: np.ndarray
    exposure_times_us: np.ndarray
    sequencer_set_ids: np.ndarray
    split_files: bool

    @property
    def count(self) -> int:
        return int(self.frames.shape[0])

    @property
    def end_index(self) -> int:
        return self.start_index + self.count - 1


class FrameChunkBuffer:
    """Successful-frame-only buffer with aligned image and metadata entries."""

    def __init__(self, capacity: int | None) -> None:
        self.capacity = capacity
        self.start_index = 0
        self.frames: list[np.ndarray] = []
        self.timestamps_camera_us: list[float] = []
        self.exposure_times_us: list[float] = []
        self.sequencer_set_ids: list[int] = []

    def __len__(self) -> int:
        return len(self.frames)

    def append(
        self,
        frame: np.ndarray,
        timestamp_camera_us: float,
        exposure_time_us: float,
        sequencer_set_id: int,
    ) -> None:
        self.frames.append(frame)
        self.timestamps_camera_us.append(float(timestamp_camera_us))
        self.exposure_times_us.append(float(exposure_time_us))
        self.sequencer_set_ids.append(int(sequencer_set_id))
        self._assert_aligned()

    def is_full(self) -> bool:
        return self.capacity is not None and len(self) >= self.capacity

    def take(self, split_files: bool) -> FrameChunk | None:
        if not self.frames:
            return None
        self._assert_aligned()
        frames_array = np.stack(self.frames, axis=0)
        chunk = FrameChunk(
            start_index=self.start_index,
            frames=frames_array,
            timestamps_camera_us=np.asarray(self.timestamps_camera_us, dtype=np.float64),
            exposure_times_us=np.asarray(self.exposure_times_us, dtype=np.float64),
            sequencer_set_ids=np.asarray(self.sequencer_set_ids, dtype=np.int64),
            split_files=split_files,
        )
        self.start_index += chunk.count
        # Release all per-frame arrays as soon as the writer owns the stacked chunk.
        self.frames.clear()
        self.timestamps_camera_us.clear()
        self.exposure_times_us.clear()
        self.sequencer_set_ids.clear()
        return chunk

    def _assert_aligned(self) -> None:
        lengths = {
            len(self.frames),
            len(self.timestamps_camera_us),
            len(self.exposure_times_us),
            len(self.sequencer_set_ids),
        }
        if len(lengths) != 1:
            raise RuntimeError("Frame buffer and per-frame metadata lengths are inconsistent")


@dataclass
class SaveMetrics:
    start_index: int
    end_index: int
    frame_count: int
    frame_file: str
    timestamp_file: str
    exposure_file: str
    sequencer_file: str
    bytes_written: int
    elapsed_s: float


def _chunk_file_names(chunk: FrameChunk) -> tuple[str, str, str, str]:
    if not chunk.split_files:
        return (
            "frames.npy",
            "timestamps_camera_us.npy",
            "exposure_times_us.npy",
            "sequencer_set_ids.npy",
        )
    suffix = f"{chunk.start_index:08d}_{chunk.end_index:08d}.npy"
    return (
        f"frames_{suffix}",
        f"timestamps_camera_us_{suffix}",
        f"exposure_times_us_{suffix}",
        f"sequencer_set_ids_{suffix}",
    )


def _write_npy_temp(path: Path, array: np.ndarray) -> Path:
    temp_path = path.with_name(path.name + ".tmp")
    with temp_path.open("wb") as handle:
        np.save(handle, array, allow_pickle=False)
        handle.flush()
        os.fsync(handle.fileno())
    return temp_path


def atomic_save_npy(path: Path, array: np.ndarray) -> None:
    temp_path = _write_npy_temp(path, array)
    try:
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            temp_path.unlink()


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    temp_path = path.with_name(path.name + ".tmp")
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    try:
        with temp_path.open("w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            temp_path.unlink()


def save_frame_chunk(output_dir: Path, chunk: FrameChunk) -> SaveMetrics:
    if not (
        chunk.count
        == len(chunk.timestamps_camera_us)
        == len(chunk.exposure_times_us)
        == len(chunk.sequencer_set_ids)
    ):
        raise RuntimeError("Refusing to save a chunk with mismatched frame metadata lengths")

    names = _chunk_file_names(chunk)
    arrays = (
        chunk.frames,
        chunk.timestamps_camera_us,
        chunk.exposure_times_us,
        chunk.sequencer_set_ids,
    )
    paths = tuple(output_dir / name for name in names)
    temp_paths: list[Path] = []
    committed_paths: list[Path] = []
    started = time.perf_counter()
    try:
        for path, array in zip(paths, arrays):
            temp_paths.append(_write_npy_temp(path, array))
        # Commit metadata first and the frame file last. The presence of a final
        # frames*.npy therefore acts as the completed-chunk marker even if the
        # process is forcibly terminated between atomic renames.
        commit_order = [1, 2, 3, 0]
        for index in commit_order:
            temp_path = temp_paths[index]
            path = paths[index]
            os.replace(temp_path, path)
            committed_paths.append(path)
    except Exception:
        # Remove only the incomplete current group; earlier completed chunks remain.
        for path in committed_paths:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise
    finally:
        for temp_path in temp_paths:
            try:
                temp_path.unlink()
            except FileNotFoundError:
                pass

    elapsed_s = time.perf_counter() - started
    bytes_written = sum(path.stat().st_size for path in paths)
    speed_mib_s = bytes_written / (1024**2) / elapsed_s if elapsed_s > 0 else float("inf")
    print(
        f"[SAVE] frames {chunk.start_index}-{chunk.end_index}\n"
        f"       file={names[0]}\n"
        f"       count={chunk.count}\n"
        f"       size={format_bytes(bytes_written)}\n"
        f"       elapsed={elapsed_s:.3f} s\n"
        f"       speed={speed_mib_s:.1f} MiB/s"
    )
    return SaveMetrics(
        start_index=chunk.start_index,
        end_index=chunk.end_index,
        frame_count=chunk.count,
        frame_file=names[0],
        timestamp_file=names[1],
        exposure_file=names[2],
        sequencer_file=names[3],
        bytes_written=bytes_written,
        elapsed_s=elapsed_s,
    )


@dataclass
class CaptureStats:
    captured_frames: int = 0
    saved_frames: int = 0
    saved_chunks: int = 0
    written_bytes: int = 0
    dropped_frames: int = 0
    lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def capture_succeeded(self) -> None:
        with self.lock:
            self.captured_frames += 1

    def capture_failed(self) -> None:
        with self.lock:
            self.dropped_frames += 1

    def saved(self, metrics: SaveMetrics) -> None:
        with self.lock:
            self.saved_frames += metrics.frame_count
            self.saved_chunks += 1
            self.written_bytes += metrics.bytes_written

    def snapshot(self) -> dict[str, int]:
        with self.lock:
            return {
                "captured_frames": self.captured_frames,
                "saved_frames": self.saved_frames,
                "saved_chunks": self.saved_chunks,
                "written_bytes": self.written_bytes,
                "dropped_frames": self.dropped_frames,
            }


class MetadataTracker:
    def __init__(self, output_dir: Path, metadata: dict[str, Any], stats: CaptureStats) -> None:
        self.output_dir = output_dir
        self.path = output_dir / "metadata.json"
        self.metadata = metadata
        self.stats = stats
        self.lock = threading.Lock()
        atomic_write_json(self.path, self.metadata)

    def chunk_saved(self, metrics: SaveMetrics) -> None:
        with self.lock:
            self.metadata["frame_files"].append(metrics.frame_file)
            self.metadata["timestamps_camera_files"].append(metrics.timestamp_file)
            self.metadata["exposure_times_files"].append(metrics.exposure_file)
            self.metadata["sequencer_set_ids_files"].append(metrics.sequencer_file)
            self.metadata["saved_chunks"].append(
                {
                    "start_frame_index": metrics.start_index,
                    "end_frame_index": metrics.end_index,
                    "frame_count": metrics.frame_count,
                    "frame_file": metrics.frame_file,
                    "timestamps_camera_file": metrics.timestamp_file,
                    "exposure_times_file": metrics.exposure_file,
                    "sequencer_set_ids_file": metrics.sequencer_file,
                    "bytes_written": metrics.bytes_written,
                    "save_elapsed_s": metrics.elapsed_s,
                }
            )
            self._copy_stats()
            self.metadata["last_saved_frame_index"] = metrics.end_index
            atomic_write_json(self.path, self.metadata)

    def finish(
        self,
        status: str,
        elapsed_s: float,
        frame_shape: list[int] | None,
        frame_dtype: str | None,
        error_message: str | None = None,
    ) -> None:
        with self.lock:
            self._copy_stats()
            self.metadata["capture_status"] = status
            self.metadata["capture_elapsed_s"] = float(elapsed_s)
            if frame_shape is not None:
                self.metadata["shape"] = [self.metadata["frame_count_saved"], *frame_shape]
            if frame_dtype is not None:
                self.metadata["dtype"] = frame_dtype
            if error_message:
                self.metadata["capture_error"] = error_message
            atomic_write_json(self.path, self.metadata)

    def _copy_stats(self) -> None:
        snapshot = self.stats.snapshot()
        self.metadata["frame_count_captured"] = snapshot["captured_frames"]
        self.metadata["frame_count_saved"] = snapshot["saved_frames"]
        self.metadata["chunk_count_saved"] = snapshot["saved_chunks"]
        self.metadata["written_bytes"] = snapshot["written_bytes"]
        self.metadata["dropped_frames"] = snapshot["dropped_frames"]


class ChunkWriter:
    """Single SSD writer with a bounded queue and explicit backpressure."""

    _STOP = object()

    def __init__(
        self,
        output_dir: Path,
        max_queue_chunks: int,
        on_saved: Callable[[SaveMetrics], None],
    ) -> None:
        self.output_dir = output_dir
        self.queue: queue.Queue[FrameChunk | object] = queue.Queue(maxsize=max_queue_chunks)
        self.on_saved = on_saved
        self.error: BaseException | None = None
        self._closed = False
        self.thread = threading.Thread(target=self._run, name="speckle-ssd-writer", daemon=True)
        self.thread.start()

    @property
    def pending_chunks(self) -> int:
        return self.queue.qsize()

    def submit(self, chunk: FrameChunk) -> None:
        self.raise_if_failed()
        try:
            self.queue.put_nowait(chunk)
            return
        except queue.Full:
            print(
                "[WARN] SSD writer queue is full; acquisition is applying backpressure. "
                "No frames are being discarded and queue memory remains bounded."
            )
        while True:
            self.raise_if_failed()
            try:
                self.queue.put(chunk, timeout=0.5)
                return
            except queue.Full:
                continue

    def close(self) -> None:
        if self._closed:
            self.raise_if_failed()
            return
        while True:
            try:
                self.queue.put(self._STOP, timeout=0.5)
                break
            except queue.Full:
                # Even after a write error the worker keeps draining queued jobs,
                # so wait until the stop marker can be enqueued.
                continue
        self.queue.join()
        self.thread.join()
        self._closed = True
        self.raise_if_failed()

    def raise_if_failed(self) -> None:
        if self.error is not None:
            raise RuntimeError(f"SSD writer failed: {self.error}") from self.error

    def _run(self) -> None:
        while True:
            item = self.queue.get()
            try:
                if item is self._STOP:
                    return
                if self.error is not None:
                    continue
                assert isinstance(item, FrameChunk)
                metrics = save_frame_chunk(self.output_dir, item)
                self.on_saved(metrics)
            except BaseException as exc:  # report to acquisition thread
                if self.error is None:
                    self.error = exc
            finally:
                self.queue.task_done()


def format_bytes(n_bytes: int) -> str:
    value = float(n_bytes)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024.0 or unit == "TiB":
            return f"{value:.2f} {unit}"
        value /= 1024.0
    return f"{value:.2f} TiB"


def calculate_progress(
    cfg: CaptureConfig,
    elapsed_s: float,
    captured_frames: int,
) -> tuple[float | None, float | None]:
    fractions: list[float] = []
    etas: list[float] = []
    if cfg.frame_count is not None:
        fractions.append(captured_frames / cfg.frame_count)
        fps = captured_frames / elapsed_s if elapsed_s > 0 else 0.0
        if fps > 0:
            etas.append(max(0.0, (cfg.frame_count - captured_frames) / fps))
    if cfg.measurement_duration_s is not None:
        fractions.append(elapsed_s / cfg.measurement_duration_s)
        etas.append(max(0.0, cfg.measurement_duration_s - elapsed_s))
    # Capture stops when the first enabled condition is reached.
    fraction = min(1.0, max(fractions)) if fractions else None
    eta = min(etas) if etas else None
    return fraction, eta


def print_progress(
    cfg: CaptureConfig,
    stats: CaptureStats,
    elapsed_s: float,
    buffer_frames: int,
    writer_pending_chunks: int,
) -> None:
    snapshot = stats.snapshot()
    captured = snapshot["captured_frames"]
    effective_fps = captured / elapsed_s if elapsed_s > 0 else 0.0
    fraction, eta = calculate_progress(cfg, elapsed_s, captured)
    target = f"/{cfg.frame_count}" if cfg.frame_count is not None else ""
    percent = f" ({fraction * 100:.1f}%)" if fraction is not None else ""
    eta_line = f"\n           ETA={eta:.1f} s" if eta is not None else ""
    capacity = cfg.frames_per_file if cfg.frames_per_file is not None else "unbounded"
    print(
        f"[PROGRESS] captured={captured}{target}{percent}\n"
        f"           saved={snapshot['saved_frames']}\n"
        f"           elapsed={elapsed_s:.1f} s\n"
        f"           effective_fps={effective_fps:.2f}"
        f"{eta_line}\n"
        f"           chunks={snapshot['saved_chunks']}\n"
        f"           written={format_bytes(snapshot['written_bytes'])}\n"
        f"           buffer={buffer_frames}/{capacity}\n"
        f"           writer_queue={writer_pending_chunks}/{cfg.writer_queue_max_chunks}\n"
        f"           dropped={snapshot['dropped_frames']}"
    )


def print_summary(status: str, stats: CaptureStats, elapsed_s: float) -> None:
    snapshot = stats.snapshot()
    average_fps = snapshot["captured_frames"] / elapsed_s if elapsed_s > 0 else 0.0
    print(
        "[SUMMARY]\n"
        f"status={status}\n"
        f"captured_frames={snapshot['captured_frames']}\n"
        f"saved_frames={snapshot['saved_frames']}\n"
        f"elapsed={elapsed_s:.3f} s\n"
        f"average_fps={average_fps:.3f}\n"
        f"saved_chunks={snapshot['saved_chunks']}\n"
        f"written={format_bytes(snapshot['written_bytes'])}\n"
        f"dropped_frames={snapshot['dropped_frames']}"
    )
    if snapshot["captured_frames"] != snapshot["saved_frames"]:
        print(
            "[WARN] captured_frames and saved_frames do not match: "
            f"{snapshot['captured_frames']} != {snapshot['saved_frames']}"
        )


def _initial_metadata(
    cfg: CaptureConfig,
    camera_identity: dict[str, str | None],
    exposure_mode: str,
    requested_sequence_us: list[float] | None,
    applied_sequence_us: list[float],
    chunk_states: dict[str, bool],
    timestamp_reset_done: bool,
    tick_frequency_hz: float | None,
    capture_start_unix_s: float,
) -> dict[str, Any]:
    return {
        "capture_status": "in_progress",
        "frame_count_requested": cfg.frame_count,
        "measurement_duration_s_requested": cfg.measurement_duration_s,
        "frame_count_captured": 0,
        "frame_count_saved": 0,
        "chunk_count_saved": 0,
        "last_saved_frame_index": None,
        "written_bytes": 0,
        "dropped_frames": 0,
        "shape": None,
        "dtype": None,
        "frame_files": [],
        "timestamps_camera_files": [],
        "exposure_times_files": [],
        "sequencer_set_ids_files": [],
        "saved_chunks": [],
        "frames_per_file": cfg.frames_per_file,
        "camera_index": cfg.camera_index,
        "timeout_ms": cfg.timeout_ms,
        "capture_start_unix_s": capture_start_unix_s,
        "camera_identity": camera_identity,
        "camera_serial_number": camera_identity.get("serial_number"),
        "camera_model": camera_identity.get("model_name"),
        "camera_vendor": camera_identity.get("vendor_name"),
        "exposure_mode": exposure_mode,
        "requested_exposure_sequence_us": requested_sequence_us,
        "exposure_sequence_us": applied_sequence_us,
        "sequencer_enabled": exposure_mode == "sequencer",
        "sequencer_set_count": len(applied_sequence_us) if exposure_mode == "sequencer" else 0,
        "exposure_times_file": "exposure_times_us.npy",
        "sequencer_set_ids_file": "sequencer_set_ids.npy",
        "timestamps_camera_file": "timestamps_camera_us.npy",
        "chunk_data": chunk_states,
        "timestamp": {
            "source": (
                "camera_chunk_timestamp" if chunk_states["timestamp"] else "host_perf_counter_fallback"
            ),
            "camera_timestamp_reset_done": timestamp_reset_done,
            "tick_frequency_hz": tick_frequency_hz,
            "camera_us_note": (
                "Converted from camera ticks when tick_frequency_hz is known; otherwise host "
                "perf_counter elapsed microseconds are used. Values are not quantized."
            ),
        },
        "config": cfg.__dict__,
    }


def _save_combined_metadata_vectors(output_dir: Path, metadata: dict[str, Any]) -> None:
    """Create convenient full vectors after chunked capture; chunks remain recoverable."""
    specifications = (
        ("timestamps_camera_files", "timestamps_camera_us.npy"),
        ("exposure_times_files", "exposure_times_us.npy"),
        ("sequencer_set_ids_files", "sequencer_set_ids.npy"),
    )
    for list_key, output_name in specifications:
        names = metadata.get(list_key, [])
        if not names:
            continue
        # Unsplit capture already wrote the canonical output file.
        if names == [output_name]:
            continue
        arrays = [np.load(output_dir / name, allow_pickle=False, mmap_mode="r") for name in names]
        combined = np.concatenate(arrays)
        atomic_save_npy(output_dir / output_name, combined)
        del combined
        del arrays


def ensure_output_dir_has_no_recording(output_dir: Path) -> None:
    """Refuse to mix a new run with completed or interrupted recording files."""
    conflicts = []
    for pattern in (
        "frames*.npy",
        "timestamps_camera_us*.npy",
        "exposure_times_us*.npy",
        "sequencer_set_ids*.npy",
        "metadata.json",
        "*.npy.tmp",
        "metadata.json.tmp",
    ):
        conflicts.extend(output_dir.glob(pattern))
    if conflicts:
        names = ", ".join(sorted({path.name for path in conflicts})[:5])
        raise FileExistsError(
            "Output directory already contains recording files. Use a new/empty output_dir "
            f"to avoid mixing frame indices ({names})."
        )


def capture(cfg: CaptureConfig, output_override: str | None = None) -> Path:
    validate_capture_config(cfg)
    exposure_mode, requested_sequence_us = resolve_exposure_request(cfg)
    output_dir = Path(output_override or cfg.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    ensure_output_dir_has_no_recording(output_dir)

    if cfg.frames_per_file is None:
        print(
            "[WARN] frames_per_file is not set. Legacy frames.npy output is preserved, but all "
            "frames remain in memory until capture ends. Use frames_per_file: 1000 for long runs."
        )

    tl_factory = pylon.TlFactory.GetInstance()
    devices = tl_factory.EnumerateDevices()
    if not devices:
        raise RuntimeError("No Basler camera detected.")
    if cfg.camera_index < 0 or cfg.camera_index >= len(devices):
        raise IndexError(f"camera_index={cfg.camera_index} is out of range (detected: {len(devices)})")

    camera = pylon.InstantCamera(tl_factory.CreateDevice(devices[cfg.camera_index]))
    camera.Open()

    stats = CaptureStats()
    writer: ChunkWriter | None = None
    tracker: MetadataTracker | None = None
    frame_buffer = FrameChunkBuffer(cfg.frames_per_file)
    status = "failed"
    error_message: str | None = None
    capture_start_monotonic_s: float | None = None
    frame_shape: list[int] | None = None
    frame_dtype: str | None = None

    try:
        apply_camera_settings(camera, cfg, exposure_mode)
        camera_identity = get_camera_identity(camera)
        chunk_states = enable_frame_chunks(camera, sequencer_required=exposure_mode == "sequencer")

        if exposure_mode == "sequencer":
            assert requested_sequence_us is not None
            set_exposure_map = configure_exposure_sequencer(camera, requested_sequence_us)
            applied_sequence_us = [set_exposure_map[index] for index in range(len(set_exposure_map))]
            fixed_exposure_us = applied_sequence_us[0]
        else:
            set_exposure_map = {}
            actual_fixed = _read_feature_value(camera, "ExposureTime")
            if actual_fixed is None:
                if cfg.exposure_time is None:
                    raise RuntimeError("ExposureTime is unreadable and no exposure_time was configured")
                actual_fixed = cfg.exposure_time
            fixed_exposure_us = float(actual_fixed)
            applied_sequence_us = [fixed_exposure_us]

        timestamp_reset_done = try_execute_command(camera, "GevTimestampControlReset")
        if not timestamp_reset_done:
            timestamp_reset_done = try_execute_command(camera, "TimestampReset")
        tick_frequency_hz = get_timestamp_tick_frequency_hz(
            camera, camera_identity.get("model_name")
        )

        capture_start_unix_s = time.time()
        metadata = _initial_metadata(
            cfg,
            camera_identity,
            exposure_mode,
            requested_sequence_us,
            applied_sequence_us,
            chunk_states,
            timestamp_reset_done,
            tick_frequency_hz,
            capture_start_unix_s,
        )
        tracker = MetadataTracker(output_dir, metadata, stats)
        writer = ChunkWriter(
            output_dir,
            max_queue_chunks=cfg.writer_queue_max_chunks,
            on_saved=lambda metrics: (stats.saved(metrics), tracker.chunk_saved(metrics)),
        )

        camera.StartGrabbing(pylon.GrabStrategy_OneByOne, pylon.GrabLoop_ProvidedByUser)
        capture_start_monotonic_s = time.perf_counter()
        next_progress_at_s = cfg.progress_interval_s

        while camera.IsGrabbing():
            snapshot = stats.snapshot()
            if should_stop_capture(cfg, capture_start_monotonic_s, snapshot["captured_frames"]):
                break
            writer.raise_if_failed()

            result = camera.RetrieveResult(cfg.timeout_ms, pylon.TimeoutHandling_ThrowException)
            try:
                if not result.GrabSucceeded():
                    stats.capture_failed()
                    continue

                frame = result.Array.copy()
                if frame_shape is None:
                    frame_shape = list(frame.shape)
                    frame_dtype = str(frame.dtype)

                timestamp_value = None
                if chunk_states["timestamp"]:
                    timestamp_value = _read_chunk_value(result, ("ChunkTimestamp",))
                if timestamp_value is not None and tick_frequency_hz and tick_frequency_hz > 0:
                    timestamp_camera_us = float(timestamp_value) / tick_frequency_hz * 1_000_000.0
                else:
                    timestamp_camera_us = (
                        time.perf_counter() - capture_start_monotonic_s
                    ) * 1_000_000.0

                if exposure_mode == "sequencer":
                    set_value = _read_chunk_value(
                        result,
                        ("ChunkSequencerSetActive", "ChunkSequenceSetIndex"),
                    )
                    if set_value is None:
                        raise RuntimeError(
                            "SequencerSetActive chunk was enabled but is missing from a grabbed frame"
                        )
                    sequencer_set_id = int(set_value)
                    if sequencer_set_id not in set_exposure_map:
                        raise RuntimeError(
                            f"Frame reported unexpected SequencerSetActive={sequencer_set_id}"
                        )
                else:
                    sequencer_set_id = FIXED_SEQUENCER_SET_ID

                chunk_exposure = None
                if chunk_states["exposure_time"]:
                    chunk_exposure = _read_chunk_value(result, ("ChunkExposureTime",))
                exposure_time_us = resolve_frame_exposure_us(
                    chunk_exposure,
                    sequencer_set_id,
                    set_exposure_map,
                    fixed_exposure_us,
                )

                frame_buffer.append(
                    frame,
                    timestamp_camera_us,
                    exposure_time_us,
                    sequencer_set_id,
                )
                stats.capture_succeeded()
            finally:
                result.Release()

            if frame_buffer.is_full():
                chunk = frame_buffer.take(split_files=True)
                assert chunk is not None
                writer.submit(chunk)
                del chunk

            elapsed_s = time.perf_counter() - capture_start_monotonic_s
            if elapsed_s >= next_progress_at_s:
                print_progress(cfg, stats, elapsed_s, len(frame_buffer), writer.pending_chunks)
                while next_progress_at_s <= elapsed_s:
                    next_progress_at_s += cfg.progress_interval_s

        if stats.snapshot()["captured_frames"] == 0:
            raise RuntimeError("No frames captured.")

        final_chunk = frame_buffer.take(split_files=cfg.frames_per_file is not None)
        if final_chunk is not None:
            writer.submit(final_chunk)
            del final_chunk
        writer.close()
        _save_combined_metadata_vectors(output_dir, tracker.metadata)
        status = "completed"
        elapsed_s = time.perf_counter() - capture_start_monotonic_s
        tracker.finish(status, elapsed_s, frame_shape, frame_dtype)
        return output_dir
    except KeyboardInterrupt:
        status = "interrupted"
        error_message = "Capture interrupted by user"
        raise
    except Exception as exc:
        status = "failed"
        error_message = str(exc)
        raise
    finally:
        if camera.IsGrabbing():
            camera.StopGrabbing()

        # Preserve a successfully captured partial buffer on interruption/failure
        # when the writer itself is still healthy.
        if status != "completed" and writer is not None:
            try:
                partial = frame_buffer.take(split_files=cfg.frames_per_file is not None)
                if partial is not None:
                    writer.submit(partial)
                    del partial
                writer.close()
            except Exception as writer_exc:
                status = "failed"
                writer_text = f"SSD finalization failed: {writer_exc}"
                error_message = (
                    f"{error_message}; {writer_text}" if error_message else writer_text
                )

        elapsed_s = (
            time.perf_counter() - capture_start_monotonic_s
            if capture_start_monotonic_s is not None
            else 0.0
        )
        if tracker is not None and status != "completed":
            try:
                tracker.finish(status, elapsed_s, frame_shape, frame_dtype, error_message)
            except Exception as metadata_exc:
                print(f"[WARN] Failed to update metadata.json during cleanup: {metadata_exc}")
        print_summary(status, stats, elapsed_s)

        if camera.IsOpen():
            camera.Close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Capture speckle images from Basler camera using pypylon")
    parser.add_argument("--config", required=True, help="Path to config file (.yaml/.yml/.json)")
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Optional output directory override. If omitted, config output_dir is used.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cfg = load_config(Path(args.config))
    out = capture(cfg, output_override=args.output_dir)
    print(f"Capture completed. Saved to: {out}")


if __name__ == "__main__":
    main()
