from __future__ import annotations

import json
from pathlib import Path


def _load_db() -> dict:
    db_path = Path(__file__).with_name("actual_gain_db.json")
    return json.loads(db_path.read_text(encoding="utf-8"))


def _convert_gain(gain_db: float, nbits: int, sat_capacity_e: float) -> float:
    g0 = (2 ** nbits) / sat_capacity_e
    return (10 ** (gain_db / 20.0)) * g0


def _resolve_model_capacity(model: str | None, db: dict) -> float | None:
    if not model:
        return None
    capacities = db.get("model_saturation_capacity_e", {})
    aliases = db.get("model_aliases", {})

    if model in capacities:
        return float(capacities[model])

    for canonical, alias_list in aliases.items():
        if model == canonical or model in alias_list:
            cap = capacities.get(canonical)
            return None if cap is None else float(cap)
    return None


def _from_anchor(actual_at_ref: float, gain_db: float, ref_gain_db: float) -> float:
    return actual_at_ref * (10 ** ((gain_db - ref_gain_db) / 20.0))


def _eq_gain(gain_db: float, target: float) -> bool:
    return abs(gain_db - target) < 1e-9


def _from_serial_calibration(serial_number: str | None, nbits: int, gain_db: float, db: dict) -> float | None:
    """Match Matlab GetActualGain branching behavior.

    Important: several cameras only define specific gain branches.
    For those, non-matching gains return None and caller may fallback to model-based conversion.
    """
    if not serial_number:
        return None

    serial_db = db.get("serial_number_calibrations", {}).get(serial_number)
    if not serial_db:
        return None

    bit_db = serial_db.get(str(nbits))
    if not bit_db:
        return None

    # Matlab case '40335410'
    if serial_number == "40335410":
        if nbits == 12:
            # Matlab has explicit 16/20/24 and otherwise uses 24dB anchor.
            return _from_anchor(actual_at_ref=5.8617, gain_db=gain_db, ref_gain_db=24.0)
        if nbits == 8:
            return _from_anchor(actual_at_ref=0.146, gain_db=gain_db, ref_gain_db=16.0)
        return None

    # Matlab case '24828238'
    if serial_number == "24828238":
        if nbits == 12:
            if _eq_gain(gain_db, 8.0):
                return _from_anchor(0.914227869406958, gain_db, 8.0)
            if _eq_gain(gain_db, 16.0):
                return _from_anchor(2.310091349580211, gain_db, 16.0)
            if _eq_gain(gain_db, 24.0):
                return _from_anchor(5.806579358327972, gain_db, 24.0)
            return None
        if nbits == 8:
            if _eq_gain(gain_db, 20.0):
                return _from_anchor(0.230528769675060, gain_db, 36.0)
            if _eq_gain(gain_db, 36.0):
                return _from_anchor(1.468687685052209, gain_db, 36.0)
            return None
        return None

    # Matlab case '25268932'
    if serial_number == "25268932":
        if nbits == 12 and _eq_gain(gain_db, 8.0):
            return _from_anchor(0.919622547325621, gain_db, 8.0)
        if nbits == 12 and _eq_gain(gain_db, 16.0):
            return _from_anchor(2.292981165322791, gain_db, 16.0)
        return None

    # Matlab case '25268933'
    if serial_number == "25268933":
        if nbits == 12 and _eq_gain(gain_db, 8.0):
            return _from_anchor(0.913958659880829, gain_db, 8.0)
        if nbits == 12 and _eq_gain(gain_db, 16.0):
            return _from_anchor(2.291581725766085, gain_db, 16.0)
        return None

    # Matlab case '25268934'
    if serial_number == "25268934":
        if nbits == 12 and _eq_gain(gain_db, 8.0):
            return _from_anchor(0.909228222449580, gain_db, 8.0)
        if nbits == 12 and _eq_gain(gain_db, 16.0):
            return _from_anchor(2.254590311763096, gain_db, 16.0)
        return None

    # Matlab case '40335401'
    if serial_number == "40335401" and nbits == 8:
        return _from_anchor(actual_at_ref=0.0238, gain_db=gain_db, ref_gain_db=0.0)

    # Matlab case '40513592'
    if serial_number == "40513592" and nbits == 10:
        return _from_anchor(actual_at_ref=0.5846, gain_db=gain_db, ref_gain_db=16.0)

    # Generic anchor fallback only when no special Matlab branch above exists.
    if "anchor_gain_db" in bit_db and "anchor_actual_gain_du_per_e" in bit_db:
        ref_gain = float(bit_db["anchor_gain_db"])
        ref_actual = float(bit_db["anchor_actual_gain_du_per_e"])
        return _from_anchor(ref_actual, gain_db, ref_gain)

    return None


def estimate_actual_gain_du_per_e(
    *,
    gain_db: float,
    nbits: int,
    serial_number: str | None,
    model_name: str | None,
) -> tuple[float, str]:
    """Estimate DU/e from gain dB and camera identity.

    Returns:
        (actual_gain_du_per_e, source)
        source is one of:
        - "serial_calibration"
        - "model_capacity_calculation"
    """
    db = _load_db()

    by_serial = _from_serial_calibration(serial_number=serial_number, nbits=nbits, gain_db=gain_db, db=db)
    if by_serial is not None:
        return by_serial, "serial_calibration"

    sat_capacity = _resolve_model_capacity(model_name, db)
    if sat_capacity is None:
        raise ValueError(
            "actual_gain_du_per_eを自動算出できませんでした。"
            "対応するcamera serial/modelがDBにないため、"
            "configでactual_gain_du_per_eを指定してください。"
        )
    return _convert_gain(gain_db=gain_db, nbits=nbits, sat_capacity_e=sat_capacity), "model_capacity_calculation"
