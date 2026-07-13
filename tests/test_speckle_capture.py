from __future__ import annotations

import contextlib
import io
import math
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from speckle_capture import speckle_capture as sc


class FakeNode:
    def __init__(
        self,
        value=None,
        *,
        minimum=None,
        maximum=None,
        writable=True,
        readable=True,
        available=True,
        accepted=None,
    ):
        self.Value = value
        self.Min = minimum
        self.Max = maximum
        self.writable = writable
        self.readable = readable
        self.available = available
        self.accepted = set(accepted) if accepted is not None else None
        self.set_history = []
        self.execute_count = 0

    @staticmethod
    def _flag_value(flag):
        return bool(flag() if callable(flag) else flag)

    def SetValue(self, value):
        if not self._flag_value(self.writable):
            raise RuntimeError("not writable")
        if self.accepted is not None and value not in self.accepted:
            raise ValueError(f"unsupported value: {value}")
        self.Value = value
        self.set_history.append(value)

    def GetValue(self):
        if not self._flag_value(self.readable):
            raise RuntimeError("not readable")
        return self.Value

    def Execute(self):
        if not self._flag_value(self.writable):
            raise RuntimeError("not writable")
        self.execute_count += 1


class FakeNodeMap:
    def __init__(self, nodes):
        self.nodes = nodes

    def GetNode(self, name):
        return self.nodes.get(name)


class FakeCamera:
    def __init__(self, nodes):
        self.nodes = nodes

    def GetNodeMap(self):
        return FakeNodeMap(self.nodes)

    def __getattr__(self, name):
        try:
            return self.nodes[name]
        except KeyError as exc:
            raise AttributeError(name) from exc


class FakeChunkValue:
    def __init__(self, value):
        self.Value = value


class FakeGrabResult:
    def __init__(self, succeeded=True, *, block_id=None, skipped=0, **chunks):
        self._succeeded = succeeded
        self.Array = np.arange(4, dtype=np.uint16).reshape(2, 2)
        self._block_id = block_id
        self._skipped = skipped
        for name, value in chunks.items():
            setattr(self, name, FakeChunkValue(value))

    def GrabSucceeded(self):
        return self._succeeded

    def GetBlockID(self):
        if self._block_id is None:
            raise RuntimeError("no block id")
        return self._block_id

    def GetNumberOfSkippedImages(self):
        return self._skipped


def make_record(value=1, timestamp=1000.0, exposure=1000.0, set_id=-1):
    return sc.FrameRecord(
        image=np.full((2, 3), value, dtype=np.uint16),
        timestamp_camera_us=timestamp,
        exposure_time_us=exposure,
        sequencer_set_id=set_id,
        timestamp_source="test",
        exposure_source="test",
        sequencer_set_source="test",
    )


def make_payload(start=0, count=2):
    return sc.ChunkPayload(
        start_index=start,
        frames=np.arange(count * 6, dtype=np.uint16).reshape(count, 2, 3),
        timestamps_camera_us=np.arange(count, dtype=np.float64) * 100.0,
        exposure_times_us=np.full(count, 1000.0, dtype=np.float64),
        sequencer_set_ids=np.zeros(count, dtype=np.int64),
    )


class ConfigValidationTests(unittest.TestCase):
    def base(self, **updates):
        values = {"output_dir": ".", "frame_count": 10, "exposure_time": 1000.0}
        values.update(updates)
        return sc.CaptureConfig(**values)

    def test_fixed_exposure(self):
        plan = sc.validate_capture_config(self.base())
        self.assertEqual(plan.mode, "fixed")
        self.assertEqual(plan.requested_times_us, (1000.0,))

    def test_multiple_exposures_take_priority(self):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            plan = sc.validate_capture_config(self.base(exposure_times_us=[1000, 10000]))
        self.assertEqual(plan.mode, "sequencer")
        self.assertEqual(plan.requested_times_us, (1000.0, 10000.0))
        self.assertIn("takes precedence", stream.getvalue())

    def test_one_element_sequence_is_allowed(self):
        plan = sc.validate_capture_config(self.base(exposure_times_us=[1000]))
        self.assertEqual(plan.mode, "sequencer")
        self.assertEqual(len(plan.requested_times_us), 1)

    def test_bad_sequences_are_rejected(self):
        bad_values = ([], [0], [-1], [math.nan], [math.inf], ["1000"], [True])
        for value in bad_values:
            with self.subTest(value=value), self.assertRaises(ValueError):
                sc.validate_capture_config(self.base(exposure_times_us=value))

    def test_non_array_sequence_is_rejected(self):
        with self.assertRaises(ValueError):
            sc.validate_capture_config(self.base(exposure_times_us="1000,10000"))

    def test_progress_and_chunk_sizes_must_be_positive(self):
        with self.assertRaises(ValueError):
            sc.validate_capture_config(self.base(progress_interval_s=0))
        with self.assertRaises(ValueError):
            sc.validate_capture_config(self.base(frames_per_file=0))


