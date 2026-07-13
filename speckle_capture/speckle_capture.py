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
import math
import os
import queue
import threading
import time
from dataclasses import asdict, dataclass, field
from numbers import Real
from pathlib import Path
from typing import Any, Callable, Sequence

import numpy as np

try:
    import yaml
except ImportError:  # Pure helpers and fake-camera tests do not require YAML.
    yaml = None  # type: ignore[assignment]

try:
    from pypylon import genicam, pylon
except ImportError:  # Allow camera-free unit tests to import the module.
    genicam = None  # type: ignore[assignment]
    pylon = None  # type: ignore[assignment]


DROP_NOTIFICATION_INTERVAL_S = 5.0
DEFAULT_PROGRESS_INTERVAL_S = 10.0
WRITE_QUEUE_MAX_CHUNKS = 2
WRITE_QUEUE_PUT_TIMEOUT_S = 5.0
UNKNOWN_SEQUENCER_SET_ID = -1


@dataclass(frozen=True)
class ResolvedFeature:
    name: str
    node: object


def _is_writable(node: object) -> bool:
    try:
        if genicam is not None:
            return bool(genicam.IsWritable(node))
    except Exception:
        pass
    try:
        value = getattr(node, "writable", getattr(node, "IsWritable", True))
        return bool(value() if callable(value) else value)
    except Exception:
        return False


def _is_readable(node: object) -> bool:
    try:
        if genicam is not None:
            return bool(genicam.IsReadable(node))
    except Exception:
        pass
    try:
        value = getattr(node, "readable", getattr(node, "IsReadable", True))
        return bool(value() if callable(value) else value)
    except Exception:
        return False


def _is_available(node: object) -> bool:
    try:
        if genicam is not None:
            return bool(genicam.IsAvailable(node))
    except Exception:
        pass
    try:
        value = getattr(node, "available", getattr(node, "IsAvailable", True))
        return bool(value() if callable(value) else value)
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

    # Optional chunked save mode. If set, frames are split into multiple files.
    frames_per_file: int | None = None
    progress_interval_s: float = DEFAULT_PROGRESS_INTERVAL_S


@dataclass(frozen=True)
class ExposurePlan:
    mode: str
    requested_times_us: tuple[float, ...]


def _positive_finite_number(value: object, field_name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, Real):
        raise ValueError(f"{field_name} must be a finite number > 0")
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        raise ValueError(f"{field_name} must be a finite number > 0")
    return result


def validate_capture_config(cfg: CaptureConfig) -> ExposurePlan:
    if cfg.frame_count is None and cfg.measurement_duration_s is None:
        raise ValueError("Either frame_count or measurement_duration_s must be set.")
    if cfg.frame_count is not None:
        if isinstance(cfg.frame_count, bool) or not isinstance(cfg.frame_count, int) or cfg.frame_count <= 0:
            raise ValueError("frame_count must be a positive integer when specified")
    if cfg.measurement_duration_s is not None:
        _positive_finite_number(cfg.measurement_duration_s, "measurement_duration_s")
    if cfg.frames_per_file is not None:
        if (
            isinstance(cfg.frames_per_file, bool)
            or not isinstance(cfg.frames_per_file, int)
            or cfg.frames_per_file <= 0
        ):
            raise ValueError("frames_per_file must be a positive integer when specified")
    _positive_finite_number(cfg.progress_interval_s, "progress_interval_s")
    if isinstance(cfg.camera_index, bool) or not isinstance(cfg.camera_index, int) or cfg.camera_index < 0:
        raise ValueError("camera_index must be a non-negative integer")
    if isinstance(cfg.timeout_ms, bool) or not isinstance(cfg.timeout_ms, int) or cfg.timeout_ms <= 0:
        raise ValueError("timeout_ms must be a positive integer")

    if cfg.exposure_times_us is not None:
        if not isinstance(cfg.exposure_times_us, (list, tuple)):
            raise ValueError("exposure_times_us must be an array of finite numbers > 0")
        if not cfg.exposure_times_us:
            raise ValueError("exposure_times_us must not be empty")
        times = tuple(
            _positive_finite_number(value, f"exposure_times_us[{index}]")
            for index, value in enumerate(cfg.exposure_times_us)
        )
        if cfg.exposure_time is not None:
            print("[INFO] Both exposure_times_us and exposure_time are set; exposure_times_us takes precedence.")
        if len(times) == 1:
            print("[INFO] A one-element exposure_times_us sequence will use the camera sequencer (fixed-equivalent).")
        return ExposurePlan("sequencer", times)

    if cfg.exposure_time is None:
        return ExposurePlan("fixed", ())
    return ExposurePlan("fixed", (_positive_finite_number(cfg.exposure_time, "exposure_time"),))


def load_config(path: Path) -> CaptureConfig:
    raw_text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".yaml", ".yml"}:
        if yaml is None:
            raise RuntimeError("PyYAML is required to read YAML configuration files")
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


def _resolve_feature(
    camera: object,
    candidates: Sequence[str],
    *,
    readable: bool = False,
    writable: bool = False,
    required: bool = False,
    purpose: str | None = None,
) -> ResolvedFeature | None:
    for name in candidates:
        node = _get_node_safe(camera, name)  # type: ignore[arg-type]
        if node is None or not _is_available(node):
            continue
        if readable and not _is_readable(node):
            continue
        if writable and not _is_writable(node):
            continue
        return ResolvedFeature(name=name, node=node)
    if required:
        access = "readable/writable" if readable and writable else "readable" if readable else "writable"
        label = purpose or "feature"
        raise RuntimeError(
            f"Camera does not provide the required {access} GenICam {label}. "
            f"Tried nodes: {', '.join(candidates)}"
        )
    return None


def _feature_proxy(camera: object, feature: ResolvedFeature) -> object:
    try:
        return getattr(camera, feature.name)
    except Exception:
        return feature.node


def _set_feature_value(camera: object, feature: ResolvedFeature, value: Any) -> None:
    proxy = _feature_proxy(camera, feature)
    setter = getattr(proxy, "SetValue", None)
    if callable(setter):
        setter(value)
        return
    if hasattr(proxy, "Value"):
        setattr(proxy, "Value", value)
        return
    raise RuntimeError(f"GenICam node {feature.name} has no value setter")


def _get_feature_value(camera: object, feature: ResolvedFeature) -> Any:
    proxy = _feature_proxy(camera, feature)
    getter = getattr(proxy, "GetValue", None)
    if callable(getter):
        return getter()
    if hasattr(proxy, "Value"):
        return getattr(proxy, "Value")
    raise RuntimeError(f"GenICam node {feature.name} has no value getter")


def _execute_feature(camera: object, feature: ResolvedFeature) -> None:
    proxy = _feature_proxy(camera, feature)
    execute = getattr(proxy, "Execute", None)
    if not callable(execute):
        raise RuntimeError(f"GenICam node {feature.name} is not executable")
    execute()


def _feature_min_max(camera: object, feature: ResolvedFeature) -> tuple[float | None, float | None]:
    proxy = _feature_proxy(camera, feature)
    minimum = getattr(proxy, "Min", None)
    maximum = getattr(proxy, "Max", None)
    if minimum is None:
        getter = getattr(proxy, "GetMin", None)
        minimum = getter() if callable(getter) else None
    if maximum is None:
        getter = getattr(proxy, "GetMax", None)
        maximum = getter() if callable(getter) else None
    return (
        float(minimum) if minimum is not None else None,
        float(maximum) if maximum is not None else None,
    )


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



