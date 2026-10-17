"""Process-level regressions for the documented macOS/Linux timeout command."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


WRAPPER = Path(__file__).resolve().parents[1] / "with-timeout.py"


@unittest.skipUnless(os.name == "posix", "The validation wrapper targets macOS/Linux")
class TimeoutTests(unittest.TestCase):
    def run_command(self, code, seconds="5"):
        return subprocess.run(
            [sys.executable, str(WRAPPER), seconds, sys.executable, "-c", code],
            capture_output=True, text=True, timeout=10,
        )

    def test_preserves_success_failure_output_and_signal_exit(self):
        for status in (0, 23):
            with self.subTest(status=status):
                result = self.run_command(f"print('visible output'); raise SystemExit({status})")
                self.assertEqual(result.returncode, status)
                self.assertEqual(result.stdout, "visible output\n")
        result = self.run_command("import os,signal; os.kill(os.getpid(), signal.SIGTERM)")
        self.assertEqual(result.returncode, 128 + signal.SIGTERM)

    def test_timeout_kills_child_and_grandchild(self):
        # Inherited stdout stays open if only the immediate child is killed.
        result = self.run_command(
            "import subprocess,sys,time; "
            "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
            "print('started', flush=True); time.sleep(30)",
            seconds="1",
        )
        self.assertEqual(result.returncode, 124)
        self.assertIn("started", result.stdout)
        self.assertIn("Validation timed out.", result.stdout)

    def test_interrupt_cleans_up_process_group(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / "ready"
            code = (
                "import pathlib,subprocess,sys,time; "
                "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
                f"pathlib.Path({str(ready)!r}).touch(); time.sleep(30)"
            )
            with subprocess.Popen(
                [sys.executable, str(WRAPPER), "5", sys.executable, "-c", code],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ) as wrapper:
                deadline = time.monotonic() + 3
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists(), "Child did not start")
                wrapper.send_signal(signal.SIGINT)
                output, error = wrapper.communicate(timeout=7)
                self.assertEqual(wrapper.returncode, 130, error)
                self.assertIn("Validation interrupted.", output)

    def test_invalid_timeout_and_missing_command_are_reported(self):
        for seconds in ("0", "-1", "nan", "inf"):
            with self.subTest(seconds=seconds):
                result = self.run_command("raise SystemExit(99)", seconds)
                self.assertEqual(result.returncode, 2)
                self.assertIn("positive finite timeout", result.stderr)
        result = subprocess.run(
            [sys.executable, str(WRAPPER), "1"], capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
