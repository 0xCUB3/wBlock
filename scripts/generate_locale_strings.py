#!/usr/bin/env python3
"""
Generate one Localizable.strings file from the English key list with visible progress.

Usage:
  python3 scripts/generate_locale_strings.py --folder ja --lang ja
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

from deep_translator import GoogleTranslator


PLACEHOLDER_PATTERNS = [
    re.compile(r"%\d+\$[@df]"),
    re.compile(r"%[@df]"),
]
PROTECTED_TERMS = ["wBlock", "Safari", "iCloud", "YouTube", "AdGuard", "URL"]
KEY_LINE_PATTERN = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder", required=True, help="Locale folder, e.g. zh-Hans")
    parser.add_argument("--lang", required=True, help="Translator language, e.g. zh-CN")
    parser.add_argument(
        "--root",
        default="/Users/skula/Documents/wBlock",
        help="Repository root (defaults to current workspace path).",
    )
    parser.add_argument("--chunk-size", type=int, default=35)
    return parser.parse_args()


def load_keys(en_file: Path) -> list[str]:
    keys: list[str] = []
    for raw_line in en_file.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        match = KEY_LINE_PATTERN.match(line)
        if not match:
            continue
        key = match.group(1).encode("utf-8").decode("unicode_escape")
        keys.append(key)
    # Keep order and uniqueness
    seen = set()
    ordered: list[str] = []
    for key in keys:
        if key not in seen:
            seen.add(key)
            ordered.append(key)
    return ordered


def should_translate(text: str) -> bool:
    if text.startswith("http://") or text.startswith("https://"):
        return False
    if "\\(" in text:
        return False
    return True


def protect_text(text: str) -> tuple[str, dict[str, str]]:
    token_map: dict[str, str] = {}
    token_index = 0

    def add_token(fragment: str) -> str:
        nonlocal token_index
        token = f"__TOKEN_{token_index}__"
        token_index += 1
        token_map[token] = fragment
        return token

    protected = text

    for pattern in PLACEHOLDER_PATTERNS:
        while True:
            match = pattern.search(protected)
            if not match:
                break
            fragment = match.group(0)
            protected = protected[: match.start()] + add_token(fragment) + protected[match.end() :]

    for term in PROTECTED_TERMS:
        protected = re.sub(rf"\b{re.escape(term)}\b", lambda _: add_token(term), protected)

    return protected, token_map


def unprotect_text(text: str, token_map: dict[str, str]) -> str:
    value = text
    for token, fragment in token_map.items():
        value = value.replace(token, fragment)
    return value


def escape_strings_entry(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def translate_keys(keys: list[str], target_lang: str, chunk_size: int) -> dict[str, str]:
    output: dict[str, str] = {key: key for key in keys}

    translatable: list[tuple[str, str, dict[str, str]]] = []
    for key in keys:
        if not should_translate(key):
            output[key] = key
            continue
        protected, token_map = protect_text(key)
        translatable.append((key, protected, token_map))

    if not translatable:
        return output

    translator = GoogleTranslator(source="en", target=target_lang)
    total_chunks = math.ceil(len(translatable) / chunk_size)

    for i in range(0, len(translatable), chunk_size):
        chunk = translatable[i : i + chunk_size]
        chunk_idx = (i // chunk_size) + 1
        print(f"chunk {chunk_idx}/{total_chunks}", flush=True)
        source_payload = [protected for _, protected, _ in chunk]
        try:
            translated_payload = translator.translate_batch(source_payload)
            if translated_payload is None or len(translated_payload) != len(source_payload):
                translated_payload = source_payload
        except Exception:
            translated_payload = source_payload

        for (original_key, _, token_map), translated in zip(chunk, translated_payload):
            if translated is None:
                translated = original_key
            output[original_key] = unprotect_text(translated, token_map)

    return output


def main() -> None:
    args = parse_args()
    repo_root = Path(args.root)
    english_file = repo_root / "wBlock" / "en.lproj" / "Localizable.strings"
    if not english_file.exists():
        raise FileNotFoundError(f"Missing English seed file: {english_file}")

    keys = load_keys(english_file)
    print(f"keys={len(keys)}", flush=True)

    if args.folder == "en":
        translations = {key: key for key in keys}
    else:
        translations = translate_keys(keys, args.lang, args.chunk_size)

    out_dir = repo_root / "wBlock" / f"{args.folder}.lproj"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "Localizable.strings"
    lines = [f'"{escape_strings_entry(key)}" = "{escape_strings_entry(translations[key])}";' for key in keys]
    out_file.write_text("\n".join(lines) + "\n")
    print(f"wrote={out_file}", flush=True)


if __name__ == "__main__":
    main()