@dataclass(frozen=True)
class ChunkCapabilities:
    timestamp_enabled: bool = False
    exposure_enabled: bool = False
    sequencer_set_enabled: bool = False
    enabled_selector_values: tuple[str, ...] = ()
    selector_names: dict[str, str] = field(default_factory=dict)


def _enable_chunk_selector(camera: object, selector_candidates: Sequence[str]) -> str | None:
    selector = _resolve_feature(
        camera,
        ("ChunkSelector",),
        writable=True,
        required=False,
    )
    if selector is None:
        return None
    for selector_value in selector_candidates:
        try:
            _set_feature_value(camera, selector, selector_value)
            enable = _resolve_feature(
                camera,
                ("ChunkEnable",),
                readable=True,
                writable=True,
                required=False,
            )
            if enable is None:
                continue
            _set_feature_value(camera, enable, True)
            if bool(_get_feature_value(camera, enable)):
                return selector_value
        except Exception:
            continue
    return None


def configure_chunk_data(camera: object) -> ChunkCapabilities:
    mode = _resolve_feature(
        camera,
        ("ChunkModeActive",),
        readable=True,
        writable=True,
        required=False,
    )
    if mode is None:
        print("[WARN] ChunkModeActive is unavailable; camera timestamps will use the host timer.")
        return ChunkCapabilities()
    try:
        _set_feature_value(camera, mode, True)
        if not bool(_get_feature_value(camera, mode)):
            raise RuntimeError("ChunkModeActive did not become enabled")
    except Exception as exc:
        print(f"[WARN] Failed to enable chunk mode; camera timestamps will use the host timer: {exc}")
        return ChunkCapabilities()

    selectors: dict[str, str] = {}
    timestamp = _enable_chunk_selector(camera, ("Timestamp", "TimestampValue"))
    if timestamp is not None:
        selectors["timestamp"] = timestamp
    exposure = _enable_chunk_selector(camera, ("ExposureTime", "ExposureTimeAbs"))
    if exposure is not None:
        selectors["exposure"] = exposure
    sequencer_set = _enable_chunk_selector(
        camera,
        ("SequencerSetActive", "SequenceSetIndex"),
    )
    if sequencer_set is not None:
        selectors["sequencer_set"] = sequencer_set

    if timestamp is None:
        print("[WARN] Timestamp chunk is unavailable; using host perf_counter timestamps.")
    if exposure is None:
        print("[WARN] ExposureTime chunk is unavailable.")
    if sequencer_set is None:
        print("[INFO] Sequencer set chunk is unavailable; set IDs will be derived from chunk exposure when unique.")

    return ChunkCapabilities(
        timestamp_enabled=timestamp is not None,
        exposure_enabled=exposure is not None,
        sequencer_set_enabled=sequencer_set is not None,
        enabled_selector_values=tuple(selectors.values()),
        selector_names=selectors,
    )


def _reenable_chunk_selectors(camera: object, selector_values: Sequence[str]) -> None:
    if not selector_values:
        return
    mode = _resolve_feature(
        camera,
        ("ChunkModeActive",),
        writable=True,
        required=True,
        purpose="chunk mode node",
    )
    assert mode is not None
    _set_feature_value(camera, mode, True)
    for selector_value in selector_values:
        if _enable_chunk_selector(camera, (selector_value,)) is None:
            raise RuntimeError(f"Chunk selector {selector_value!r} became unavailable while saving sequencer sets")


def enable_timestamp_chunk(camera: pylon.InstantCamera) -> bool:
    """Backward-compatible wrapper retained for external callers."""
    return configure_chunk_data(camera).timestamp_enabled



def get_timestamp_tick_frequency_hz(
    camera: pylon.InstantCamera,
    model_name: str | None = None,
) -> float | None:
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
    if (model_name or "").strip().lower() == "aca1440-220um":
        print("[INFO] Timestamp tick frequency node unavailable; using acA1440-220um documented 1 GHz clock.")
        return 1_000_000_000.0
    return None



def apply_camera_settings(
    camera: pylon.InstantCamera,
    cfg: CaptureConfig,
    *,
    apply_exposure: bool = True,
) -> None:
    # Trigger should often be disabled while changing params.
    set_feature(camera, "TriggerMode", "Off")

    set_feature(camera, "Width", cfg.width)
    set_feature(camera, "Height", cfg.height)
    set_feature(camera, "OffsetX", cfg.offset_x)
    set_feature(camera, "OffsetY", cfg.offset_y)
    set_feature(camera, "PixelFormat", cfg.pixel_format)
    set_feature(camera, "Gain", cfg.gain)
    if apply_exposure:
        set_feature(camera, "ExposureTime", cfg.exposure_time)
    set_feature(camera, "BlackLevel", cfg.black_level)

    set_feature(camera, "AcquisitionFrameRateEnable", cfg.enable_acquisition_frame_rate)
    set_feature(camera, "AcquisitionFrameRate", cfg.acquisition_frame_rate)

    set_feature(camera, "TriggerSource", cfg.trigger_source)
    set_feature(camera, "TriggerDelay", cfg.trigger_delay)
    set_feature(camera, "TriggerActivation", cfg.trigger_activation)
    set_feature(camera, "TriggerMode", cfg.trigger_mode)


def _validate_camera_exposure_range(
    camera: object,
    exposure_feature: ResolvedFeature,
    exposure_times_us: Sequence[float],
) -> None:
    minimum, maximum = _feature_min_max(camera, exposure_feature)
    for value in exposure_times_us:
        if minimum is not None and value < minimum:
            raise ValueError(
                f"Exposure time {value:g} us is below camera minimum {minimum:g} us "
                f"({exposure_feature.name})"
            )
        if maximum is not None and value > maximum:
            raise ValueError(
                f"Exposure time {value:g} us is above camera maximum {maximum:g} us "
                f"({exposure_feature.name})"
            )


def configure_fixed_exposure(camera: object, requested_exposure_us: float | None) -> tuple[float, str]:
    exposure = _resolve_feature(
        camera,
        ("ExposureTime", "ExposureTimeAbs"),
        readable=True,
        writable=requested_exposure_us is not None,
        required=True,
        purpose="exposure time node",
    )
    assert exposure is not None
    if requested_exposure_us is not None:
        _validate_camera_exposure_range(camera, exposure, (requested_exposure_us,))
        _set_feature_value(camera, exposure, requested_exposure_us)
    actual = float(_get_feature_value(camera, exposure))
    return actual, exposure.name


@dataclass(frozen=True)
class SequencerConfiguration:
    set_exposure_us: dict[int, float]
    node_names: dict[str, Any]


def _set_first_supported_enum(
    camera: object,
    feature: ResolvedFeature,
    values: Sequence[str],
) -> str:
    errors: list[str] = []
    for value in values:
        try:
            _set_feature_value(camera, feature, value)
            return value
        except Exception as exc:
            errors.append(f"{value}: {exc}")
    raise RuntimeError(
        f"GenICam node {feature.name} accepts none of {list(values)!r}. "
        f"Errors: {'; '.join(errors)}"
    )


