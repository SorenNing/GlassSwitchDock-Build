"""Portable tests for CI device selection and the separate boot deadline."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('simulator_runner', Path(__file__).with_name('run-simulator.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def phone(name, runtime, state='Shutdown'):
    return dict(name=name, runtime='com.apple.CoreSimulator.SimRuntime.iOS-'+runtime,
                state=state, udid=name+runtime)


class SimulatorRunner(unittest.TestCase):
    def test_sdk_runtime_beats_alphabetically_first_old_phone(self):
        old = phone('iPhone 16e', '26-2')
        current = phone('iPhone 17 Pro', '26-5')
        self.assertEqual(runner.select_auto_device([old, current], '26.5'), current)

    def test_running_phone_avoids_cold_migration(self):
        running = phone('iPhone 16e', '26-2', 'Booted')
        self.assertEqual(runner.select_auto_device([phone('iPhone 17', '26-5'), running], '26.5'), running)

    def test_newest_runtime_fallback_uses_numeric_versions(self):
        newer = phone('iPhone 17', '26-10')
        self.assertEqual(runner.select_auto_device([phone('iPhone 16', '26-9'), newer], '27.0'), newer)
        with self.assertRaises(RuntimeError):
            runner.select_auto_device([], '26.5')

    def test_migration_budget_is_passed_without_resetting_simulator(self):
        with patch.object(runner, 'command') as command:
            runner.wait_for_boot('fixture-device', 600)
        command.assert_called_once_with(['xcrun', 'simctl', 'bootstatus', 'fixture-device', '-b'], timeout=600)
