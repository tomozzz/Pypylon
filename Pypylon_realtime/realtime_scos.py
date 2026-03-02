from __future__ import annotations

import argparse
import json
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import matplotlib.pyplot as plt

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover
    yaml = None

from pypylon import pylon

from .image_stats import box_mean, erode_valid_mask, local_std


@dataclass
class CameraConfig:
    camera_index: int = 0
    timeout_ms: int = 5000
    pixel_format: str = "Mono12"
    width: int | None = None
    height: int | None = None
    offset_x: int | None = None
    offset_y: int | None = None
    exposure_time: float = 10000.0
    gain: float = 16.0
    black_level: float = 400.0
    trigger_mode: str = "Off"
    trigger_source: str | None = None
    acquisition_frame_rate_enable: bool | None = None
    acquisition_frame_rate: float | None = 20.0


@dataclass
class RealtimeSCOSConfig:
    output_dir: str
    frame_count: int = 1200
    dark_frame_count: int = 400
    spatial_frame_count: int = 400
    window_size: int = 9
    show_every_n_frames: int = 50
    frame_rate_hz: float = 20.0
    actual_gain_du_per_e: float = 0.25
    interactive_roi: bool = False
    roi_center_xy: list[float] | None = None
    roi_radius: float | None = None
    camera: CameraConfig = field(default_factory=CameraConfig)


def load_config(path: Path) -> RealtimeSCOSConfig:
    raw = path.read_text(encoding="utf-8")
    data = yaml.safe_load(raw) if path.suffix in {".yaml", ".yml"} and yaml else json.loads(raw)
    cam = CameraConfig(**data.pop("camera", {}))
    return RealtimeSCOSConfig(camera=cam, **data)


def _set_feature(camera: pylon.InstantCamera, name: str, value: Any) -> None:
    if value is None:
        return
    try:
        node = camera.GetNodeMap().GetNode(name)
        if node is None or not pylon.IsWritable(node):
            return
        getattr(camera, name).SetValue(value)
    except Exception:
        pass


def apply_camera(camera: pylon.InstantCamera, cfg: CameraConfig) -> None:
    _set_feature(camera, "TriggerMode", "Off")
    _set_feature(camera, "PixelFormat", cfg.pixel_format)
    _set_feature(camera, "Width", cfg.width)
    _set_feature(camera, "Height", cfg.height)
    _set_feature(camera, "OffsetX", cfg.offset_x)
    _set_feature(camera, "OffsetY", cfg.offset_y)
    _set_feature(camera, "ExposureTime", cfg.exposure_time)
    _set_feature(camera, "Gain", cfg.gain)
    _set_feature(camera, "BlackLevel", cfg.black_level)
    _set_feature(camera, "AcquisitionFrameRateEnable", cfg.acquisition_frame_rate_enable)
    _set_feature(camera, "AcquisitionFrameRate", cfg.acquisition_frame_rate)
    _set_feature(camera, "TriggerSource", cfg.trigger_source)
    _set_feature(camera, "TriggerMode", cfg.trigger_mode)


def capture_n(camera: pylon.InstantCamera, n: int, timeout_ms: int) -> np.ndarray:
    camera.StartGrabbingMax(n)
    frames = []
    while camera.IsGrabbing():
        res = camera.RetrieveResult(timeout_ms, pylon.TimeoutHandling_ThrowException)
        try:
            if res.GrabSucceeded():
                frames.append(res.Array.copy())
        finally:
            res.Release()
    if not frames:
        raise RuntimeError("No frames captured")
    return np.stack(frames, axis=0)


def select_roi(mean_img: np.ndarray, cfg: RealtimeSCOSConfig) -> np.ndarray:
    h, w = mean_img.shape
    if cfg.roi_center_xy and cfg.roi_radius:
        cx, cy = cfg.roi_center_xy
        yy, xx = np.ogrid[:h, :w]
        mask = (xx - cx) ** 2 + (yy - cy) ** 2 <= cfg.roi_radius ** 2
    elif cfg.interactive_roi:
        fig, ax = plt.subplots()
        ax.imshow(mean_img, cmap="gray")
        ax.set_title("Click center then edge of ROI circle")
        pts = plt.ginput(2, timeout=0)
        plt.close(fig)
        if len(pts) != 2:
            raise RuntimeError("ROI selection cancelled")
        (cx, cy), (ex, ey) = pts
        r = float(np.hypot(ex - cx, ey - cy))
        yy, xx = np.ogrid[:h, :w]
        mask = (xx - cx) ** 2 + (yy - cy) ** 2 <= r ** 2
    else:
        mask = np.ones_like(mean_img, dtype=bool)
    return erode_valid_mask(mask, cfg.window_size)