def _disable_auto_features(camera: object) -> dict[str, str]:
    auto_nodes: dict[str, str] = {}
    for auto_name in ("ExposureAuto", "GainAuto"):
        auto_feature = _resolve_feature(camera, (auto_name,), writable=True, required=False)
        if auto_feature is not None:
            try:
                _set_feature_value(camera, auto_feature, "Off")
                auto_nodes[auto_name] = auto_feature.name
            except Exception as exc:
                raise RuntimeError(f"Failed to disable {auto_name} before sequencer setup: {exc}") from exc
    return auto_nodes


def _configure_legacy_exposure_sequence(
    camera: object,
    exposure: ResolvedFeature,
    mode: ResolvedFeature,
    exposure_times_us: Sequence[float],
    chunk_selector_values: Sequence[str],
    auto_nodes: dict[str, str],
) -> SequencerConfiguration:
    """Configure legacy Basler Sequence* cameras in automatic advance mode."""
    selector = _resolve_feature(
        camera,
        ("SequenceSetIndex",),
        readable=True,
        writable=True,
        required=True,
        purpose="legacy sequence set index",
    )
    store = _resolve_feature(
        camera,
        ("SequenceSetStore",),
        writable=True,
        required=True,
        purpose="legacy sequence set store command",
    )
    load = _resolve_feature(
        camera,
        ("SequenceSetLoad",),
        writable=True,
        required=True,
        purpose="legacy sequence set load command",
    )
    total = _resolve_feature(
        camera,
        ("SequenceSetTotalNumber",),
        readable=True,
        writable=True,
        required=True,
        purpose="legacy sequence set count",
    )
    advance = _resolve_feature(
        camera,
        ("SequenceAdvanceMode",),
        writable=True,
        required=True,
        purpose="legacy sequence advance mode",
    )
    configuration_mode = _resolve_feature(
        camera,
        ("SequenceConfigurationMode",),
        readable=True,
        writable=True,
        required=False,
    )
    assert all(item is not None for item in (selector, store, load, total, advance))
    _validate_camera_exposure_range(camera, exposure, exposure_times_us)
    selector_min, selector_max = _feature_min_max(camera, selector)
    if selector_min is not None and selector_min > 0:
        raise RuntimeError("Legacy SequenceSetIndex does not expose set 0")
    if selector_max is not None and len(exposure_times_us) - 1 > int(selector_max):
        raise ValueError(
            f"Camera supports legacy sequence set IDs through {int(selector_max)}, "
            f"but {len(exposure_times_us)} exposure values were requested"
        )
    total_min, total_max = _feature_min_max(camera, total)
    if total_min is not None and len(exposure_times_us) < total_min:
        raise ValueError(f"Camera requires at least {int(total_min)} legacy sequence sets")
    if total_max is not None and len(exposure_times_us) > total_max:
        raise ValueError(f"Camera supports at most {int(total_max)} legacy sequence sets")

    set_map: dict[int, float] = {}
    try:
        _set_feature_value(camera, mode, False)
        if configuration_mode is not None:
            _set_feature_value(camera, configuration_mode, "On")
        _set_feature_value(camera, total, len(exposure_times_us))
        _set_first_supported_enum(camera, advance, ("Auto", "Automatic"))
        for set_id, requested_us in enumerate(exposure_times_us):
            _set_feature_value(camera, selector, set_id)
            _set_feature_value(camera, exposure, requested_us)
            actual_us = float(_get_feature_value(camera, exposure))
            executions = _resolve_feature(
                camera,
                ("SequenceSetExecutions",),
                writable=True,
                required=False,
            )
            if executions is not None:
                _set_feature_value(camera, executions, 1)
            _reenable_chunk_selectors(camera, chunk_selector_values)
            _execute_feature(camera, store)
            set_map[set_id] = actual_us
        _set_feature_value(camera, selector, 0)
        _execute_feature(camera, load)
        if configuration_mode is not None:
            _set_feature_value(camera, configuration_mode, "Off")
        _set_feature_value(camera, mode, True)
    except Exception as exc:
        try:
            if configuration_mode is not None:
                _set_feature_value(camera, configuration_mode, "Off")
        except Exception:
            pass
        try:
            _set_feature_value(camera, mode, False)
        except Exception:
            pass
        raise RuntimeError(f"Failed to configure legacy camera exposure sequence before acquisition: {exc}") from exc

    for set_id, actual_us in set_map.items():
        print(f"[SEQUENCER] set={set_id} exposure={actual_us:g} us next={(set_id + 1) % len(set_map)}")
    return SequencerConfiguration(
        set_exposure_us=set_map,
        node_names={
            "backend": "legacy_sequence",
            "mode": mode.name,
            "configuration_mode": configuration_mode.name if configuration_mode is not None else None,
            "set_selector": selector.name,
            "set_save": store.name,
            "set_load": load.name,
            "set_total": total.name,
            "trigger_source": advance.name,
            "trigger_source_value": "Auto",
            "exposure": exposure.name,
            **auto_nodes,
        },
    )


