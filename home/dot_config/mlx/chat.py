"""Bounded-memory Qwen3.5 chat using Apple's mlx-lm Python API."""

import argparse
from contextlib import closing
from importlib.metadata import version, PackageNotFoundError
import os
from pathlib import Path
import platform
import sys


MODEL = "mlx-community/Qwen3.5-9B-4bit"
CONTEXT_TOKENS = 8192
REPLY_TOKENS = 512
HELP = "q: quit | r: reset conversation | h: help"


def configure_cache(cache_dir, volume):
    mount = Path(volume).expanduser()
    if not mount.is_absolute() or not mount.is_mount():
        raise ValueError(f"Connect the external SSD at {mount}.")
    mount = mount.resolve(strict=True)
    root = Path(cache_dir).expanduser()
    if not root.is_absolute():
        raise ValueError("The cache directory must be an absolute path.")
    root = root.resolve(strict=True)
    if not root.is_relative_to(mount) or root == mount:
        raise ValueError("The cache directory must be beneath the external SSD.")
    for name in ("hub", "xet"):
        child = root / name
        if not child.is_dir():
            raise ValueError(f"Missing {root / name}. Connect the external SSD.")
        if not child.resolve(strict=True).is_relative_to(mount):
            raise ValueError(f"{child} points outside the external SSD.")

    # Set these before importing Hugging Face/MLX: they cache environment values.
    # Deliberately override inherited settings; never fall back to internal storage.
    os.environ.update(
        HF_HOME=str(root),
        HF_HUB_CACHE=str(root / "hub"),
        HF_XET_CACHE=str(root / "xet"),
        HF_HUB_OFFLINE="0",
        TRANSFORMERS_OFFLINE="0",
        HF_HUB_DISABLE_TELEMETRY="1",
    )
    return root


def check_environment():
    if sys.version_info < (3, 10) or sys.prefix == sys.base_prefix:
        raise ValueError("A Python 3.10+ virtual environment is required.")
    import mlx.core
    from mlx_lm import load, stream_generate
    from mlx_lm.models.cache import make_prompt_cache
    from mlx_lm.sample_utils import make_sampler
    from packaging.version import Version

    if Version(version("mlx-lm")) < Version("0.32.2"):
        raise ValueError("mlx-lm 0.32.2 or newer is required for this launcher.")


def chat(model, tokenizer):
    import mlx.core as mx
    from mlx_lm import stream_generate
    from mlx_lm.models.cache import make_prompt_cache
    from mlx_lm.sample_utils import make_sampler

    end = tokenizer.encode("<|im_end|>", add_special_tokens=False)
    if len(end) != 1 or end[0] not in tokenizer.eos_token_ids:
        raise ValueError("Expected Qwen3.5's <|im_end|> end-of-turn token.")
    newline = tokenizer.encode("\n", add_special_tokens=False)
    sampler = make_sampler(temp=0.7, top_p=0.8, top_k=20)
    cache = make_prompt_cache(model)
    used_tokens = 0
    separator = []
    print(f"{HELP}\nContext limit: {CONTEXT_TOKENS} tokens; replies: {REPLY_TOKENS}.")
    print("Thinking disabled. Conversation stays in memory; nothing is saved.")
    try:
        while True:
            try:
                query = input("\nYou: ").strip()
            except EOFError:
                print()
                break
            if query == "q":
                break
            if query == "h":
                print(HELP)
                continue
            if query == "r":
                cache.clear()
                mx.clear_cache()
                cache = make_prompt_cache(model)
                used_tokens = 0
                separator = []
                print("Conversation reset.")
                continue
            if not query:
                continue

            prompt = separator + tokenizer.apply_chat_template(
                [{"role": "user", "content": query}],
                tokenize=True,
                add_generation_prompt=True,
                enable_thinking=False,
            )
            required = used_tokens + len(prompt) + REPLY_TOKENS
            if required > CONTEXT_TOKENS:
                print(
                    f"Context limit: this turn needs {required}/{CONTEXT_TOKENS} "
                    "tokens including the reserved reply. Enter r to reset "
                    "or shorten your input; history has not been dropped."
                )
                continue

            tokenizer.detokenizer.reset()
            print("\nAssistant: ", end="", flush=True)
            last = None
            with closing(
                stream_generate(
                    model,
                    tokenizer,
                    prompt,
                    prompt_cache=cache,
                    sampler=sampler,
                    max_tokens=REPLY_TOKENS,
                    prefill_step_size=512,
                )
            ) as responses:
                for response in responses:
                    print(response.text, end="", flush=True)
                    last = response
            if last is None or last.finish_reason not in ("stop", "length"):
                raise RuntimeError("MLX generation ended without a completed response.")

            # mlx-lm 0.32.2 caches each yielded token, including EOS, before yielding.
            # Append only the missing boundary, not a re-rendered copy of history.
            used_tokens += len(prompt) + last.generation_tokens
            separator = ([] if last.token == end[0] else end) + newline
            print(
                f"\n[{last.generation_tokens} tokens; "
                f"{last.generation_tps:.1f} tok/s; "
                f"peak {last.peak_memory:.2f} GB; "
                f"context {used_tokens}/{CONTEXT_TOKENS}]"
            )
            if last.finish_reason == "length":
                print("Reply reached the 512-token limit; the next turn will close it.")
    except KeyboardInterrupt:
        print()
    finally:
        cache.clear()
        mx.clear_cache()
    print("Bye.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", required=True, help="Existing Hugging Face cache root")
    parser.add_argument("--volume", required=True, help="Mounted external SSD")
    parser.add_argument("--check-env", action="store_true", help="Check prerequisites without loading a model")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("MLX chat requires native Apple Silicon macOS (not Rosetta).")
    try:
        root = configure_cache(args.cache_dir, args.volume)
    except (OSError, ValueError) as error:
        parser.exit(1, f"External cache unavailable: {error}\nNo internal fallback is used.\n")
    try:
        check_environment()
    except (ImportError, OSError, ValueError, PackageNotFoundError) as error:
        parser.exit(
            1, f"MLX environment unavailable: {error}\n"
            "Run task -g llm:chat to install missing requirements. If setup still "
            "fails, repair the venv or move it aside; working packages are not force-upgraded.\n"
        )
    if args.check_env:
        return

    try:
        from huggingface_hub import snapshot_download
        from huggingface_hub.errors import LocalEntryNotFoundError
        from mlx_lm import load
    except ImportError as error:
        parser.exit(1, f"Cannot import mlx-lm from this Python environment: {error}\n")
    try:
        snapshot = snapshot_download(
            MODEL, cache_dir=str(root / "hub"), local_files_only=True
        )
    except LocalEntryNotFoundError:
        print(f"Downloading {MODEL} to {root / 'hub'} (external SSD)...", flush=True)
        snapshot = snapshot_download(
            MODEL, cache_dir=str(root / "hub"), local_files_only=False
        )

    print(f"Loading {MODEL} from the external cache...", flush=True)
    model, tokenizer = load(
        snapshot,
        tokenizer_config={"trust_remote_code": False},
        trust_remote_code=False,
    )
    chat(model, tokenizer)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nBye.")