class SequencerTests(unittest.TestCase):
    def modern_nodes(self):
        configuration_mode = FakeNode("Off", accepted={"Off", "On"})

        def configuration_mode_on():
            return configuration_mode.Value == "On"

        return {
            "ExposureAuto": FakeNode("Continuous", accepted={"Continuous", "Off"}),
            "GainAuto": FakeNode("Continuous", accepted={"Continuous", "Off"}),
            "ExposureTime": FakeNode(1000.0, minimum=10.0, maximum=20000.0),
            "SequencerMode": FakeNode("Off", accepted={"Off", "On"}),
            "SequencerConfigurationMode": configuration_mode,
            "SequencerSetSelector": FakeNode(
                0,
                minimum=0,
                maximum=31,
                writable=configuration_mode_on,
            ),
            "SequencerSetSave": FakeNode(
                writable=configuration_mode_on,
                available=configuration_mode_on,
            ),
            "SequencerSetLoad": FakeNode(
                writable=configuration_mode_on,
                available=configuration_mode_on,
            ),
            "SequencerPathSelector": FakeNode(
                0,
                minimum=0,
                maximum=1,
                writable=configuration_mode_on,
            ),
            "SequencerSetNext": FakeNode(
                0,
                minimum=0,
                maximum=31,
                writable=configuration_mode_on,
            ),
            "SequencerTriggerSource": FakeNode(
                "Off",
                accepted={"FrameStart"},
                writable=configuration_mode_on,
            ),
            "SequencerTriggerActivation": FakeNode(
                "RisingEdge",
                accepted={"RisingEdge"},
                writable=configuration_mode_on,
            ),
            "SequencerSetStart": FakeNode(
                0,
                writable=configuration_mode_on,
            ),
        }

    def test_modern_usb_sequence_uses_path_one_and_cycles(self):
        nodes = self.modern_nodes()
        result = sc.configure_exposure_sequencer(FakeCamera(nodes), [1000.0, 10000.0])
        self.assertEqual(result.set_exposure_us, {0: 1000.0, 1: 10000.0})
        self.assertEqual(nodes["SequencerPathSelector"].set_history, [1, 1])
        self.assertEqual(nodes["SequencerSetNext"].set_history, [1, 0])
        self.assertEqual(nodes["SequencerTriggerSource"].set_history, ["FrameStart", "FrameStart"])
        self.assertEqual(nodes["SequencerSetSave"].execute_count, 2)
        self.assertEqual(nodes["SequencerSetLoad"].execute_count, 1)
        self.assertEqual(nodes["SequencerConfigurationMode"].set_history, ["On", "Off"])
        self.assertEqual(nodes["SequencerConfigurationMode"].Value, "Off")
        self.assertEqual(nodes["SequencerMode"].Value, "On")
        self.assertEqual(nodes["ExposureAuto"].set_history, ["Off"])
        self.assertEqual(nodes["GainAuto"].set_history, ["Off"])
        self.assertEqual(result.node_names["backend"], "sequencer_path")

    def test_modern_sequence_restores_modes_when_gated_node_is_missing(self):
        nodes = self.modern_nodes()
        nodes["SequencerSetSave"].available = False

        with self.assertRaisesRegex(RuntimeError, "sequencer set save command"):
            sc.configure_exposure_sequencer(FakeCamera(nodes), [1000.0, 10000.0])

        self.assertEqual(nodes["SequencerConfigurationMode"].set_history, ["On", "Off"])
        self.assertEqual(nodes["SequencerConfigurationMode"].Value, "Off")
        self.assertEqual(nodes["SequencerMode"].Value, "Off")

    def test_legacy_sequence_uses_auto_and_total_count(self):
        nodes = {
            "ExposureTimeAbs": FakeNode(1000.0, minimum=10.0, maximum=20000.0),
            "SequenceEnable": FakeNode(False, accepted={False, True}),
            "SequenceSetIndex": FakeNode(0, minimum=0, maximum=7),
            "SequenceSetStore": FakeNode(),
            "SequenceSetLoad": FakeNode(),
            "SequenceSetTotalNumber": FakeNode(1, minimum=1, maximum=8),
            "SequenceAdvanceMode": FakeNode("Auto", accepted={"Auto"}),
            "SequenceConfigurationMode": FakeNode("Off", accepted={"Off", "On"}),
            "SequenceSetExecutions": FakeNode(1, minimum=1, maximum=100),
        }
        result = sc.configure_exposure_sequencer(FakeCamera(nodes), [1000.0, 5000.0])
        self.assertEqual(result.node_names["backend"], "legacy_sequence")
        self.assertEqual(nodes["SequenceSetTotalNumber"].Value, 2)
        self.assertEqual(nodes["SequenceAdvanceMode"].Value, "Auto")
        self.assertEqual(nodes["SequenceSetStore"].execute_count, 2)
        self.assertEqual(nodes["SequenceConfigurationMode"].set_history, ["On", "Off"])
        self.assertEqual(nodes["SequenceEnable"].Value, True)

    def test_missing_sequencer_nodes_fail_before_grab(self):
        nodes = {"ExposureTime": FakeNode(1000.0, minimum=10, maximum=20000)}
        with self.assertRaisesRegex(RuntimeError, "sequencer enable"):
            sc.configure_exposure_sequencer(FakeCamera(nodes), [1000.0, 10000.0])

    def test_out_of_range_exposure_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "above camera maximum"):
            sc.configure_exposure_sequencer(FakeCamera(self.modern_nodes()), [50000.0])