def process(cfg: RealtimeSCOSConfig) -> Path:
    out = Path(cfg.output_dir).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)

    tl = pylon.TlFactory.GetInstance()
    devs = tl.EnumerateDevices()
    if not devs:
        raise RuntimeError("No camera detected")
    cam = pylon.InstantCamera(tl.CreateDevice(devs[cfg.camera.camera_index]))
    cam.Open()
    apply_camera(cam, cfg.camera)

    try:
        dark_frames = capture_n(cam, cfg.dark_frame_count, cfg.camera.timeout_ms).astype(np.float64)
        dark_mean = dark_frames.mean(axis=0) - cfg.camera.black_level
        dark_var = dark_frames.var(axis=0)
        dark_var_window = box_mean(dark_var, cfg.window_size)

        spatial_frames = capture_n(cam, cfg.spatial_frame_count, cfg.camera.timeout_ms).astype(np.float64)
        spatial_minus_dark = spatial_frames - cfg.camera.black_level - dark_mean
        sp_im = spatial_minus_dark.mean(axis=0)
        sp_var = local_std(sp_im, cfg.window_size) ** 2

        mask = select_roi(sp_im, cfg)
        mask_idx = np.where(mask)

        all_frames = capture_n(cam, cfg.frame_count, cfg.camera.timeout_ms).astype(np.float64)
        frames_corr = all_frames - cfg.camera.black_level - dark_mean

        n = frames_corr.shape[0]
        raw_k2 = np.full(n, np.nan, dtype=np.float64)
        corr_k2 = np.full(n, np.nan, dtype=np.float64)
        mean_i = np.full(n, np.nan, dtype=np.float64)

        plt.ion()
        fig, axes = plt.subplots(3, 1, figsize=(8, 7))
        l1, = axes[0].plot([], [])
        l2, = axes[1].plot([], [])
        l3, = axes[2].plot([], [])
        axes[0].set_ylabel("Kcorr^2")
        axes[1].set_ylabel("I [DU]")
        axes[2].set_ylabel("BFI")
        axes[2].set_xlabel("time [s]")

        t = np.arange(n, dtype=np.float64) / cfg.frame_rate_hz
        for k in range(n):
            im = frames_corr[k]
            std_im = local_std(im, cfg.window_size)
            fit_i = box_mean(im, cfg.window_size)
            fit_i2 = np.maximum(fit_i * fit_i, 1e-12)

            std2_m = (std_im[mask_idx] ** 2)
            fit_m = fit_i[mask_idx]
            fit2_m = fit_i2[mask_idx]
            mean_i[k] = im[mask_idx].mean()
            raw_k2[k] = np.mean(std2_m / fit2_m)
            corr_k2[k] = np.mean(
                (std2_m - cfg.actual_gain_du_per_e * fit_m - sp_var[mask_idx] - (1.0 / 12.0) - dark_var_window[mask_idx]) / fit2_m
            )

            if k == 0 or (k + 1) % cfg.show_every_n_frames == 0:
                valid = ~np.isnan(corr_k2)
                bfi = np.where(valid, 1.0 / np.maximum(corr_k2, 1e-12), np.nan)
                l1.set_data(t[valid], corr_k2[valid])
                l2.set_data(t[valid], mean_i[valid])
                l3.set_data(t[valid], bfi[valid])
                for ax in axes:
                    ax.relim()
                    ax.autoscale_view()
                fig.canvas.draw_idle()
                fig.canvas.flush_events()

        bfi = 1.0 / np.maximum(corr_k2, 1e-12)
        base_n = max(int(round(10 * cfg.frame_rate_hz)), 1)
        if t[-1] > 120:
            rbfi = bfi / np.nanmean(bfi[:base_n])
        else:
            rbfi = bfi / np.nanpercentile(bfi[:base_n], 5)

        np.save(out / "frames_raw.npy", all_frames)
        np.save(out / "frames_corrected.npy", frames_corr)
        np.save(out / "dark_mean.npy", dark_mean)
        np.save(out / "dark_var.npy", dark_var)
        np.save(out / "spatial_var.npy", sp_var)
        np.save(out / "mask.npy", mask)
        np.savez(
            out / "scos_timeseries.npz",
            time_s=t,
            mean_i=mean_i,
            raw_speckle_contrast=raw_k2,
            corr_speckle_contrast=corr_k2,
            bfi=bfi,
            rbfi=rbfi,
        )

        meta = {
            "config": asdict(cfg),
            "captured_at_unix": time.time(),
            "frame_shape": list(all_frames.shape[1:]),
            "frame_count": int(n),
        }
        (out / "metadata.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
        return out
    finally:
        if cam.IsGrabbing():
            cam.StopGrabbing()
        if cam.IsOpen():
            cam.Close()


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Realtime SCOS (Pypylon) with BFI computation")
    ap.add_argument("--config", required=True)
    return ap.parse_args()


def main() -> None:
    args = parse_args()
    cfg = load_config(Path(args.config))
    out = process(cfg)
    print(f"Saved results to: {out}")


if __name__ == "__main__":
    main()
