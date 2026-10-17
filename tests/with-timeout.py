"""Run a validation command with a hard process-group timeout on macOS/Linux."""

import argparse
import math
import os
import signal
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seconds", type=float)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not math.isfinite(args.seconds) or args.seconds <= 0 or not args.command:
        parser.error("Provide a positive finite timeout and a command.")

    with subprocess.Popen(args.command, start_new_session=True) as process:
        try:
            code = process.wait(timeout=args.seconds)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            code = 124 if isinstance(error, subprocess.TimeoutExpired) else 130
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass  # The entire process group already exited.
            process.wait()
            try:
                os.write(
                    2, b"Validation timed out.\n" if code == 124 else b"Validation interrupted.\n"
                )
            except OSError:
                pass  # A closed diagnostic pipe must not replace the exit status.
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    raise SystemExit(main())