class ChunkAndFrameTests(unittest.TestCase):
    def test_chunk_capabilities_probe_optional_set_id(self):
        nodes = {
            "ChunkModeActive": FakeNode(False),
            "ChunkSelector": FakeNode("Timestamp", accepted={"Timestamp", "ExposureTime"}),
            "ChunkEnable": FakeNode(False),
        }
        caps = sc.configure_chunk_data(FakeCamera(nodes))
        self.assertTrue(caps.timestamp_enabled)
        self.assertTrue(caps.exposure_enabled)
        self.assertFalse(caps.sequencer_set_enabled)

    def test_chunk_exposure_has_priority(self):
        result = FakeGrabResult(
            ChunkTimestamp=1_000_000,
            ChunkExposureTime=1234.5,
            ChunkSequencerSetActive=0,
        )
        record = sc.extract_frame_record(
            result,
            capture_start_monotonic_s=0.0,
            tick_frequency_hz=1_000_000.0,
            exposure_mode="sequencer",
            fixed_exposure_us=None,
            set_exposure_us={0: 1000.0},
        )
        self.assertIsNotNone(record)
        self.assertEqual(record.exposure_time_us, 1234.5)
        self.assertEqual(record.exposure_source, "camera_chunk_exposure_time")

    def test_set_id_maps_exposure_when_exposure_chunk_missing(self):
        result = FakeGrabResult(ChunkSequencerSetActive=1)
        record = sc.extract_frame_record(
            result,
            capture_start_monotonic_s=0.0,
            tick_frequency_hz=None,
            exposure_mode="sequencer",
            fixed_exposure_us=None,
            set_exposure_us={0: 1000.0, 1: 10000.0},
        )
        self.assertEqual(record.exposure_time_us, 10000.0)
        self.assertEqual(record.sequencer_set_id, 1)

    def test_exposure_uniquely_maps_set_and_duplicate_is_unknown(self):
        unique = FakeGrabResult(ChunkExposureTime=10000.0)
        record = sc.extract_frame_record(
            unique,
            capture_start_monotonic_s=0.0,
            tick_frequency_hz=None,
            exposure_mode="sequencer",
            fixed_exposure_us=None,
            set_exposure_us={0: 1000.0, 1: 10000.0},
        )
        self.assertEqual(record.sequencer_set_id, 1)
        self.assertEqual(sc.exposure_to_unique_set_id(1000.0, {0: 1000.0, 1: 1000.0}), -1)

    def test_failed_grab_returns_none_without_touching_array(self):
        result = FakeGrabResult(False)
        del result.Array
        record = sc.extract_frame_record(
            result,
            capture_start_monotonic_s=0.0,
            tick_frequency_hz=None,
            exposure_mode="fixed",
            fixed_exposure_us=1000.0,
            set_exposure_us={},
        )
        self.assertIsNone(record)

    def test_skipped_images_and_block_gap(self):
        skipped, block = sc.estimate_skipped_frames(FakeGrabResult(block_id=10, skipped=2), 7)
        self.assertEqual(skipped, 2)
        self.assertEqual(block, 10)

    def test_acA1440_tick_frequency_fallback(self):
        self.assertEqual(sc.get_timestamp_tick_frequency_hz(FakeCamera({}), "acA1440-220um"), 1e9)
        self.assertIsNone(sc.get_timestamp_tick_frequency_hz(FakeCamera({}), "unknown"))


