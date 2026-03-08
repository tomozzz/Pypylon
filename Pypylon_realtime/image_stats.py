from __future__ import annotations

import numpy as np


def _integral_image(arr: np.ndarray) -> np.ndarray:
    return np.pad(arr.cumsum(axis=0).cumsum(axis=1), ((1, 0), (1, 0)), mode="constant")


def box_mean(arr: np.ndarray, window: int) -> np.ndarray:
    if window < 1:
        raise ValueError("window must be >= 1")
    h, w = arr.shape
    pad = window // 2
    arr_pad = np.pad(arr, ((pad, pad), (pad, pad)), mode="reflect")
    ii = _integral_image(arr_pad)
    out = (
        ii[window:, window:]
        - ii[:-window, window:]
        - ii[window:, :-window]
        + ii[:-window, :-window]
    ) / float(window * window)
    return out[:h, :w]


def local_std(arr: np.ndarray, window: int) -> np.ndarray:
    mean = box_mean(arr, window)
    mean2 = box_mean(arr * arr, window)
    var = np.maximum(mean2 - mean * mean, 0.0)
    return np.sqrt(var)


def erode_valid_mask(mask: np.ndarray, window: int) -> np.ndarray:
    pad = int(np.ceil(window / 2.0))
    out = mask.copy()
    out[:pad, :] = False
    out[-pad:, :] = False
    out[:, :pad] = False
    out[:, -pad:] = False
    return out