def configure_exposure_sequencer(
    camera: object,
    exposure_times_us: Sequence[float],
    *,
    chunk_selector_values: Sequence[str] = (),
) -> SequencerConfiguration:
    """Configure a camera-side cyclic exposure sequencer.

    ace Classic/U/L USB cameras use path 1 for set advance and FrameStart as
    the per-frame advance signal. Older Sequence* aliases are explored where
    their semantics match; missing transition nodes result in a pre-grab error.
    """
    if not exposure_times_us:
        raise ValueError("exposure_times_us must not be empty")

    # Basler requires Exposure Auto and Gain Auto to be Off before exposure
    # and sequencer nodes become writable. Resolve the required nodes only
    # after disabling those optional auto functions.
    auto_nodes = _disable_auto_features(camera)
    exposure = _resolve_feature(
        camera,
        ("ExposureTime", "ExposureTimeAbs"),
        readable=True,
        writable=True,
        required=True,
        purpose="sequencer exposure node",
    )
    mode = _resolve_feature(
        camera,
        ("SequencerMode", "SequenceEnable"),
        readable=True,
        writable=True,
        required=True,
        purpose="sequencer enable node",
    )
    assert exposure is not None and mode is not None
    if mode.name == "SequenceEnable":
        return _configure_legacy_exposure_sequence(
            camera,
            exposure,
            mode,
            exposure_times_us,
            chunk_selector_values,
            auto_nodes,
        )

    configuration_mode = _resolve_feature(
        camera,
        ("SequencerConfigurationMode",),
        readable=True,
        writable=True,
        required=True,
        purpose="sequencer configuration mode node",
    )
    assert configuration_mode is not None

    # ExposureTime is available before entering sequencer configuration mode,
    # so reject invalid requests without changing the camera mode.
    _validate_camera_exposure_range(camera, exposure, exposure_times_us)

    set_map: dict[int, float] = {}
    trigger_value: str | None = None
    try:
        # On ace Classic USB cameras, the set/path nodes are gated by
        # SequencerConfigurationMode. Resolve them only after entering it.
        _set_feature_value(camera, mode, "Off")
        _set_feature_value(camera, configuration_mode, "On")

        selector = _resolve_feature(
            camera,
            ("SequencerSetSelector",),
            readable=True,
            writable=True,
            required=True,
            purpose="sequencer set selector",
        )
        save_command = _resolve_feature(
            camera,
            ("SequencerSetSave",),
            writable=True,
            required=True,
            purpose="sequencer set save command",
        )
        load_command = _resolve_feature(
            camera,
            ("SequencerSetLoad",),
            writable=True,
            required=True,
            purpose="sequencer set load command",
        )
        path_selector = _resolve_feature(
            camera,
            ("SequencerPathSelector",),
            readable=True,
            writable=True,
            required=True,
            purpose="sequencer path selector",
        )
        set_next = _resolve_feature(
            camera,
            ("SequencerSetNext",),
            readable=True,
            writable=True,
            required=True,
            purpose="sequencer next-set node",
        )
        trigger_source = _resolve_feature(
            camera,
            ("SequencerTriggerSource",),
            writable=True,
            required=True,
            purpose="sequencer trigger source",
        )
        assert all(
            item is not None
            for item in (selector, save_command, load_command, path_selector, set_next, trigger_source)
        )

        selector_min, selector_max = _feature_min_max(camera, selector)
        if selector_min is not None and selector_min > 0:
            raise RuntimeError(f"Sequencer set selector starts at {selector_min:g}; set 0 is unavailable")
        if selector_max is not None and len(exposure_times_us) - 1 > int(selector_max):
            raise ValueError(
                f"Camera supports sequencer set IDs through {int(selector_max)}, "
                f"but {len(exposure_times_us)} exposure values were requested"
            )

        path_min, path_max = _feature_min_max(camera, path_selector)
        advance_path = 1
        if (path_min is not None and path_min > 1) or (path_max is not None and path_max < 1):
            advance_path = 0

        for set_id, requested_us in enumerate(exposure_times_us):
            _set_feature_value(camera, selector, set_id)
            _set_feature_value(camera, exposure, requested_us)
            actual_us = float(_get_feature_value(camera, exposure))
            _set_feature_value(camera, path_selector, advance_path)
            _set_feature_value(camera, set_next, (set_id + 1) % len(exposure_times_us))
            if trigger_value is None:
                trigger_value = _set_first_supported_enum(
                    camera,
                    trigger_source,
                    ("FrameStart", "ExposureStart", "FrameEnd", "Auto"),
                )
            else:
                _set_feature_value(camera, trigger_source, trigger_value)
            activation = _resolve_feature(
                camera,
                ("SequencerTriggerActivation",),
                writable=True,
                required=False,
            )
            if activation is not None:
                try:
                    _set_feature_value(camera, activation, "RisingEdge")
                except Exception:
                    pass
            _reenable_chunk_selectors(camera, chunk_selector_values)
            _execute_feature(camera, save_command)
            set_map[set_id] = actual_us

        start = _resolve_feature(
            camera,
            ("SequencerSetStart",),
            writable=True,
            required=False,
        )
        if start is not None:
            _set_feature_value(camera, start, 0)
        _set_feature_value(camera, selector, 0)
        _execute_feature(camera, load_command)
        _set_feature_value(camera, configuration_mode, "Off")
        _set_feature_value(camera, mode, "On")
    except Exception as exc:
        try:
            _set_feature_value(camera, configuration_mode, "Off")
        except Exception:
            pass
        try:
            _set_feature_value(camera, mode, "Off")
        except Exception:
            pass
        if isinstance(exc, ValueError):
            raise
        raise RuntimeError(f"Failed to configure camera exposure sequencer before acquisition: {exc}") from exc

    for set_id, actual_us in set_map.items():
        print(f"[SEQUENCER] set={set_id} exposure={actual_us:g} us next={(set_id + 1) % len(set_map)}")

    return SequencerConfiguration(
        set_exposure_us=set_map,
        node_names={
            "backend": "sequencer_path",
            "mode": mode.name,
            "configuration_mode": configuration_mode.name,
            "set_selector": selector.name,
            "set_save": save_command.name,
            "set_load": load_command.name,
            "path_selector": path_selector.name,
            "path_index": advance_path,
            "set_next": set_next.name,
            "trigger_source": trigger_source.name,
            "trigger_source_value": trigger_value,
            "exposure": exposure.name,
            **auto_nodes,
        },
    )





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


def _read_grab_chunk_value(result: object, candidates: Sequence[str]) -> Any | None:
    for name in candidates:
        try:
            value = getattr(result, name)
            if hasattr(value, "Value"):
                value = value.Value
            else:
                getter = getattr(value, "GetValue", None)
                if callable(getter):
                    value = getter()
            return value
        except Exception:
            continue
    return None


def estimate_skipped_frames(
    result: object,
    previous_block_id: int | None,
) -> tuple[int, int | None]:
    skipped = 0
    try:
        getter = getattr(result, "GetNumberOfSkippedImages")
        skipped = max(skipped, int(getter()))
    except Exception:
        pass

    block_id: int | None = None
    for name in ("GetBlockID", "BlockID"):
        try:
            value = getattr(result, name)
            block_id = int(value() if callable(value) else value)
            break
        except Exception:
            continue
    if block_id is not None and previous_block_id is not None and block_id > previous_block_id:
        skipped = max(skipped, max(0, block_id - previous_block_id - 1))
    return skipped, block_id if block_id is not None else previous_block_id


def exposure_to_unique_set_id(exposure_us: float, set_exposure_us: dict[int, float]) -> int:
    matches = [
        set_id
        for set_id, registered_us in set_exposure_us.items()
        if math.isclose(
            exposure_us,
            registered_us,
            rel_tol=1e-6,
            abs_tol=max(1e-3, abs(registered_us) * 1e-6),
        )
    ]
    return matches[0] if len(matches) == 1 else UNKNOWN_SEQUENCER_SET_ID


@dataclass(frozen=True)
class FrameRecord:
    image: np.ndarray
    timestamp_camera_us: float
    exposure_time_us: float
    sequencer_set_id: int
    timestamp_source: str
    exposure_source: str
    sequencer_set_source: str


def extract_frame_record(
    result: object,
    *,
    capture_start_monotonic_s: float,
    tick_frequency_hz: float | None,
    exposure_mode: str,
    fixed_exposure_us: float | None,
    set_exposure_us: dict[int, float],
) -> FrameRecord | None:
    if not bool(result.GrabSucceeded()):
        return None

    image = np.asarray(result.Array).copy()
    host_elapsed_us = (time.perf_counter() - capture_start_monotonic_s) * 1_000_000.0

    tick_value = _read_grab_chunk_value(
        result,
        ("ChunkTimestamp", "BslChunkTimestampValue", "ChunkTimestampValue"),
    )
    if tick_value is not None and tick_frequency_hz is not None and tick_frequency_hz > 0:
        timestamp_us = (float(tick_value) / tick_frequency_hz) * 1_000_000.0
        timestamp_source = "camera_chunk_timestamp"
    else:
        timestamp_us = host_elapsed_us
        timestamp_source = "host_perf_counter_fallback"

    chunk_exposure = _read_grab_chunk_value(
        result,
        ("ChunkExposureTime", "ChunkExposureTimeAbs", "BslChunkExposureTime"),
    )
    chunk_set = _read_grab_chunk_value(
        result,
        ("ChunkSequencerSetActive", "ChunkSequenceSetIndex", "ChunkSequencerSetIndex"),
    )
    set_id = UNKNOWN_SEQUENCER_SET_ID
    set_source = "unknown"
    if chunk_set is not None:
        try:
            candidate_set_id = int(chunk_set)
            if exposure_mode != "sequencer" or candidate_set_id in set_exposure_us:
                set_id = candidate_set_id
                set_source = "camera_chunk_sequencer_set"
        except (TypeError, ValueError, OverflowError):
            pass

    if chunk_exposure is not None:
        exposure_us = float(chunk_exposure)
        exposure_source = "camera_chunk_exposure_time"
        if set_id == UNKNOWN_SEQUENCER_SET_ID and exposure_mode == "sequencer":
            set_id = exposure_to_unique_set_id(exposure_us, set_exposure_us)
            if set_id != UNKNOWN_SEQUENCER_SET_ID:
                set_source = "chunk_exposure_unique_match"
    elif set_id != UNKNOWN_SEQUENCER_SET_ID and set_id in set_exposure_us:
        exposure_us = float(set_exposure_us[set_id])
        exposure_source = "sequencer_set_mapping"
    elif exposure_mode == "fixed" and fixed_exposure_us is not None:
        exposure_us = float(fixed_exposure_us)
        exposure_source = "fixed_camera_readback"
    else:
        raise RuntimeError(
            "Successful grab has neither ChunkExposureTime nor a usable sequencer set chunk; "
            "the applied exposure cannot be associated safely without frame-order inference."
        )

    return FrameRecord(
        image=image,
        timestamp_camera_us=float(timestamp_us),
        exposure_time_us=float(exposure_us),
        sequencer_set_id=int(set_id),
        timestamp_source=timestamp_source,
        exposure_source=exposure_source,
        sequencer_set_source=set_source,
    )