class SaveAndQueueTests(unittest.TestCase):
    def test_full_buffer_flushes_and_releases_references(self):
        buffer = sc.FrameBuffer()
        buffer.append(make_record(1))
        self.assertIsNone(sc.take_full_chunk_if_ready(buffer, 2, 0))
        buffer.append(make_record(2))
        payload = sc.take_full_chunk_if_ready(buffer, 2, 0)
        self.assertIsNotNone(payload)
        self.assertEqual(payload.count, 2)
        self.assertEqual(len(buffer), 0)
        self.assertEqual(buffer.timestamps_camera_us, [])

    def test_final_partial_buffer_is_flushable(self):
        buffer = sc.FrameBuffer()
        buffer.append(make_record(1))
        payload = buffer.take_all(8)
        self.assertEqual((payload.start_index, payload.end_index, payload.count), (8, 8, 1))
        self.assertEqual(len(buffer), 0)

    def test_atomic_chunk_files_have_aligned_ranges_and_lengths(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            first = sc.save_chunk_files(output, make_payload(0, 2), chunked=True)
            second = sc.save_chunk_files(output, make_payload(2, 1), chunked=True)
            self.assertEqual(first.frame_file, "frames_00000000_00000001.npy")
            self.assertEqual(second.frame_file, "frames_00000002_00000002.npy")
            for prefix in ("frames", "timestamps_camera_us", "exposure_times_us", "sequencer_set_ids"):
                arrays = sorted(output.glob(prefix + "_*.npy"))
                self.assertEqual([len(np.load(path)) for path in arrays], [2, 1])
            self.assertEqual(list(output.glob("*.tmp")), [])

    def test_single_file_names_remain_compatible(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            sc.save_chunk_files(output, make_payload(0, 2), chunked=False)
            for name in (
                "frames.npy",
                "timestamps_camera_us.npy",
                "exposure_times_us.npy",
                "sequencer_set_ids.npy",
            ):
                self.assertTrue((output / name).is_file())

    def test_later_save_failure_does_not_delete_completed_chunk(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            sc.save_chunk_files(output, make_payload(0, 1), chunked=True)
            with mock.patch.object(sc, "_write_npy_temporary", side_effect=OSError("disk full")):
                with self.assertRaises(OSError):
                    sc.save_chunk_files(output, make_payload(1, 1), chunked=True)
            self.assertTrue((output / "frames_00000000_00000000.npy").is_file())

    def test_metadata_updates_atomically(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "metadata.json"
            manager = sc.MetadataManager(path, {"capture_status": "in_progress"})
            manager.update({"frame_count_saved": 2, "capture_status": "completed"})
            self.assertEqual(manager.snapshot()["capture_status"], "completed")
            self.assertFalse((Path(folder) / "metadata.json.tmp").exists())

    def test_bounded_queue_full_raises_without_silent_drop(self):
        started = threading.Event()
        release = threading.Event()
        stats = sc.CaptureStats()

        def slow_save(_output, payload, *, chunked):
            started.set()
            release.wait(2)
            return sc.SaveResult(
                payload.start_index,
                payload.end_index,
                payload.count,
                f"frames_{payload.start_index}.npy",
                "t.npy",
                "e.npy",
                "s.npy",
                100,
                0.1,
            )

        with tempfile.TemporaryDirectory() as folder, mock.patch.object(sc, "save_chunk_files", side_effect=slow_save):
            writer = sc.AsyncChunkWriter(
                Path(folder),
                stats,
                lambda: None,
                max_queue_chunks=1,
                put_timeout_s=0.01,
            )
            try:
                writer.submit(make_payload(0, 1))
                self.assertTrue(started.wait(1))
                writer.submit(make_payload(1, 1))
                stream = io.StringIO()
                with contextlib.redirect_stdout(stream), self.assertRaisesRegex(RuntimeError, "remained full"):
                    writer.submit(make_payload(2, 1))
                self.assertIn("without dropping", stream.getvalue())
            finally:
                release.set()
                writer.close()


class ProgressTests(unittest.TestCase):
    def test_frame_and_time_eta_choose_earlier_stop(self):
        estimate = sc.calculate_progress(
            captured_frames=40,
            elapsed_s=5.0,
            frame_count=100,
            measurement_duration_s=20.0,
        )
        self.assertAlmostEqual(estimate.percent, 40.0)
        self.assertAlmostEqual(estimate.eta_s, 7.5)
        self.assertEqual(estimate.limiting_condition, "frame_count")

    def test_reporter_obeys_interval(self):
        cfg = sc.CaptureConfig(output_dir=".", frame_count=10, progress_interval_s=10.0)
        stats = sc.CaptureStats()
        stats.record_capture(np.zeros((2, 2), dtype=np.uint8))
        output = []
        reporter = sc.ProgressReporter(cfg, stats, 100.0, printer=output.append)
        self.assertFalse(
            reporter.maybe_report(now_s=109.9, frame_buffer_count=1, queue_size=0, queue_capacity=2)
        )
        self.assertTrue(
            reporter.maybe_report(now_s=110.0, frame_buffer_count=1, queue_size=0, queue_capacity=2)
        )
        self.assertIn("captured=1", output[0])
        self.assertIn("eta=", output[0])

    def test_duration_progress_and_eta(self):
        estimate = sc.calculate_progress(
            captured_frames=20,
            elapsed_s=4.0,
            frame_count=None,
            measurement_duration_s=10.0,
        )
        self.assertAlmostEqual(estimate.percent, 40.0)
        self.assertAlmostEqual(estimate.eta_s, 6.0)
        self.assertEqual(estimate.limiting_condition, "duration")

    def test_summary_and_captured_saved_mismatch(self):
        snapshot = sc.CaptureSnapshot(
            captured_frames=10,
            saved_frames=9,
            saved_chunks=2,
            last_saved_frame_index=8,
            written_bytes=1024,
            dropped_frames=1,
            frame_shape=[2, 2],
            frame_dtype="uint16",
            frame_files=[],
            timestamp_files=[],
            exposure_files=[],
            sequencer_set_files=[],
        )
        summary = sc.format_capture_summary("failed", snapshot, 2.0)
        self.assertIn("status=failed", summary)
        self.assertIn("average_fps=5.00", summary)
        warning = sc.captured_saved_mismatch_warning(snapshot)
        self.assertIn("captured=10, saved=9", warning)
        snapshot.saved_frames = 10
        self.assertIsNone(sc.captured_saved_mismatch_warning(snapshot))


if __name__ == "__main__":
    unittest.main()
