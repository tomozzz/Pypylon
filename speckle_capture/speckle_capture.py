#!/usr/bin/env python3
"""Basler Speckle capture utility using pypylon.

Features:
- Starts acquisition immediately when the script runs.
- Saves frames as numeric arrays (NumPy .npy).
- Saves per-frame camera-internal capture timestamps.
- Supports fixed-duration capture and/or fixed-frame-count capture.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import yaml
from pypylon import genicam, pylon


DROP_NOTIFICATION_INTERVAL_S = 5.0


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
    black_level: float | None = None
    trigger_mode: str | None = None
    trigger_source: str | None = None
    trigger_delay: float | None = None
    enable_acquisition_frame_rate: bool | None = None
    acquisition_frame_rate: float | None = None
    trigger_activation: str | None = None

    # Optional chunked save mode. If set, frames are split into multiple files.
    frames_per_file: int | None = None


def load_config(path: Path) -> CaptureConfig:
    raw_text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".yaml", ".yml"}:
        data = yaml.safe_load(raw_text)
    else:
        data = json.loads(raw_text)

    if not isinstance(data, dict):
        raise ValueError("Config file root must be a dictionary/object")

    return CaptureConfig(**data)



def _get_node_safe(camera: pylon.InstantCamera, name: str) -> object | None:
    try:
        return camera.GetNodeMap().GetNode(name)
    except Exception:
        return None


def set_feature(camera: pylon.InstantCamera, name: str, value: Any) -> None:
    if value is None:
        return

    node = _get_node_safe(camera, name)
    if node is None:
        print(f"[WARN] Feature not found: {name}")
        return

    if not _is_writable(node):
        print(f"[WARN] Feature exists but is not writable: {name}")
        return

    feature = getattr(camera, name)
    try:
        feature.SetValue(value)
    except Exception as exc:
        print(f"[WARN] Failed to set {name}={value!r}: {exc}")



def try_execute_command(camera: pylon.InstantCamera, name: str) -> bool:
    node = _get_node_safe(camera, name)
    if node is None or not _is_writable(node):
        return False
    try:
        getattr(camera, name).Execute()
        return True
    except Exception:
        return False



def enable_timestamp_chunk(camera: pylon.InstantCamera) -> bool:
    try:
        set_feature(camera, "ChunkModeActive", True)
        set_feature(camera, "ChunkSelector", "Timestamp")
        set_feature(camera, "ChunkEnable", True)

        chunk_enabled = _get_node_safe(camera, "ChunkEnable")
        chunk_mode = _get_node_safe(camera, "ChunkModeActive")
        if chunk_enabled is None or chunk_mode is None:
            return False
        return True
    except Exception as exc:
        print(f"[WARN] Failed to enable timestamp chunk. Fallback to host timer: {exc}")
        return False



def get_timestamp_tick_frequency_hz(camera: pylon.InstantCamera) -> float | None:
    # Typical Basler names for timestamp tick frequency.
    candidates = [
        "GevTimestampTickFrequency",
        "GevTimestampTickFrequencyAbs",
        "TimestampTickFrequency",
    ]
    for name in candidates:
        node = _get_node_safe(camera, name)
        if node is None or not _is_readable(node):
            continue
        try:
            return float(getattr(camera, name).GetValue())
        except Exception:
            continue
    return None



def apply_camera_settings(camera: pylon.InstantCamera, cfg: CaptureConfig) -> None:
    # Trigger should often be disabled while changing params.
    set_feature(camera, "TriggerMode", "Off")

    set_feature(camera, "Width", cfg.width)
    set_feature(camera, "Height", cfg.height)
    set_feature(camera, "OffsetX", cfg.offset_x)
    set_feature(camera, "OffsetY", cfg.offset_y)
    set_feature(camera, "PixelFormat", cfg.pixel_format)
    set_feature(camera, "Gain", cfg.gain)
    set_feature(camera, "ExposureTime", cfg.exposure_time)
    set_feature(camera, "BlackLevel", cfg.black_level)

    set_feature(camera, "AcquisitionFrameRateEnable", cfg.enable_acquisition_frame_rate)
    set_feature(camera, "AcquisitionFrameRate", cfg.acquisition_frame_rate)

    set_feature(camera, "TriggerSource", cfg.trigger_source)
    set_feature(camera, "TriggerDelay", cfg.trigger_delay)
    set_feature(camera, "TriggerActivation", cfg.trigger_activation)
    set_feature(camera, "TriggerMode", cfg.trigger_mode)





def get_camera_identity(camera: pylon.InstantCamera) -> dict:
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



def capture(cfg: CaptureConfig, output_override: str | None = None) -> Path:
    if cfg.frame_count is None and cfg.measurement_duration_s is None:
        raise ValueError("Either frame_count or measurement_duration_s must be set.")
    if cfg.frame_count is not None and cfg.frame_count <= 0:
        raise ValueError("frame_count must be > 0 when specified")
    if cfg.measurement_duration_s is not None and cfg.measurement_duration_s <= 0:
        raise ValueError("measurement_duration_s must be > 0 when specified")
    if cfg.frames_per_file is not None and cfg.frames_per_file <= 0:
        raise ValueError("frames_per_file must be > 0 when specified")

    output_dir = Path(output_override or cfg.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    tl_factory = pylon.TlFactory.GetInstance()
    devices = tl_factory.EnumerateDevices()
    if not devices:
        raise RuntimeError("No Basler camera detected.")
    if cfg.camera_index < 0 or cfg.camera_index >= len(devices):
        raise IndexError(f"camera_index={cfg.camera_index} is out of range (detected: {len(devices)})")

    camera = pylon.InstantCamera(tl_factory.CreateDevice(devices[cfg.camera_index]))
    camera.Open()

    try:
        apply_camera_settings(camera, cfg)
        camera_identity = get_camera_identity(camera)
        chunk_timestamp_enabled = enable_timestamp_chunk(camera)

        # Reset camera internal timestamp counter if supported, then start immediately.
        timestamp_reset_done = try_execute_command(camera, "GevTimestampControlReset")
        if not timestamp_reset_done:
            timestamp_reset_done = try_execute_command(camera, "TimestampReset")

        tick_frequency_hz = get_timestamp_tick_frequency_hz(camera)

        # Start acquisition now: measurement starts at this line.
        camera.StartGrabbing(pylon.GrabStrategy_OneByOne, pylon.GrabLoop_ProvidedByUser)
        capture_start_monotonic_s = time.perf_counter()
        capture_start_unix_s = time.time()

        frames: list[np.ndarray] = []
        cam_timestamp_us: list[float] = []

        dropped_total = 0
        dropped_since_last_notice = 0
        next_drop_notice_at_s = DROP_NOTIFICATION_INTERVAL_S

        while camera.IsGrabbing():
            if should_stop_capture(cfg, capture_start_monotonic_s, len(frames)):
                break

            result = camera.RetrieveResult(cfg.timeout_ms, pylon.TimeoutHandling_ThrowException)
            try:
                if not result.GrabSucceeded():
                    # Dropped/failed frame: do not append timestamps or frame.
                    dropped_total += 1
                    dropped_since_last_notice += 1
                    continue

                frame = result.Array.copy()
                frames.append(frame)

                tick_val: int | None = None
                if chunk_timestamp_enabled:
                    try:
                        tick_val = int(result.ChunkTimestamp.Value)
                    except Exception:
                        tick_val = None

                if tick_val is None:
                    # Fallback to host timer in microseconds.
                    elapsed_us = (time.perf_counter() - capture_start_monotonic_s) * 1_000_000.0
                    cam_timestamp_us.append(elapsed_us)
                else:
                    if tick_frequency_hz and tick_frequency_hz > 0:
                        cam_timestamp_us.append((tick_val / tick_frequency_hz) * 1_000_000.0)
                    else:
                        # If frequency is unknown, keep raw tick value as-is in microsecond vector.
                        cam_timestamp_us.append(float(tick_val))
            finally:
                result.Release()

            elapsed_s = time.perf_counter() - capture_start_monotonic_s
            if elapsed_s >= next_drop_notice_at_s:
                if dropped_since_last_notice > 0:
                    print(
                        "[WARN] Dropped/failed frames in last "
                        f"{DROP_NOTIFICATION_INTERVAL_S:.0f}s: {dropped_since_last_notice} "
                        f"(total={dropped_total})"
                    )
                    dropped_since_last_notice = 0
                next_drop_notice_at_s += DROP_NOTIFICATION_INTERVAL_S

        if dropped_since_last_notice > 0:
            print(
                "[WARN] Dropped/failed frames since last notice: "
                f"{dropped_since_last_notice} (total={dropped_total})"
            )

        if not frames:
            raise RuntimeError("No frames captured.")

        total_frame_bytes = sum(frame.nbytes for frame in frames)
        frame_shape = list(frames[0].shape)
        frame_dtype = str(frames[0].dtype)
        frame_count_captured = len(frames)

        frame_files: list[str] = []
        if cfg.frames_per_file is None:
            try:
                frames_arr = np.stack(frames, axis=0)
            except MemoryError as exc:
                gib = total_frame_bytes / (1024**3)
                raise RuntimeError(
                    "Insufficient memory to combine captured frames into one array. "
                    f"Captured frame payload is approximately {gib:.1f} GiB. "
                    "Reduce frame_count / measurement_duration_s, lower image size, "
                    "or save frames in smaller batches."
                ) from exc
            np.save(output_dir / "frames.npy", frames_arr)
            frame_files.append("frames.npy")
        else:
            for start in range(0, frame_count_captured, cfg.frames_per_file):
                chunk = frames[start : start + cfg.frames_per_file]
                try:
                    chunk_arr = np.stack(chunk, axis=0)
                except MemoryError as exc:
                    gib = sum(frame.nbytes for frame in chunk) / (1024**3)
                    raise RuntimeError(
                        "Insufficient memory to combine a frame chunk into one array. "
                        f"Chunk starting at index {start} is approximately {gib:.1f} GiB. "
                        "Reduce frames_per_file or lower image size."
                    ) from exc
                chunk_path = output_dir / f"frames_{start:08d}_{start + len(chunk) - 1:08d}.npy"
                np.save(chunk_path, chunk_arr)
                frame_files.append(chunk_path.name)

        cam_us_arr = np.asarray(cam_timestamp_us, dtype=np.float64)
        # Reduce timestamp granularity to 0.1 ms (100 us) to keep file size smaller.
        cam_us_arr = np.round(cam_us_arr / 100.0) * 100.0
        np.save(output_dir / "timestamps_camera_us.npy", cam_us_arr)

        metadata = {
            "frame_count_requested": cfg.frame_count,
            "measurement_duration_s_requested": cfg.measurement_duration_s,
            "frame_count_captured": frame_count_captured,
            "shape": [frame_count_captured, *frame_shape],
            "dtype": frame_dtype,
            "frame_files": frame_files,
            "frames_per_file": cfg.frames_per_file,
            "camera_index": cfg.camera_index,
            "timeout_ms": cfg.timeout_ms,
            "capture_start_unix_s": capture_start_unix_s,
            "capture_elapsed_s": float(time.perf_counter() - capture_start_monotonic_s),
            "camera_identity": camera_identity,
            "camera_serial_number": camera_identity.get("serial_number"),
            "camera_model": camera_identity.get("model_name"),
            "camera_vendor": camera_identity.get("vendor_name"),
            "timestamp": {
                "source": "camera_chunk_timestamp" if chunk_timestamp_enabled else "host_perf_counter_fallback",
                "camera_timestamp_reset_done": timestamp_reset_done,
                "tick_frequency_hz": tick_frequency_hz,
                "camera_us_note": (
                    "camera_us is converted from camera ticks when tick_frequency_hz is available; "
                    "otherwise camera_us stores raw tick value. Values are quantized to 100 us (0.1 ms)."
                ),
            },
            "config": cfg.__dict__,
        }
        (output_dir / "metadata.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        return output_dir
    finally:
        if camera.IsGrabbing():
            camera.StopGrabbing()
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