@dataclass(frozen=True)
class ChunkPayload:
    start_index: int
    frames: np.ndarray
    timestamps_camera_us: np.ndarray
    exposure_times_us: np.ndarray
    sequencer_set_ids: np.ndarray

    @property
    def count(self) -> int:
        return int(self.frames.shape[0])

    @property
    def end_index(self) -> int:
        return self.start_index + self.count - 1


class FrameBuffer:
    def __init__(self) -> None:
        self.frames: list[np.ndarray] = []
        self.timestamps_camera_us: list[float] = []
        self.exposure_times_us: list[float] = []
        self.sequencer_set_ids: list[int] = []

    def __len__(self) -> int:
        return len(self.frames)

    def append(self, record: FrameRecord) -> None:
        # Append one complete record so all arrays stay aligned.
        self.frames.append(record.image)
        self.timestamps_camera_us.append(record.timestamp_camera_us)
        self.exposure_times_us.append(record.exposure_time_us)
        self.sequencer_set_ids.append(record.sequencer_set_id)

    def take_all(self, start_index: int) -> ChunkPayload:
        count = len(self.frames)
        if count == 0:
            raise ValueError("Cannot create a chunk from an empty frame buffer")
        if not (
            count
            == len(self.timestamps_camera_us)
            == len(self.exposure_times_us)
            == len(self.sequencer_set_ids)
        ):
            raise RuntimeError("Frame buffer image/metadata lengths are inconsistent")
        frames = np.stack(self.frames, axis=0)
        timestamps = np.asarray(self.timestamps_camera_us, dtype=np.float64)
        # Preserve the existing 0.1 ms timestamp file granularity.
        timestamps = np.round(timestamps / 100.0) * 100.0
        exposures = np.asarray(self.exposure_times_us, dtype=np.float64)
        set_ids = np.asarray(self.sequencer_set_ids, dtype=np.int64)
        payload = ChunkPayload(start_index, frames, timestamps, exposures, set_ids)
        self.frames.clear()
        self.timestamps_camera_us.clear()
        self.exposure_times_us.clear()
        self.sequencer_set_ids.clear()
        return payload


def take_full_chunk_if_ready(
    buffer: FrameBuffer,
    frames_per_file: int | None,
    start_index: int,
) -> ChunkPayload | None:
    if frames_per_file is None or len(buffer) < frames_per_file:
        return None
    return buffer.take_all(start_index)


def _atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def _write_npy_temporary(final_path: Path, array: np.ndarray) -> tuple[Path, int]:
    temporary = final_path.with_name(final_path.name + ".tmp")
    with temporary.open("wb") as stream:
        # A file handle prevents np.save from silently adding a .npy suffix.
        np.save(stream, array, allow_pickle=False)
        stream.flush()
        os.fsync(stream.fileno())
    return temporary, temporary.stat().st_size


@dataclass(frozen=True)
class SaveResult:
    start_index: int
    end_index: int
    count: int
    frame_file: str
    timestamp_file: str
    exposure_file: str
    sequencer_set_file: str
    written_bytes: int
    elapsed_s: float


def save_chunk_files(output_dir: Path, payload: ChunkPayload, *, chunked: bool) -> SaveResult:
    if not (
        payload.count
        == len(payload.timestamps_camera_us)
        == len(payload.exposure_times_us)
        == len(payload.sequencer_set_ids)
    ):
        raise RuntimeError("Chunk image/metadata lengths are inconsistent")

    if chunked:
        suffix = f"_{payload.start_index:08d}_{payload.end_index:08d}.npy"
        names = {
            "frames": "frames" + suffix,
            "timestamps": "timestamps_camera_us" + suffix,
            "exposure": "exposure_times_us" + suffix,
            "set": "sequencer_set_ids" + suffix,
        }
    else:
        names = {
            "frames": "frames.npy",
            "timestamps": "timestamps_camera_us.npy",
            "exposure": "exposure_times_us.npy",
            "set": "sequencer_set_ids.npy",
        }

    arrays = {
        "timestamps": payload.timestamps_camera_us,
        "exposure": payload.exposure_times_us,
        "set": payload.sequencer_set_ids,
        "frames": payload.frames,
    }
    started = time.perf_counter()
    temporary_files: dict[str, Path] = {}
    written_bytes = 0
    for key in ("timestamps", "exposure", "set", "frames"):
        temporary, byte_count = _write_npy_temporary(output_dir / names[key], arrays[key])
        temporary_files[key] = temporary
        written_bytes += byte_count

    # Metadata arrays become visible first. frames_*.npy is the completion marker
    # used by readers, so an interrupted group is never mistaken for a full chunk.
    for key in ("timestamps", "exposure", "set", "frames"):
        os.replace(temporary_files[key], output_dir / names[key])
    elapsed_s = time.perf_counter() - started
    speed_mib_s = written_bytes / (1024**2) / elapsed_s if elapsed_s > 0 else math.inf
    size_gib = written_bytes / (1024**3)
    print(
        f"[SAVE] frames={payload.start_index}-{payload.end_index}\n"
        f"       file={names['frames']}\n"
        f"       count={payload.count}\n"
        f"       size={size_gib:.2f} GiB\n"
        f"       elapsed={elapsed_s:.2f} s\n"
        f"       speed={speed_mib_s:.0f} MiB/s"
    )
    return SaveResult(
        start_index=payload.start_index,
        end_index=payload.end_index,
        count=payload.count,
        frame_file=names["frames"],
        timestamp_file=names["timestamps"],
        exposure_file=names["exposure"],
        sequencer_set_file=names["set"],
        written_bytes=written_bytes,
        elapsed_s=elapsed_s,
    )


@dataclass
class CaptureSnapshot:
    captured_frames: int
    saved_frames: int
    saved_chunks: int
    last_saved_frame_index: int | None
    written_bytes: int
    dropped_frames: int
    frame_shape: list[int] | None
    frame_dtype: str | None
    frame_files: list[str]
    timestamp_files: list[str]
    exposure_files: list[str]
    sequencer_set_files: list[str]


