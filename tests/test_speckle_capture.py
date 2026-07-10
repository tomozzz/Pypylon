from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

import numpy as np


def _load_capture_module():
    """Load the capture module without requiring the pypylon wheel."""
    genicam = types.ModuleType("pypylon.genicam")
    genicam.IsWritable = lambda node: bool(getattr(node, "writable", True))
    genicam.IsReadable = lambda node: bool(getattr(node, "readable", True))
    pylon = types.ModuleType("pypylon.pylon")
    package = types.ModuleType("pypylon")
    package.genicam = genicam
    package.pylon = pylon
    sys.modules.setdefault("pypylon", package)
    sys.modules.setdefault("pypylon.genicam", genicam)
    sys.modules.setdefault("pypylon.pylon", pylon)

    path = Path(__file__).parents[1] / "speckle_capture" / "speckle_capture.py"
    spec = importlib.util.spec_from_file_location("speckle_capture_under_test", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


sc = _load_capture_module()


class FakeFeature:
    def __init__(self, value=None, minimum=10.0, maximum=1_000_000.0):
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.writable = True
        self.readable = True

    def SetValue(self, value):
        self.value = value

    def GetValue(self):
        return self.value

    def GetMin(self):
        return self.minimum

    def GetMax(self):
        return self.maximum


class FakeCommand(FakeFeature):
    def __init__(self, callback=None):
        super().__init__()
        self.callback = callback

    def Execute(self):
        if self.callback:
            self.callback()


class FakeNodeMap:
    def __init__(self, camera):
        self.camera = camera

    def GetNode(self, name):
        return getattr(self.camera, name, None)


class FakeSequencerCamera:
    def __init__(self):
        self.saved_sets = []
        for name, value in {
            "SequencerMode": "Off",
            "SequencerConfigurationMode": "Off",
            "SequencerSetSelector": 0,
            "SequencerPathSelector": 0,
            "SequencerTriggerSource": "",
            "SequencerSetNext": 0,
            "ExposureTime": 1000.0,
        }.items():
            setattr(self, name, FakeFeature(value))
        self.SequencerSetSelector.minimum = 0
        self.SequencerSetSelector.maximum = 31
        self.SequencerSetSave = FakeCommand(self._save)
        self.SequencerSetLoad = FakeCommand()

    def GetNodeMap(self):
        return FakeNodeMap(self)

    def _save(self):
        self.saved_sets.append(
            {
                "set": self.SequencerSetSelector.value,
                "exposure": self.ExposureTime.value,
                "path": self.SequencerPathSelector.value,
                "trigger": self.SequencerTriggerSource.value,
                "next": self.SequencerSetNext.value,
            }
        )


def make_chunk(start, count, split=True):
    frames = np.arange(count * 6, dtype=np.uint16).reshape(count, 2, 3)
    return sc.FrameChunk(
        start_index=start,
        frames=frames,
        timestamps_camera_us=np.arange(start, start + count, dtype=float) * 100.0,
        exposure_times_us=np.where(np.arange(count) % 2 == 0, 1000.0, 10000.0),
        sequencer_set_ids=np.arange(count, dtype=np.int64) % 2,
        split_files=split,
    )


class ConfigTests(unittest.TestCase):
    def test_load_fixed_exposure_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_text(
                "output_dir: ./out\nframe_count: 4\nexposure_time: 1000.0\n",
                encoding="utf-8",
            )
            cfg = sc.load_config(path)
            self.assertEqual(sc.resolve_exposure_request(cfg), ("fixed", [1000.0]))

    def test_load_multiple_exposure_config_and_precedence(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_text(
                "output_dir: ./out\nframe_count: 4\nexposure_time: 5\n"
                "exposure_times_us: [1000.0, 10000.0]\n",
                encoding="utf-8",
            )
            cfg = sc.load_config(path)
            with contextlib.redirect_stdout(io.StringIO()) as output:
                mode, values = sc.resolve_exposure_request(cfg)
            self.assertEqual((mode, values), ("sequencer", [1000.0, 10000.0]))
            self.assertIn("takes precedence", output.getvalue())

    def test_invalid_exposure_arrays(self):
        invalid = ([], [0], [-1], [float("nan")], [float("inf")], "1000")
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    sc.validate_exposure_times(value)
        with self.assertRaisesRegex(ValueError, "below the camera minimum"):
            sc.validate_exposure_times([9], 10, 100)
        with self.assertRaisesRegex(ValueError, "above the camera maximum"):
            sc.validate_exposure_times([101], 10, 100)


class SequencerTests(unittest.TestCase):
    def test_configure_cyclic_frame_start_sequencer(self):
        camera = FakeSequencerCamera()
        with contextlib.redirect_stdout(io.StringIO()):
            mapping = sc.configure_exposure_sequencer(camera, [1000.0, 10000.0, 2500.0])
        self.assertEqual(mapping, {0: 1000.0, 1: 10000.0, 2: 2500.0})
        self.assertEqual([entry["next"] for entry in camera.saved_sets], [1, 2, 0])
        self.assertTrue(all(entry["path"] == 1 for entry in camera.saved_sets))
        self.assertTrue(all(entry["trigger"] == "FrameStart" for entry in camera.saved_sets))
        self.assertEqual(camera.SequencerMode.value, "On")
        self.assertEqual(camera.SequencerConfigurationMode.value, "Off")

    def test_set_id_mapping_prefers_chunk_exposure(self):
        mapping = {0: 1000.0, 1: 10000.0}
        self.assertEqual(sc.resolve_frame_exposure_us(None, 1, mapping, 500.0), 10000.0)
        self.assertEqual(sc.resolve_frame_exposure_us(9999.5, 1, mapping, 500.0), 9999.5)

    def test_too_many_sets_are_rejected_before_configuration(self):
        camera = FakeSequencerCamera()
        with self.assertRaisesRegex(ValueError, "at most 32"):
            sc.configure_exposure_sequencer(camera, [1000.0] * 33)


class BufferAndSaveTests(unittest.TestCase):
    def test_existing_recording_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            (output / "frames_00000000_00000000.npy").touch()
            with self.assertRaises(FileExistsError):
                sc.ensure_output_dir_has_no_recording(output)

    def test_dropped_frame_simulation_keeps_arrays_aligned_and_clears_buffer(self):
        buffer = sc.FrameChunkBuffer(capacity=2)
        # Simulated failed grab: append nothing.
        buffer.append(np.zeros((2, 2), np.uint16), 1.0, 1000.0, 0)
        buffer.append(np.ones((2, 2), np.uint16), 3.0, 10000.0, 1)
        self.assertTrue(buffer.is_full())
        chunk = buffer.take(split_files=True)
        self.assertEqual(len(buffer), 0)
        self.assertEqual(chunk.count, 2)
        self.assertEqual(len(chunk.timestamps_camera_us), chunk.count)
        self.assertEqual(len(chunk.exposure_times_us), chunk.count)
        self.assertEqual(len(chunk.sequencer_set_ids), chunk.count)

    def test_chunk_threshold_and_final_remainder_are_saved_contiguously(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            first = make_chunk(0, 2, True)
            second = make_chunk(2, 1, True)
            metrics1 = sc.save_frame_chunk(output, first)
            metrics2 = sc.save_frame_chunk(output, second)
            self.assertEqual((metrics1.start_index, metrics1.end_index), (0, 1))
            self.assertEqual((metrics2.start_index, metrics2.end_index), (2, 2))
            for metrics in (metrics1, metrics2):
                frames = np.load(output / metrics.frame_file)
                exposure = np.load(output / metrics.exposure_file)
                timestamps = np.load(output / metrics.timestamp_file)
                set_ids = np.load(output / metrics.sequencer_file)
                self.assertEqual(frames.shape[0], len(exposure))
                self.assertEqual(frames.shape[0], len(timestamps))
                self.assertEqual(frames.shape[0], len(set_ids))

    def test_legacy_frames_file_matches_metadata_length(self):
        with tempfile.TemporaryDirectory() as tmp:
            metrics = sc.save_frame_chunk(Path(tmp), make_chunk(0, 3, False))
            self.assertEqual(metrics.frame_file, "frames.npy")
            self.assertEqual(np.load(Path(tmp) / "frames.npy").shape[0], 3)
            self.assertEqual(len(np.load(Path(tmp) / "exposure_times_us.npy")), 3)

    def test_atomic_save_renames_temp_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "values.npy"
            sc.atomic_save_npy(path, np.arange(4))
            self.assertTrue(path.exists())
            self.assertFalse(Path(str(path) + ".tmp").exists())

    def test_frame_file_is_committed_after_chunk_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            original_replace = sc.os.replace
            destinations = []

            def track_replace(source, destination):
                destinations.append(Path(destination).name)
                return original_replace(source, destination)

            with mock.patch.object(sc.os, "replace", side_effect=track_replace):
                sc.save_frame_chunk(Path(tmp), make_chunk(0, 2, True))
            self.assertEqual(destinations[-1], "frames_00000000_00000001.npy")

    def test_chunk_metadata_is_combined_after_completion(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            first = sc.save_frame_chunk(output, make_chunk(0, 2, True))
            second = sc.save_frame_chunk(output, make_chunk(2, 1, True))
            metadata = {
                "timestamps_camera_files": [first.timestamp_file, second.timestamp_file],
                "exposure_times_files": [first.exposure_file, second.exposure_file],
                "sequencer_set_ids_files": [first.sequencer_file, second.sequencer_file],
            }
            sc._save_combined_metadata_vectors(output, metadata)
            self.assertEqual(len(np.load(output / "timestamps_camera_us.npy")), 3)
            self.assertEqual(len(np.load(output / "exposure_times_us.npy")), 3)
            self.assertEqual(len(np.load(output / "sequencer_set_ids.npy")), 3)

    def test_failed_current_chunk_keeps_prior_completed_chunk(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            first = sc.save_frame_chunk(output, make_chunk(0, 2, True))
            original = sc._write_npy_temp
            call_count = 0

            def fail_on_second_temp(path, array):
                nonlocal call_count
                call_count += 1
                if call_count == 2:
                    raise OSError("simulated SSD error")
                return original(path, array)

            with mock.patch.object(sc, "_write_npy_temp", side_effect=fail_on_second_temp):
                with self.assertRaises(OSError):
                    sc.save_frame_chunk(output, make_chunk(2, 2, True))
            self.assertTrue((output / first.frame_file).exists())
            self.assertFalse((output / "frames_00000002_00000003.npy").exists())
            self.assertFalse(any(output.glob("*.tmp")))


class MetadataProgressAndQueueTests(unittest.TestCase):
    def test_metadata_status_updates(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            stats = sc.CaptureStats()
            metadata = {
                "capture_status": "in_progress",
                "frame_files": [],
                "timestamps_camera_files": [],
                "exposure_times_files": [],
                "sequencer_set_ids_files": [],
                "saved_chunks": [],
            }
            tracker = sc.MetadataTracker(output, metadata, stats)
            stats.capture_succeeded()
            stats.capture_succeeded()
            metrics = sc.save_frame_chunk(output, make_chunk(0, 2, True))
            stats.saved(metrics)
            tracker.chunk_saved(metrics)
            tracker.finish("completed", 1.0, [2, 3], "uint16")
            saved = json.loads((output / "metadata.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["capture_status"], "completed")
            self.assertEqual(saved["frame_count_captured"], 2)
            self.assertEqual(saved["frame_count_saved"], 2)
            self.assertEqual(saved["last_saved_frame_index"], 1)

    def test_interrupted_and_failed_metadata_states(self):
        for status in ("interrupted", "failed"):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as tmp:
                output = Path(tmp)
                stats = sc.CaptureStats()
                metadata = {
                    "capture_status": "in_progress",
                    "frame_files": [],
                    "timestamps_camera_files": [],
                    "exposure_times_files": [],
                    "sequencer_set_ids_files": [],
                    "saved_chunks": [],
                }
                tracker = sc.MetadataTracker(output, metadata, stats)
                tracker.finish(status, 0.5, None, None, "simulated")
                saved = json.loads((output / "metadata.json").read_text(encoding="utf-8"))
                self.assertEqual(saved["capture_status"], status)
                self.assertEqual(saved["capture_error"], "simulated")

    def test_progress_fraction_and_eta_for_frame_and_time_limits(self):
        frame_cfg = sc.CaptureConfig(output_dir="x", frame_count=100)
        fraction, eta = sc.calculate_progress(frame_cfg, 5.0, 25)
        self.assertAlmostEqual(fraction, 0.25)
        self.assertAlmostEqual(eta, 15.0)

        time_cfg = sc.CaptureConfig(output_dir="x", measurement_duration_s=60)
        fraction, eta = sc.calculate_progress(time_cfg, 12.0, 120)
        self.assertAlmostEqual(fraction, 0.2)
        self.assertAlmostEqual(eta, 48.0)

        both_cfg = sc.CaptureConfig(output_dir="x", frame_count=100, measurement_duration_s=60)
        fraction, eta = sc.calculate_progress(both_cfg, 30.0, 80)
        self.assertAlmostEqual(fraction, 0.8)
        self.assertAlmostEqual(eta, 7.5)

    def test_periodic_progress_and_mismatch_warning(self):
        cfg = sc.CaptureConfig(output_dir="x", frame_count=10, frames_per_file=5)
        stats = sc.CaptureStats(captured_frames=5, saved_frames=4, dropped_frames=1)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            sc.print_progress(cfg, stats, 2.0, 1, 0)
            sc.print_summary("failed", stats, 2.0)
        text = output.getvalue()
        self.assertIn("[PROGRESS]", text)
        self.assertIn("ETA=", text)
        self.assertIn("do not match", text)

    def test_writer_queue_is_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            writer = sc.ChunkWriter(Path(tmp), 1, lambda metrics: None)
            self.assertEqual(writer.queue.maxsize, 1)
            writer.close()

    def test_async_writer_saves_submitted_chunk(self):
        with tempfile.TemporaryDirectory() as tmp:
            saved_metrics = []
            writer = sc.ChunkWriter(Path(tmp), 1, saved_metrics.append)
            writer.submit(make_chunk(0, 2, True))
            writer.close()
            self.assertEqual(len(saved_metrics), 1)
            self.assertTrue((Path(tmp) / saved_metrics[0].frame_file).exists())


if __name__ == "__main__":
    unittest.main()
