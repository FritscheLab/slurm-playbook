#!/usr/bin/env python3
"""Regenerate SHA256SUMS.txt for public download assets deterministically."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import sys
import tempfile
from typing import Final


REPO_ROOT: Final[Path] = Path(__file__).resolve().parents[1]
DOWNLOAD_DIR: Final[Path] = REPO_ROOT / "docs/assets/downloads"
DEFAULT_OUTPUT: Final[Path] = REPO_ROOT / "SHA256SUMS.txt"
ALLOWED_DOWNLOADS: Final[frozenset[str]] = frozenset(
    {
        "slurm-example-pipeline.zip",
        "slurm-session-cheatsheets.pdf",
        "slurm-tutorial-slides.pdf",
    }
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_files() -> list[Path]:
    entries = list(DOWNLOAD_DIR.iterdir())
    observed = {path.name for path in entries}
    unexpected = observed - ALLOWED_DOWNLOADS
    missing = ALLOWED_DOWNLOADS - observed
    if unexpected:
        raise ValueError(
            "downloads directory contains uncurated files: "
            + ", ".join(sorted(unexpected))
        )
    if missing:
        raise ValueError(
            "downloads directory is missing expected files: "
            + ", ".join(sorted(missing))
        )
    for path in entries:
        if path.is_symlink() or not path.is_file():
            raise ValueError(
                f"curated download is not a regular, non-symlink file: {path.name}"
            )
    files = entries
    return sorted(files, key=lambda item: item.name)


def render_checksums() -> bytes:
    lines = [
        f"{sha256(path)}  {path.relative_to(REPO_ROOT).as_posix()}\n"
        for path in download_files()
    ]
    return "".join(lines).encode("utf-8")


def resolve_output(raw_output: Path) -> Path:
    return raw_output if raw_output.is_absolute() else REPO_ROOT / raw_output


def display_path(path: Path) -> str:
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(path)


def write_atomically(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{path.name}.", dir=path.parent, delete=False
        ) as handle:
            temporary_name = handle.name
            handle.write(payload)
        os.replace(temporary_name, path)
    finally:
        if temporary_name is not None:
            try:
                Path(temporary_name).unlink()
            except FileNotFoundError:
                pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if SHA256SUMS.txt is stale; do not write files",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"checksum path (default: {DEFAULT_OUTPUT.relative_to(REPO_ROOT)})",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = resolve_output(args.output)
    try:
        payload = render_checksums()
    except (OSError, ValueError) as exc:
        print(f"ERROR: cannot generate checksums: {exc}", file=sys.stderr)
        return 1

    if args.check:
        try:
            current = output.read_bytes()
        except OSError as exc:
            print(f"ERROR: cannot read {output}: {exc}", file=sys.stderr)
            return 1
        if current != payload:
            print("ERROR: SHA256SUMS.txt is stale; run `make checksums`", file=sys.stderr)
            return 1
        print(f"PASS: {len(payload.splitlines())} download checksums are current")
        return 0

    try:
        write_atomically(output, payload)
    except OSError as exc:
        print(f"ERROR: cannot write {output}: {exc}", file=sys.stderr)
        return 1
    print(f"WROTE: {display_path(output)} ({len(payload.splitlines())} assets)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
