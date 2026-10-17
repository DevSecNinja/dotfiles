"""Model-free tests for the global MLX launcher (standard library only)."""

from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).resolve().parents[2] / "home/dot_config/mlx/chat.py"
SPEC = importlib.util.spec_from_file_location("mlx_chat", SCRIPT)
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)
CHECK_ENVIRONMENT = launcher.check_environment


class LocalEntryNotFoundError(Exception):
    pass


class ChatTests(unittest.TestCase):
    def setUp(self):
        self.lengths = {}
        self.calls = []
        self.responses = []
        self.closed_streams = 0
        self.model = object()
        self.tokenizer = Mock()
        self.tokenizer.eos_token_ids = {0, 2}
        self.tokenizer.encode.side_effect = lambda text, **_: {
            "<|im_end|>": [2], "\n": [3]
        }[text]
        self.tokenizer.apply_chat_template.side_effect = (
            lambda messages, **_: [11] * self.lengths.get(messages[0]["content"], 10)
        )
        self.modules = {
            name: ModuleType(name)
            for name in (
                "mlx", "mlx.core", "mlx_lm", "mlx_lm.models",
                "mlx_lm.models.cache", "mlx_lm.sample_utils",
                "huggingface_hub", "huggingface_hub.errors",
                "packaging", "packaging.version",
            )
        }
        self.mx = self.modules["mlx.core"]
        self.modules["mlx"].core = self.mx
        self.mx.clear_cache = Mock()
        self.load = self.modules["mlx_lm"].load = Mock(
            return_value=(self.model, self.tokenizer)
        )
        self.modules["mlx_lm"].stream_generate = self.stream
        self.make_cache = self.modules["mlx_lm.models.cache"].make_prompt_cache = Mock(
            side_effect=lambda _: [SimpleNamespace(tokens=[])]
        )
        self.sampler = self.modules["mlx_lm.sample_utils"].make_sampler = Mock()
        self.snapshot = self.modules["huggingface_hub"].snapshot_download = Mock(
            return_value="/mock/external/snapshot"
        )
        self.modules["huggingface_hub.errors"].LocalEntryNotFoundError = (
            LocalEntryNotFoundError
        )
        self.modules["packaging.version"].Version = (
            lambda text: tuple(int(part) for part in text.split("."))
        )
        self.module_patch = patch.dict(sys.modules, self.modules)
        self.module_patch.start()
        self.addCleanup(self.module_patch.stop)
        self.environment_patch = patch.object(launcher, "check_environment")
        self.environment_check = self.environment_patch.start()
        self.addCleanup(self.environment_patch.stop)
        self.output = io.StringIO()
        self.redirect = redirect_stdout(self.output)
        self.redirect.__enter__()
        self.addCleanup(self.redirect.__exit__, None, None, None)

    def stream(self, model, tokenizer, prompt, **kwargs):
        self.assertIs(model, self.model)
        self.assertIs(tokenizer, self.tokenizer)
        cache = kwargs["prompt_cache"]
        self.calls.append({
            "prompt": prompt[:], "before": len(cache[0].tokens), **kwargs
        })
        cache[0].tokens.extend(prompt)
        tokens, reason = self.responses.pop(0) if self.responses else ([42, 2], "stop")
        try:
            for i, token in enumerate(tokens, 1):
                if isinstance(token, BaseException):
                    raise token
                # Match mlx-lm 0.32.2's one-token lookahead, including cached EOS.
                cache[0].tokens.append(token)
                yield SimpleNamespace(
                    text="" if token in self.tokenizer.eos_token_ids else "answer",
                    token=token, generation_tokens=i, generation_tps=12.5,
                    peak_memory=6.25,
                    finish_reason=reason if i == len(tokens) else None,
                )
        finally:
            self.closed_streams += 1

    def run_chat(self, inputs):
        with patch("builtins.input", side_effect=inputs):
            launcher.chat(self.model, self.tokenizer)
        return self.output.getvalue()

    def test_no_thinking_sampling_and_cache_continuity(self):
        output = self.run_chat(["first", "second", "q"])
        self.sampler.assert_called_once_with(temp=0.7, top_p=0.8, top_k=20)
        for call in self.tokenizer.apply_chat_template.call_args_list:
            self.assertEqual(call.kwargs, {
                "tokenize": True, "add_generation_prompt": True, "enable_thinking": False
            })
            self.assertEqual(len(call.args[0]), 1)
        first, second = self.calls
        self.assertIs(first["prompt_cache"], second["prompt_cache"])
        self.assertEqual(first["prompt"], [11] * 10)
        self.assertEqual(second["prompt"], [3] + [11] * 10)
        self.assertEqual(second["before"], 12)
        for call in self.calls:
            self.assertEqual(call["max_tokens"], 512)
            self.assertEqual(call["prefill_step_size"], 512)
            self.assertIs(call["sampler"], self.sampler.return_value)
        self.assertEqual(self.tokenizer.detokenizer.reset.call_count, 2)
        self.assertIn("12.5 tok/s; peak 6.25 GB", output)
        self.assertIn("context 25/8192", output)
        self.assertEqual(self.closed_streams, 2)

    def test_reset_releases_history_and_starts_without_separator(self):
        output = self.run_chat(["first", "r", "second", "q"])
        self.assertEqual(self.make_cache.call_count, 2)
        self.assertIsNot(self.calls[0]["prompt_cache"], self.calls[1]["prompt_cache"])
        self.assertEqual(self.calls[1]["before"], 0)
        self.assertEqual(self.calls[1]["prompt"], [11] * 10)
        self.assertEqual(self.mx.clear_cache.call_count, 2)
        self.assertIn("Conversation reset.", output)

    def test_exact_8192_token_boundary_is_admitted(self):
        self.lengths["boundary"] = 8192 - 512
        self.responses = [([42] * 512, "length")]
        output = self.run_chat(["boundary", "q"])
        self.assertEqual(len(self.calls), 1)
        self.assertIn("context 8192/8192", output)

    def test_oversized_prompt_is_rejected_without_mutating_history(self):
        self.lengths["oversized"] = 8192 - 512 + 1
        output = self.run_chat(["oversized", "shorter", "q"])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0]["before"], 0)
        self.assertIn("8193/8192", output)
        self.assertIn("history has not been dropped", output)

    def test_truncation_boundary_and_cached_history_count_toward_limit(self):
        self.lengths.update(first=100, oversized=7067, boundary=7066)
        self.responses = [([42] * 512, "length"), ([42, 2], "stop")]
        output = self.run_chat(["first", "oversized", "boundary", "q"])
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(self.calls[1]["before"], 612)
        self.assertEqual(self.calls[1]["prompt"], [2, 3] + [11] * 7066)
        self.assertIs(self.calls[0]["prompt_cache"], self.calls[1]["prompt_cache"])
        self.assertIn("8193/8192", output)
        self.assertIn("Reply reached the 512-token limit", output)

    def test_alternate_eos_also_closes_the_assistant_turn(self):
        self.responses = [([0], "stop")]
        self.run_chat(["first", "second", "q"])
        self.assertEqual(self.calls[1]["prompt"], [2, 3] + [11] * 10)

    def test_commands_and_blank_input_do_not_generate(self):
        output = self.run_chat(["  ", "h", "q"])
        self.assertFalse(self.calls)
        self.assertIn(launcher.HELP, output)

    def test_eof_and_keyboard_interrupt_at_input_exit_cleanly(self):
        for signal in (EOFError(), KeyboardInterrupt()):
            with self.subTest(signal=type(signal).__name__):
                output = self.run_chat([signal])
                self.assertIn("Bye.", output)
        self.assertFalse(self.calls)

    def test_interrupt_during_generation_closes_stream_and_releases_cache(self):
        self.responses = [([42, KeyboardInterrupt()], "stop")]
        output = self.run_chat(["first"])
        self.assertEqual(self.closed_streams, 1)
        self.assertEqual(self.calls[0]["prompt_cache"], [])
        self.mx.clear_cache.assert_called_once_with()
        self.assertIn("Bye.", output)

    def test_generation_errors_are_not_hidden(self):
        self.responses = [([RuntimeError("GPU failure")], "stop")]
        with self.assertRaisesRegex(RuntimeError, "GPU failure"):
            self.run_chat(["first"])
        self.assertEqual(self.closed_streams, 1)
        self.assertEqual(self.calls[0]["prompt_cache"], [])
        self.assertNotIn("Bye.", self.output.getvalue())

    def test_generation_eof_is_not_mistaken_for_terminal_eof(self):
        self.responses = [([EOFError("truncated weights")], "stop")]
        with self.assertRaisesRegex(EOFError, "truncated weights"):
            self.run_chat(["first"])
        self.assertEqual(self.closed_streams, 1)
        self.assertNotIn("Bye.", self.output.getvalue())

    def test_incomplete_stream_is_an_error(self):
        self.responses = [([], "stop")]
        with self.assertRaisesRegex(RuntimeError, "without a completed response"):
            self.run_chat(["first"])

    def test_missing_turn_token_is_rejected(self):
        self.tokenizer.eos_token_ids = {0}
        with self.assertRaisesRegex(ValueError, "end-of-turn token"):
            self.run_chat(["q"])

    def run_main(self, root, system="Darwin", machine="arm64", check=False):
        args = ["chat.py", "--cache-dir", str(root), "--volume", str(Path(root).parent)]
        if check:
            args.append("--check-env")
        with (
            patch.object(sys, "argv", args),
            patch.object(launcher.platform, "system", return_value=system),
            patch.object(launcher.platform, "machine", return_value=machine),
            patch.object(Path, "is_mount", return_value=True),
            patch("builtins.input", return_value="q"),
        ):
            launcher.main()

    def test_main_forces_external_cache_and_uses_existing_model_without_download(self):
        with tempfile.TemporaryDirectory(prefix="mlx cache ") as directory:
            root = Path(directory).resolve()
            (root / "hub").mkdir()
            (root / "xet").mkdir()
            with patch.dict(os.environ, {
                "HF_HOME": "/internal", "HF_HUB_CACHE": "/internal/hub",
                "HF_XET_CACHE": "/internal/xet", "HF_HUB_OFFLINE": "1",
                "TRANSFORMERS_OFFLINE": "1",
            }):
                def snapshot(*args, **kwargs):
                    self.assertEqual(args, (launcher.MODEL,))
                    self.assertEqual(kwargs, {
                        "cache_dir": str(root / "hub"), "local_files_only": True
                    })
                    self.assertEqual(os.environ["HF_HOME"], str(root))
                    self.assertEqual(os.environ["HF_HUB_CACHE"], str(root / "hub"))
                    self.assertEqual(os.environ["HF_XET_CACHE"], str(root / "xet"))
                    self.assertEqual(os.environ["HF_HUB_OFFLINE"], "0")
                    self.assertEqual(os.environ["TRANSFORMERS_OFFLINE"], "0")
                    return str(root / "hub/snapshot")
                self.snapshot.side_effect = snapshot
                self.run_main(root)
                self.snapshot.assert_called_once()
                self.load.assert_called_once_with(
                    str(root / "hub/snapshot"),
                    tokenizer_config={"trust_remote_code": False},
                    trust_remote_code=False,
                )
            self.assertEqual(sorted(p.name for p in root.iterdir()), ["hub", "xet"])

    def test_missing_cache_fails_without_loading(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ):
            root = Path(directory)
            for child in ("", "hub"):
                if child:
                    (root / child).mkdir()
                error = io.StringIO()
                with redirect_stderr(error), self.assertRaises(SystemExit) as exit_info:
                    self.run_main(root)
                self.assertEqual(exit_info.exception.code, 1)
                self.load.assert_not_called()
                self.snapshot.assert_not_called()
                self.assertIn("No internal fallback", error.getvalue())

    def test_missing_model_downloads_only_to_external_cache(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ):
            root = Path(directory).resolve()
            (root / "hub").mkdir()
            (root / "xet").mkdir()
            self.snapshot.side_effect = [
                LocalEntryNotFoundError("not cached"), str(root / "hub/snapshot")
            ]
            self.run_main(root)
            self.assertEqual(self.snapshot.call_count, 2)
            self.assertEqual(self.snapshot.call_args.kwargs, {
                "cache_dir": str(root / "hub"), "local_files_only": False
            })
            self.assertIn("Downloading", self.output.getvalue())
            self.load.assert_called_once()

    def test_download_failure_is_not_hidden(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ):
            root = Path(directory)
            (root / "hub").mkdir()
            (root / "xet").mkdir()
            self.snapshot.side_effect = [
                LocalEntryNotFoundError("not cached"), OSError("download failed")
            ]
            with self.assertRaisesRegex(OSError, "download failed"):
                self.run_main(root)
            self.load.assert_not_called()

    def test_status_check_never_resolves_or_loads_a_model(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ):
            root = Path(directory)
            (root / "hub").mkdir()
            (root / "xet").mkdir()
            self.run_main(root, check=True)
            self.environment_check.assert_called_once()
            self.snapshot.assert_not_called()
            self.load.assert_not_called()

    def test_status_check_reports_broken_packages(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ):
            root = Path(directory)
            (root / "hub").mkdir()
            (root / "xet").mkdir()
            self.environment_check.side_effect = ImportError("missing dependency")
            error = io.StringIO()
            with redirect_stderr(error), self.assertRaises(SystemExit) as result:
                self.run_main(root, check=True)
            self.assertEqual(result.exception.code, 1)
            self.assertIn("missing dependency", error.getvalue())
            self.snapshot.assert_not_called()

    def test_environment_check_accepts_current_and_newer_without_installing(self):
        for release in ("0.32.2", "0.33.0"):
            with (
                patch.object(sys, "version_info", (3, 14, 8)),
                patch.object(sys, "prefix", "/mock/venv"),
                patch.object(launcher, "version", return_value=release),
            ):
                CHECK_ENVIRONMENT()
        self.load.assert_not_called()
        self.snapshot.assert_not_called()

    def test_environment_check_rejects_old_packages_and_non_venv_python(self):
        with (
            patch.object(sys, "version_info", (3, 14, 8)),
            patch.object(sys, "prefix", "/mock/venv"),
            patch.object(launcher, "version", return_value="0.31.0"),
        ):
            with self.assertRaisesRegex(ValueError, "0.32.2"):
                CHECK_ENVIRONMENT()
        with patch.object(sys, "prefix", sys.base_prefix):
            with self.assertRaisesRegex(ValueError, "virtual environment"):
                CHECK_ENVIRONMENT()

    def test_unmounted_or_redirected_cache_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            volume = Path(directory) / "volume"
            volume.mkdir()
            with patch.object(Path, "is_mount", return_value=False):
                with self.assertRaisesRegex(ValueError, "Connect the external SSD"):
                    launcher.configure_cache(volume / "cache", volume)
            outside = Path(directory) / "internal"
            outside.mkdir()
            with patch.object(Path, "is_mount", return_value=True):
                with self.assertRaisesRegex(ValueError, "beneath the external SSD"):
                    launcher.configure_cache(outside, volume)

    def test_non_apple_platforms_fail_before_cache_lookup(self):
        for system, machine in (
            ("Linux", "aarch64"), ("Darwin", "x86_64"), ("Windows", "ARM64")
        ):
            with self.subTest(system=system, machine=machine):
                with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                    self.run_main("/not/accessed", system, machine)
                self.assertEqual(error.exception.code, 2)
        self.snapshot.assert_not_called()
        self.load.assert_not_called()

    def test_model_loading_failure_propagates(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ):
            root = Path(directory)
            (root / "hub").mkdir()
            (root / "xet").mkdir()
            self.load.side_effect = RuntimeError("incomplete model weights")
            with self.assertRaisesRegex(RuntimeError, "incomplete model weights"):
                self.run_main(root)


if __name__ == "__main__":
    unittest.main()
