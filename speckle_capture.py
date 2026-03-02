#!/usr/bin/env python3
"""Basler Speckle capture utility using pypylon.

- Captures frames as numeric arrays (NumPy .npy)
- Saves per-frame elapsed time from capture start in milliseconds
- Applies camera parameters from a config file
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover
    yaml = None

from pypylon import pylon


@dataclass
class CaptureConfig:
    output_dir: str
    frame_count: int
    camera_index: int = 0
    timeout_ms: int = 5000

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


def load_config(path: Path) -> CaptureConfig:
    raw_text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".yaml", ".yml"}:
        if yaml is None:
            raise RuntimeError("PyYAML is required for YAML config files. Install with: pip install pyyaml")
        data = yaml.safe_load(raw_text)
    else:
        data = json.loads(raw_text)

    if not isinstance(data, dict):
        raise ValueError("Config file root must be a dictionary/object")

    return CaptureConfig(**data)


def set_feature(camera: pylon.InstantCamera, name: str, value: Any) -> None:
    if value is None:
        return

    node = camera.GetNodeMap().GetNode(name)
    if node is None:
        print(f"[WARN] Feature not found: {name}")
        return

    if not pylon.IsWritable(node):
        print(f"[WARN] Feature exists but is not writable: {name}")
        return

    feature = getattr(camera, name)
    try:
        feature.SetValue(value)
    except Exception as exc:
        print(f"[WARN] Failed to set {name}={value!r}: {exc}")


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


def capture(cfg: CaptureConfig, output_override: str | None = None) -> Path:
    if cfg.frame_count <= 0:
        raise ValueError("frame_count must be > 0")

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

        camera.StartGrabbingMax(cfg.frame_count)
        timestamps_ms = np.empty(cfg.frame_count, dtype=np.float64)
        frames = None

        start_ns = time.perf_counter_ns()
        index = 0

        while camera.IsGrabbing():
            result = camera.RetrieveResult(cfg.timeout_ms, pylon.TimeoutHandling_ThrowException)
            try:
                if not result.GrabSucceeded():
                    raise RuntimeError(f"Grab failed at frame {index}: code={result.GetErrorCode()}, msg={result.GetErrorDescription()}")

                frame = result.Array
                if frames is None:
                    frames = np.empty((cfg.frame_count, frame.shape[0], frame.shape[1]), dtype=frame.dtype)

                frames[index] = frame
                timestamps_ms[index] = (time.perf_counter_ns() - start_ns) / 1_000_000.0
                index += 1
            finally:
                result.Release()

        if frames is None or index == 0:
            raise RuntimeError("No frames captured.")

        if index != cfg.frame_count:
            frames = frames[:index]
            timestamps_ms = timestamps_ms[:index]

        np.save(output_dir / "frames.npy", frames)
        np.save(output_dir / "timestamps_ms.npy", timestamps_ms)

        metadata = {
            "frame_count_requested": cfg.frame_count,
            "frame_count_captured": int(index),
            "shape": list(frames.shape),
            "dtype": str(frames.dtype),
            "camera_index": cfg.camera_index,
            "timeout_ms": cfg.timeout_ms,
            "captured_at_unix": time.time(),
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
