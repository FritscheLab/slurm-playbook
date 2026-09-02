#!/usr/bin/env python3
"""Build the downloadable example pipeline ZIP reproducibly.

The archive is derived from ``examples/`` with sorted members, fixed timestamps,
normalized POSIX modes, and uncompressed entries. Avoiding DEFLATE keeps the
output byte-for-byte stable across Python/zlib builds. The example is small, so
the modest size tradeoff is worthwhile. The script intentionally uses only the
Python standard library.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
from pathlib import Path
import stat
import sys
import tempfile
from typing import Final
from zipfile import ZIP_STORED, ZipFile, ZipInfo


REPO_ROOT: Final[Path] = Path(__file__).resolve().parents[1]
SOURCE_DIR: Final[Path] = REPO_ROOT / "examples"
DEFAULT_OUTPUT: Final[Path] = (
    REPO_ROOT / "docs/assets/downloads/slurm-example-pipeline.zip"
)
ARCHIVE_ROOT: Final[Path] = Path("slurm-example-pipeline")
FIXED_TIMESTAMP: Final[tuple[int, int, int, int, int, int]] = (1980, 1, 1, 0, 0, 0)
IGNORED_PARTS: Final[frozenset[str]] = frozenset(
    {"__pycache__", ".pytest_cache", ".mypy_cache"}
)
IGNORED_NAMES: Final[frozenset[str]] = frozenset({".DS_Store"})
IGNORED_SUFFIXES: Final[frozenset[str]] = frozenset({".pyc", ".pyo"})
RUNTIME_DIRS: Final[frozenset[str]] = frozenset({"logs", "results"})


def source_files() -> list[Path]:
    """Return the stable set of source files that belongs in the download."""

    files: list[Path] = []
    for path in SOURCE_DIR.rglob("*"):
        relative = path.relative_to(SOURCE_DIR)
        if path.is_symlink():
            raise ValueError(f"refusing to package symlink: {relative}")
        if not path.is_file():
            continue
        if path.name in IGNORED_NAMES or path.suffix in IGNORED_SUFFIXES or any(
            part in IGNORED_PARTS for part in relative.parts
        ):
            continue
        if relative.parts[0] in RUNTIME_DIRS and path.name != ".gitkeep":
            continue
        files.append(path)
    return sorted(files, key=lambda item: item.relative_to(SOURCE_DIR).as_posix())


def normalized_mode(path: Path) -> int:
    """Preserve executability while normalizing all other permission bits."""

    return 0o755 if path.stat().st_mode & 0o111 else 0o644


def build_archive() -> bytes:
    """Return the complete deterministic ZIP payload."""

    payload = io.BytesIO()
    with ZipFile(
        payload,
        mode="w",
        compression=ZIP_STORED,
        strict_timestamps=True,
    ) as archive:
        for path in source_files():
            relative = path.relative_to(SOURCE_DIR)
            member = (ARCHIVE_ROOT / relative).as_posix()
            info = ZipInfo(member, FIXED_TIMESTAMP)
            info.create_system = 3  # Unix, so extraction tools honor POSIX modes.
            info.create_version = 20
            info.extract_version = 20
            info.compress_type = ZIP_STORED
            info.external_attr = (stat.S_IFREG | normalized_mode(path)) << 16
            info.internal_attr = 0
            info.flag_bits = 0
            info.extra = b""
            info.comment = b""
            archive.writestr(info, path.read_bytes())
    return payload.getvalue()


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
        help="fail if the committed archive differs; do not write files",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"archive path (default: {DEFAULT_OUTPUT.relative_to(REPO_ROOT)})",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = resolve_output(args.output)
    try:
        payload = build_archive()
    except (OSError, ValueError) as exc:
        print(f"ERROR: cannot package example pipeline: {exc}", file=sys.stderr)
        return 1

    digest = hashlib.sha256(payload).hexdigest()
    if args.check:
        try:
            current = output.read_bytes()
        except OSError as exc:
            print(f"ERROR: cannot read {output}: {exc}", file=sys.stderr)
            return 1
        if current != payload:
            print(
                "ERROR: example pipeline ZIP is stale; run "
                "`make package-example` and then `make checksums`",
                file=sys.stderr,
            )
            return 1
        print(f"PASS: example pipeline ZIP is reproducible ({digest})")
        return 0

    try:
        write_atomically(output, payload)
    except OSError as exc:
        print(f"ERROR: cannot write {output}: {exc}", file=sys.stderr)
        return 1
    print(f"WROTE: {display_path(output)} ({digest})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