class CaptureStats:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.captured_frames = 0
        self.saved_frames = 0
        self.saved_chunks = 0
        self.last_saved_frame_index: int | None = None
        self.written_bytes = 0
        self.dropped_frames = 0
        self.frame_shape: list[int] | None = None
        self.frame_dtype: str | None = None
        self.frame_files: list[str] = []
        self.timestamp_files: list[str] = []
        self.exposure_files: list[str] = []
        self.sequencer_set_files: list[str] = []

    def record_capture(self, image: np.ndarray) -> None:
        with self._lock:
            self.captured_frames += 1
            if self.frame_shape is None:
                self.frame_shape = list(image.shape)
                self.frame_dtype = str(image.dtype)

    def record_drop(self, count: int = 1) -> None:
        with self._lock:
            self.dropped_frames += max(0, int(count))

    def record_save(self, result: SaveResult) -> None:
        with self._lock:
            self.saved_frames += result.count
            self.saved_chunks += 1
            self.last_saved_frame_index = result.end_index
            self.written_bytes += result.written_bytes
            self.frame_files.append(result.frame_file)
            self.timestamp_files.append(result.timestamp_file)
            self.exposure_files.append(result.exposure_file)
            self.sequencer_set_files.append(result.sequencer_set_file)

    def snapshot(self) -> CaptureSnapshot:
        with self._lock:
            return CaptureSnapshot(
                captured_frames=self.captured_frames,
                saved_frames=self.saved_frames,
                saved_chunks=self.saved_chunks,
                last_saved_frame_index=self.last_saved_frame_index,
                written_bytes=self.written_bytes,
                dropped_frames=self.dropped_frames,
                frame_shape=list(self.frame_shape) if self.frame_shape is not None else None,
                frame_dtype=self.frame_dtype,
                frame_files=list(self.frame_files),
                timestamp_files=list(self.timestamp_files),
                exposure_files=list(self.exposure_files),
                sequencer_set_files=list(self.sequencer_set_files),
            )


def format_capture_summary(status: str, snapshot: CaptureSnapshot, elapsed_s: float) -> str:
    average_fps = snapshot.captured_frames / elapsed_s if elapsed_s > 0 else 0.0
    return (
        "[SUMMARY]\n"
        f"status={status}\n"
        f"captured_frames={snapshot.captured_frames}\n"
        f"saved_frames={snapshot.saved_frames}\n"
        f"elapsed={elapsed_s:.1f} s\n"
        f"average_fps={average_fps:.2f}\n"
        f"saved_chunks={snapshot.saved_chunks}\n"
        f"written={snapshot.written_bytes / (1024**3):.2f} GiB\n"
        f"dropped_frames={snapshot.dropped_frames}"
    )


def captured_saved_mismatch_warning(snapshot: CaptureSnapshot) -> str | None:
    if snapshot.captured_frames == snapshot.saved_frames:
        return None
    return (
        "[WARN] Captured/saved frame mismatch: "
        f"captured={snapshot.captured_frames}, saved={snapshot.saved_frames}"
    )


class MetadataManager:
    def __init__(self, path: Path, initial: dict[str, Any]) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._data = dict(initial)
        _atomic_write_json(self.path, self._data)

    def update(self, values: dict[str, Any]) -> None:
        with self._lock:
            self._data.update(values)
            _atomic_write_json(self.path, self._data)

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return dict(self._data)


def _stats_metadata_values(
    stats: CaptureStats,
    capture_start_monotonic_s: float | None,
) -> dict[str, Any]:
    snapshot = stats.snapshot()
    elapsed_s = (
        max(0.0, time.perf_counter() - capture_start_monotonic_s)
        if capture_start_monotonic_s is not None
        else 0.0
    )
    shape = (
        [snapshot.captured_frames, *snapshot.frame_shape]
        if snapshot.frame_shape is not None
        else None
    )
    return {
        "frame_count_captured": snapshot.captured_frames,
        "frame_count_saved": snapshot.saved_frames,
        "chunk_count_saved": snapshot.saved_chunks,
        "last_saved_frame_index": snapshot.last_saved_frame_index,
        "written_bytes": snapshot.written_bytes,
        "dropped_frames": snapshot.dropped_frames,
        "capture_elapsed_s": float(elapsed_s),
        "shape": shape,
        "dtype": snapshot.frame_dtype,
        "frame_files": snapshot.frame_files,
        "timestamp_files": snapshot.timestamp_files,
        "exposure_time_files": snapshot.exposure_files,
        "sequencer_set_id_files": snapshot.sequencer_set_files,
    }


@dataclass(frozen=True)
class ProgressEstimate:
    percent: float | None
    eta_s: float | None
    limiting_condition: str | None


def calculate_progress(
    *,
    captured_frames: int,
    elapsed_s: float,
    frame_count: int | None,
    measurement_duration_s: float | None,
) -> ProgressEstimate:
    fps = captured_frames / elapsed_s if elapsed_s > 0 else 0.0
    fractions: list[tuple[str, float]] = []
    etas: list[tuple[str, float]] = []
    if frame_count is not None:
        fractions.append(("frame_count", min(1.0, captured_frames / frame_count)))
        if fps > 0:
            etas.append(("frame_count", max(0.0, (frame_count - captured_frames) / fps)))
    if measurement_duration_s is not None:
        fractions.append(("duration", min(1.0, elapsed_s / measurement_duration_s)))
        etas.append(("duration", max(0.0, measurement_duration_s - elapsed_s)))
    # Capture stops on the first reached condition, so the most advanced
    # fraction and shortest ETA describe the effective stop condition.
    percent = max(value for _, value in fractions) * 100.0 if fractions else None
    if not etas:
        return ProgressEstimate(percent, None, None)
    limiting_condition, eta_s = min(etas, key=lambda pair: pair[1])
    return ProgressEstimate(percent, eta_s, limiting_condition)


class ProgressReporter:
    def __init__(
        self,
        cfg: CaptureConfig,
        stats: CaptureStats,
        capture_start_monotonic_s: float,
        *,
        printer: Callable[[str], None] = print,
    ) -> None:
        self.cfg = cfg
        self.stats = stats
        self.capture_start_monotonic_s = capture_start_monotonic_s
        self.next_report_s = capture_start_monotonic_s + cfg.progress_interval_s
        self.printer = printer

    def maybe_report(
        self,
        *,
        now_s: float | None = None,
        frame_buffer_count: int,
        queue_size: int,
        queue_capacity: int,
        force: bool = False,
    ) -> bool:
        now_s = time.perf_counter() if now_s is None else now_s
        if not force and now_s < self.next_report_s:
            return False
        elapsed_s = max(0.0, now_s - self.capture_start_monotonic_s)
        snapshot = self.stats.snapshot()
        fps = snapshot.captured_frames / elapsed_s if elapsed_s > 0 else 0.0
        estimate = calculate_progress(
            captured_frames=snapshot.captured_frames,
            elapsed_s=elapsed_s,
            frame_count=self.cfg.frame_count,
            measurement_duration_s=self.cfg.measurement_duration_s,
        )
        progress_text = f"{estimate.percent:.1f}%" if estimate.percent is not None else "n/a"
        eta_text = f"{estimate.eta_s:.1f}s" if estimate.eta_s is not None else "n/a"
        self.printer(
            "[PROGRESS] "
            f"captured={snapshot.captured_frames} saved={snapshot.saved_frames} "
            f"elapsed={elapsed_s:.1f}s fps={fps:.2f} chunks={snapshot.saved_chunks} "
            f"written={snapshot.written_bytes / (1024**3):.2f}GiB "
            f"buffer={frame_buffer_count} queue={queue_size}/{queue_capacity} "
            f"dropped={snapshot.dropped_frames} progress={progress_text} eta={eta_text} "
            f"limit={estimate.limiting_condition or 'n/a'}"
        )
        self.next_report_s = now_s + self.cfg.progress_interval_s
        return True


class AsyncChunkWriter:
    _SENTINEL = object()

    def __init__(
        self,
        output_dir: Path,
        stats: CaptureStats,
        on_saved: Callable[[], None],
        *,
        max_queue_chunks: int = WRITE_QUEUE_MAX_CHUNKS,
        put_timeout_s: float = WRITE_QUEUE_PUT_TIMEOUT_S,
    ) -> None:
        if max_queue_chunks <= 0:
            raise ValueError("max_queue_chunks must be > 0")
        self.output_dir = output_dir
        self.stats = stats
        self.on_saved = on_saved
        self.put_timeout_s = put_timeout_s
        self.queue: queue.Queue[ChunkPayload | object] = queue.Queue(maxsize=max_queue_chunks)
        self._error_lock = threading.Lock()
        self._error: BaseException | None = None
        self._closed = False
        self._thread = threading.Thread(target=self._run, name="npy-chunk-writer", daemon=False)
        self._thread.start()

    @property
    def capacity(self) -> int:
        return self.queue.maxsize

    def _set_error(self, exc: BaseException) -> None:
        with self._error_lock:
            if self._error is None:
                self._error = exc

    def raise_if_failed(self) -> None:
        with self._error_lock:
            error = self._error
        if error is not None:
            raise RuntimeError(f"Chunk writer failed: {error}") from error

    def submit(self, payload: ChunkPayload) -> None:
        if self._closed:
            raise RuntimeError("Chunk writer is already closed")
        self.raise_if_failed()
        try:
            self.queue.put_nowait(payload)
        except queue.Full:
            print(
                f"[WARN] Write queue is full ({self.queue.qsize()}/{self.capacity}); "
                f"waiting up to {self.put_timeout_s:g}s without dropping frames."
            )
            try:
                self.queue.put(payload, timeout=self.put_timeout_s)
            except queue.Full as exc:
                raise RuntimeError(
                    "Write queue remained full; acquisition is stopping rather than silently dropping a chunk"
                ) from exc
        self.raise_if_failed()

    def _run(self) -> None:
        while True:
            item = self.queue.get()
            try:
                if item is self._SENTINEL:
                    return
                with self._error_lock:
                    already_failed = self._error is not None
                if already_failed:
                    continue
                assert isinstance(item, ChunkPayload)
                result = save_chunk_files(self.output_dir, item, chunked=True)
                self.stats.record_save(result)
                self.on_saved()
            except BaseException as exc:
                self._set_error(exc)
            finally:
                self.queue.task_done()

    def close(self) -> None:
        if self._closed:
            self.raise_if_failed()
            return
        self._closed = True
        while True:
            try:
                self.queue.put(self._SENTINEL, timeout=0.1)
                break
            except queue.Full:
                if not self._thread.is_alive():
                    raise RuntimeError("Chunk writer thread stopped while its queue was full")
        self.queue.join()
        self._thread.join(timeout=10.0)
        if self._thread.is_alive():
            raise RuntimeError("Chunk writer thread did not stop cleanly")
        self.raise_if_failed()

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
    exposure_plan = validate_capture_config(cfg)
    output_dir = Path(output_override or cfg.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if pylon is None:
        raise RuntimeError("pypylon is required for camera capture but is not installed")

    stats = CaptureStats()
    buffer = FrameBuffer()
    metadata_manager: MetadataManager | None = None
    writer: AsyncChunkWriter | None = None
    camera: Any | None = None
    capture_start_monotonic_s: float | None = None
    capture_start_unix_s: float | None = None
    status = "failed"
    fatal_error: BaseException | None = None
    pending_payloads: list[ChunkPayload] = []
    next_frame_index = 0

    try:
        tl_factory = pylon.TlFactory.GetInstance()
        devices = tl_factory.EnumerateDevices()
        if not devices:
            raise RuntimeError("No Basler camera detected.")
        if cfg.camera_index >= len(devices):
            raise IndexError(f"camera_index={cfg.camera_index} is out of range (detected: {len(devices)})")

        camera = pylon.InstantCamera(tl_factory.CreateDevice(devices[cfg.camera_index]))
        camera.Open()
        pre_disabled_auto_nodes = _disable_auto_features(camera)
        apply_camera_settings(camera, cfg, apply_exposure=False)
        camera_identity = get_camera_identity(camera)
        fixed_exposure_us: float | None = None
        sequencer_configuration: SequencerConfiguration | None = None
        genicam_nodes: dict[str, Any] = dict(pre_disabled_auto_nodes)

        if exposure_plan.mode == "fixed":
            requested_fixed = exposure_plan.requested_times_us[0] if exposure_plan.requested_times_us else None
            fixed_exposure_us, exposure_node_name = configure_fixed_exposure(camera, requested_fixed)
            actual_exposure_sequence = [fixed_exposure_us]
            set_exposure_us: dict[int, float] = {}
            genicam_nodes["exposure"] = exposure_node_name
            chunk_capabilities = configure_chunk_data(camera)
        else:
            chunk_capabilities = configure_chunk_data(camera)
            if not chunk_capabilities.exposure_enabled and not chunk_capabilities.sequencer_set_enabled:
                raise RuntimeError(
                    "Sequencer capture requires ChunkExposureTime or ChunkSequencerSetActive/"
                    "ChunkSequenceSetIndex. This camera exposes neither, so frame/exposure "
                    "association cannot be guaranteed after a failed or dropped grab."
                )
            sequencer_configuration = configure_exposure_sequencer(
                camera,
                exposure_plan.requested_times_us,
                chunk_selector_values=chunk_capabilities.enabled_selector_values,
            )
            set_exposure_us = dict(sequencer_configuration.set_exposure_us)
            actual_exposure_sequence = [set_exposure_us[index] for index in sorted(set_exposure_us)]
            genicam_nodes.update(sequencer_configuration.node_names)

        genicam_nodes["chunk_mode"] = "ChunkModeActive" if chunk_capabilities.enabled_selector_values else None
        genicam_nodes["chunk_selectors"] = dict(chunk_capabilities.selector_names)

        # Reset camera internal timestamp counter if supported, then start immediately.
        timestamp_reset_done = try_execute_command(camera, "GevTimestampControlReset")
        if not timestamp_reset_done:
            timestamp_reset_done = try_execute_command(camera, "TimestampReset")

        tick_frequency_hz = get_timestamp_tick_frequency_hz(camera, camera_identity.get("model_name"))
        timestamp_source = (
            "camera_chunk_timestamp"
            if chunk_capabilities.timestamp_enabled and tick_frequency_hz is not None
            else "host_perf_counter_fallback"
        )
        metadata = {
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
            "timestamp_files": [],
            "exposure_time_files": [],
            "sequencer_set_id_files": [],
            "frames_per_file": cfg.frames_per_file,
            "storage_format": "chunked" if cfg.frames_per_file is not None else "single_file",
            "write_queue_max_chunks": WRITE_QUEUE_MAX_CHUNKS if cfg.frames_per_file is not None else 0,
            "camera_index": cfg.camera_index,
            "timeout_ms": cfg.timeout_ms,
            "capture_start_unix_s": None,
            "capture_elapsed_s": 0.0,
            "camera_identity": camera_identity,
            "camera_serial_number": camera_identity.get("serial_number"),
            "camera_model": camera_identity.get("model_name"),
            "camera_vendor": camera_identity.get("vendor_name"),
            "exposure_mode": exposure_plan.mode,
            "exposure_sequence_us": actual_exposure_sequence,
            "exposure_sequence_requested_us": list(exposure_plan.requested_times_us),
            "sequencer_enabled": exposure_plan.mode == "sequencer",
            "sequencer_set_count": len(actual_exposure_sequence) if exposure_plan.mode == "sequencer" else 0,
            "sequencer_set_exposure_us": {str(key): value for key, value in set_exposure_us.items()},
            "unknown_sequencer_set_id": UNKNOWN_SEQUENCER_SET_ID,
            "capture_status": "in_progress",
            "genicam_nodes": genicam_nodes,
            "chunk_data": {
                "timestamp_enabled": chunk_capabilities.timestamp_enabled,
                "exposure_enabled": chunk_capabilities.exposure_enabled,
                "sequencer_set_enabled": chunk_capabilities.sequencer_set_enabled,
                "selectors": dict(chunk_capabilities.selector_names),
            },
            "timestamp": {
                "source": timestamp_source,
                "camera_timestamp_reset_done": timestamp_reset_done,
                "tick_frequency_hz": tick_frequency_hz,
                "camera_us_note": (
                    "Camera ticks are converted only when tick_frequency_hz is known. Otherwise the host "
                    "perf_counter is used; raw ticks are never mislabeled as microseconds. Values are "
                    "quantized to 100 us (0.1 ms)."
                ),
            },
            "config": asdict(cfg),
        }
        metadata_manager = MetadataManager(output_dir / "metadata.json", metadata)

        def update_metadata_after_save() -> None:
            assert metadata_manager is not None
            metadata_manager.update(_stats_metadata_values(stats, capture_start_monotonic_s))

        if cfg.frames_per_file is not None:
            writer = AsyncChunkWriter(output_dir, stats, update_metadata_after_save)

        # Start acquisition now: measurement starts at this line.
        camera.StartGrabbing(pylon.GrabStrategy_OneByOne, pylon.GrabLoop_ProvidedByUser)
        capture_start_monotonic_s = time.perf_counter()
        capture_start_unix_s = time.time()
        metadata_manager.update({"capture_start_unix_s": capture_start_unix_s})
        reporter = ProgressReporter(cfg, stats, capture_start_monotonic_s)
        previous_block_id: int | None = None

        try:
            while camera.IsGrabbing():
                snapshot = stats.snapshot()
                if should_stop_capture(cfg, capture_start_monotonic_s, snapshot.captured_frames):
                    break

                result = camera.RetrieveResult(cfg.timeout_ms, pylon.TimeoutHandling_ThrowException)
                try:
                    skipped_count, previous_block_id = estimate_skipped_frames(result, previous_block_id)
                    if skipped_count > 0:
                        stats.record_drop(skipped_count)
                    record = extract_frame_record(
                        result,
                        capture_start_monotonic_s=capture_start_monotonic_s,
                        tick_frequency_hz=tick_frequency_hz,
                        exposure_mode=exposure_plan.mode,
                        fixed_exposure_us=fixed_exposure_us,
                        set_exposure_us=set_exposure_us,
                    )
                    if record is None:
                        stats.record_drop()
                    else:
                        buffer.append(record)
                        stats.record_capture(record.image)
                        payload = take_full_chunk_if_ready(buffer, cfg.frames_per_file, next_frame_index)
                        if payload is not None:
                            pending_payloads.append(payload)
                            assert writer is not None
                            writer.submit(payload)
                            pending_payloads.pop()
                            next_frame_index = payload.end_index + 1
                finally:
                    result.Release()

                if writer is not None:
                    writer.raise_if_failed()
                    queue_size = writer.queue.qsize()
                    queue_capacity = writer.capacity
                else:
                    queue_size = 0
                    queue_capacity = 0
                reporter.maybe_report(
                    frame_buffer_count=len(buffer),
                    queue_size=queue_size,
                    queue_capacity=queue_capacity,
                )
            status = "completed"
        except KeyboardInterrupt:
            status = "interrupted"
            print("[INFO] Capture interrupted by user; flushing completed frame buffers.")
        except BaseException as exc:
            status = "failed"
            fatal_error = exc
    finally:
        if camera is not None:
            try:
                if camera.IsGrabbing():
                    camera.StopGrabbing()
            except Exception:
                pass

        # Flush every complete successful frame still held in memory.
        if metadata_manager is not None and len(buffer) > 0:
            try:
                payload = buffer.take_all(next_frame_index)
                if writer is not None:
                    pending_payloads.append(payload)
                    writer.submit(payload)
                    pending_payloads.pop()
                else:
                    save_result = save_chunk_files(output_dir, payload, chunked=False)
                    stats.record_save(save_result)
                    metadata_manager.update(_stats_metadata_values(stats, capture_start_monotonic_s))
            except BaseException as exc:
                status = "failed"
                if fatal_error is None:
                    fatal_error = exc
                else:
                    print(f"[WARN] Additional error while flushing final frame buffer: {exc}")

        if writer is not None:
            try:
                writer.close()
            except BaseException as exc:
                status = "failed"
                if fatal_error is None:
                    fatal_error = exc
                else:
                    print(f"[WARN] Additional chunk writer shutdown error: {exc}")

        # A payload that could not enter a full queue is retained and attempted
        # synchronously after the worker has drained earlier chunks.
        for payload in pending_payloads:
            try:
                result = save_chunk_files(output_dir, payload, chunked=True)
                stats.record_save(result)
            except BaseException as exc:
                status = "failed"
                if fatal_error is None:
                    fatal_error = exc
                else:
                    print(f"[WARN] Additional synchronous chunk save error: {exc}")

        final_snapshot = stats.snapshot()
        if status == "completed" and final_snapshot.captured_frames == 0:
            status = "failed"
            fatal_error = RuntimeError("No frames captured.")

        if metadata_manager is not None:
            final_values = _stats_metadata_values(stats, capture_start_monotonic_s)
            final_values["capture_status"] = status
            final_values["capture_error"] = str(fatal_error) if fatal_error is not None else None
            try:
                metadata_manager.update(final_values)
            except BaseException as exc:
                status = "failed"
                if fatal_error is None:
                    fatal_error = exc
                print(f"[WARN] Failed to write final metadata.json: {exc}")

        final_snapshot = stats.snapshot()
        elapsed_s = (
            max(0.0, time.perf_counter() - capture_start_monotonic_s)
            if capture_start_monotonic_s is not None
            else 0.0
        )
        print(format_capture_summary(status, final_snapshot, elapsed_s))
        mismatch_warning = captured_saved_mismatch_warning(final_snapshot)
        if mismatch_warning is not None:
            print(mismatch_warning)

        if camera is not None:
            try:
                if camera.IsOpen():
                    camera.Close()
            except Exception:
                pass

    if fatal_error is not None:
        raise fatal_error
    return output_dir



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
