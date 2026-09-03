#!/usr/bin/env python3
"""Validate task selections and protect pipeline-owned result directories.

This small command-line helper keeps path, manifest, and recovery checks out of
the Bash wrappers so those wrappers remain compatible with macOS Bash 3.2.
Only the Python standard library is used.

The four subcommands form the safety boundary used by the wrappers: ``resolve``
canonicalizes a path, ``prepare`` initializes or cleans an owned run,
``invalidate`` removes named stale publications, and ``select`` validates a
full-run or recovery array specification.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from typing import Final, Sequence

# Reuse the combiner's readers so submission-time recovery checks enforce the
# same manifest and result contracts as the final fan-in stage.
from combine_results import (
    TASK_FILE_PATTERN,
    ValidationError,
    read_manifest,
    read_one_result,
    validate_result_against_manifest,
)

MARKER_NAME: Final[str] = ".slurm-playbook-run"
MARKER_FORMAT: Final[str] = "slurm-playbook-results"
MARKER_VERSION: Final[int] = 1
TASK_TOKEN: Final[re.Pattern[str]] = re.compile(
    r"^(?P<start>[1-9][0-9]*)(?:-(?P<end>[1-9][0-9]*))?$"
)
PROJECT_ROOT: Final[Path] = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Guard result directories and validate SLURM task selections."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    select = subparsers.add_parser(
        "select", help="validate a task selection and print its SLURM array spec"
    )
    select.add_argument("--manifest", required=True, type=Path)
    select.add_argument("--tasks", help="SLURM task IDs/ranges")
    select.add_argument(
        "--results-dir",
        type=Path,
        help="required existing pipeline-owned directory for a partial selection",
    )

    prepare = subparsers.add_parser(
        "prepare", help="initialize or safely clean a pipeline result directory"
    )
    prepare.add_argument("--manifest", required=True, type=Path)
    prepare.add_argument("--results-dir", required=True, type=Path)
    prepare.add_argument("--clean", action="store_true")

    invalidate = subparsers.add_parser(
        "invalidate",
        help="remove stale pipeline outputs after validating directory ownership",
    )
    invalidate.add_argument("--manifest", required=True, type=Path)
    invalidate.add_argument("--results-dir", required=True, type=Path)
    invalidate.add_argument("--task-id", type=int)
    invalidate.add_argument("--aggregates", action="store_true")

    resolve = subparsers.add_parser("resolve", help="print an absolute canonical path")
    resolve.add_argument("--path", required=True, type=Path)

    return parser.parse_args()


def manifest_digest(path: Path) -> str:
    """Hash the complete manifest used to establish result-directory ownership."""

    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def marker_payload(manifest: Path) -> dict[str, object]:
    """Build the small versioned ownership record stored with every run."""

    return {
        "format": MARKER_FORMAT,
        "version": MARKER_VERSION,
        "manifest_sha256": manifest_digest(manifest),
    }


def read_marker(results_dir: Path) -> dict[str, object]:
    """Read and validate a result directory's ownership marker."""

    marker = results_dir / MARKER_NAME
    if not marker.is_file():
        raise ValidationError(
            "this does not look like one of this pipeline's result directories "
            f"(missing {MARKER_NAME}): {results_dir}"
        )
    try:
        payload = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"invalid pipeline ownership marker: {marker}") from exc
    if not isinstance(payload, dict):
        raise ValidationError(f"invalid pipeline ownership marker: {marker}")
    if (
        payload.get("format") != MARKER_FORMAT
        or payload.get("version") != MARKER_VERSION
    ):
        raise ValidationError(f"unrecognized pipeline ownership marker: {marker}")
    return payload


def require_current_marker(results_dir: Path, manifest: Path) -> None:
    """Require ownership by this pipeline and the current manifest version."""

    payload = read_marker(results_dir)
    if payload.get("manifest_sha256") != manifest_digest(manifest):
        raise ValidationError(
            "result directory was created for a different manifest version: "
            f"{results_dir}"
        )


def atomic_write_marker(results_dir: Path, manifest: Path) -> None:
    """Publish the ownership marker without exposing a partially written file."""

    marker = results_dir / MARKER_NAME
    content = json.dumps(marker_payload(manifest), indent=2, sort_keys=True) + "\n"
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{MARKER_NAME}.", suffix=".tmp", dir=results_dir, text=True
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, marker)
    except BaseException:
        temp_path.unlink(missing_ok=True)
        raise


def guard_path(path: Path) -> Path:
    """Resolve a candidate and reject roots that would be dangerous to clean."""

    resolved = path.expanduser().resolve()
    # Individual run directories beneath ``results/`` are allowed, but these
    # broad roots themselves are never valid recursive-cleanup targets.
    protected = {
        Path(resolved.anchor),
        Path.home().resolve(),
        PROJECT_ROOT.resolve(),
        (PROJECT_ROOT / "results").resolve(),
    }
    if resolved in protected:
        raise ValidationError(f"refusing unsafe result directory: {resolved}")
    if resolved in PROJECT_ROOT.resolve().parents:
        raise ValidationError(f"refusing result directory above the project: {resolved}")
    return resolved


def prepare_directory(manifest: Path, results_dir: Path, *, clean: bool) -> Path:
    """Validate, initialize, or explicitly clean one pipeline-owned run."""

    manifest = manifest.resolve()
    # read_manifest validates required columns, positive unique IDs, and a
    # non-empty input before the directory can be marked as pipeline-owned.
    read_manifest(manifest)
    results_dir = guard_path(results_dir)

    if results_dir.exists() and not results_dir.is_dir():
        raise ValidationError(f"result path exists but is not a directory: {results_dir}")

    # --clean is intentionally conservative: a non-empty directory must prove
    # pipeline ownership before recursive removal is allowed.
    if clean and results_dir.exists():
        has_entries = any(results_dir.iterdir())
        if has_entries:
            # Ownership, not just location or spelling, authorizes recursive cleanup.
            read_marker(results_dir)
            shutil.rmtree(results_dir)

    if results_dir.exists():
        marker = results_dir / MARKER_NAME
        entries = list(results_dir.iterdir())
        has_entries = bool(entries)
        initialization_temps = {
            entry
            for entry in entries
            if entry.name.startswith(f".{MARKER_NAME}.")
            and entry.name.endswith(".tmp")
        }
        if marker.exists():
            require_current_marker(results_dir, manifest)
        elif has_entries and len(initialization_temps) != len(entries):
            raise ValidationError(
                "safety stop: the directory is populated but has no pipeline ownership "
                f"marker, so nothing was deleted or overwritten: {results_dir}"
            )
    else:
        # Multiple array elements can reach this point together.
        results_dir.mkdir(parents=True, exist_ok=True)

    # Rewriting the marker is safe under concurrent array starts because each
    # element publishes identical content with an atomic rename.
    atomic_write_marker(results_dir, manifest)
    return results_dir


def invalidate_outputs(
    manifest: Path,
    results_dir: Path,
    *,
    task_id: int | None,
    aggregates: bool,
) -> Path:
    """Remove only validated, pipeline-owned stale publications.

    Keeping this operation beside the ownership guard lets wrappers invalidate
    an earlier result before environment setup can fail. Symlinks are removed
    as directory entries; their targets are never followed.
    """

    manifest = manifest.resolve()
    manifest_rows = read_manifest(manifest)
    results_dir = guard_path(results_dir)
    if not results_dir.is_dir():
        raise ValidationError(f"result directory does not exist: {results_dir}")
    require_current_marker(results_dir, manifest)

    targets: list[Path] = []
    if task_id is not None:
        valid_ids = {int(row["task_id"]) for row in manifest_rows}
        if task_id not in valid_ids:
            raise ValidationError(f"task ID {task_id} is absent from the manifest")
        targets.append(results_dir / f"task_{task_id:03d}.csv")
    if aggregates:
        targets.extend(
            (results_dir / "combined_results.csv", results_dir / "summary.md")
        )
    if not targets:
        raise ValidationError("invalidation needs --task-id and/or --aggregates")

    # Validate every target before changing any of them. A directory or other
    # special entry at one of these exact names needs human inspection.
    for target in targets:
        if not target.is_symlink() and target.exists() and not target.is_file():
            raise ValidationError(
                f"refusing to invalidate a non-file pipeline output: {target}"
            )
    for target in targets:
        target.unlink(missing_ok=True)
    return results_dir


def parse_selection(spec: str | None, valid_ids: Sequence[int]) -> set[int]:
    """Expand a SLURM-style ID/range list and reject gaps or duplicates."""

    all_ids = set(valid_ids)
    if spec is None:
        return all_ids
    if not spec or spec.startswith(",") or spec.endswith(",") or ",," in spec:
        raise ValidationError("invalid empty task token in --tasks")

    selected: set[int] = set()
    for token in spec.split(","):
        match = TASK_TOKEN.fullmatch(token)
        if match is None:
            raise ValidationError(
                f"invalid task token {token!r}; use IDs and ascending ranges"
            )
        start = int(match.group("start"))
        end = int(match.group("end") or start)
        if start > end:
            raise ValidationError(f"descending task range is not allowed: {token}")
        ids_in_range = {task_id for task_id in all_ids if start <= task_id <= end}
        if len(ids_in_range) != end - start + 1:
            raise ValidationError(
                f"task range contains an ID absent from the manifest: {token}"
            )
        overlap = selected.intersection(ids_in_range)
        if overlap:
            duplicate = min(overlap)
            raise ValidationError(f"duplicate task ID in --tasks: {duplicate}")
        selected.update(ids_in_range)
    if not selected:
        raise ValidationError("task selection is empty")
    return selected


def compress_ids(task_ids: Sequence[int] | set[int]) -> str:
    """Compress sorted task IDs into the range syntax accepted by SLURM."""

    ordered = sorted(task_ids)
    ranges: list[str] = []
    start = previous = ordered[0]
    for task_id in ordered[1:]:
        if task_id == previous + 1:
            previous = task_id
            continue
        ranges.append(str(start) if start == previous else f"{start}-{previous}")
        start = previous = task_id
    ranges.append(str(start) if start == previous else f"{start}-{previous}")
    return ",".join(ranges)


def validate_recovery(
    manifest: Path,
    manifest_rows: list[dict[str, str]],
    results_dir: Path,
    selected: set[int],
) -> None:
    """Prove that every task excluded from a recovery is already valid."""

    results_dir = guard_path(results_dir)
    if not results_dir.is_dir():
        raise ValidationError(
            "recovery needs a pre-existing result directory from this pipeline; "
            f"nothing exists at {results_dir}"
        )
    require_current_marker(results_dir, manifest)

    expected_ids = {int(row["task_id"]) for row in manifest_rows}
    unexpected: list[Path] = []
    for candidate in results_dir.glob("task_*.csv"):
        match = TASK_FILE_PATTERN.fullmatch(candidate.name)
        if match is None:
            unexpected.append(candidate)
            continue
        candidate_id = int(match.group(1))
        if (
            candidate_id not in expected_ids
            or candidate.name != f"task_{candidate_id:03d}.csv"
        ):
            unexpected.append(candidate)
    if unexpected:
        names = ", ".join(path.name for path in sorted(unexpected))
        raise ValidationError(f"unexpected task result files: {names}")

    # Selected tasks are allowed to be absent or corrupt—they are precisely the
    # work being repaired. Every unselected task must already be trustworthy.
    for manifest_row in manifest_rows:
        task_id = int(manifest_row["task_id"])
        if task_id in selected:
            continue
        result_path = results_dir / f"task_{task_id:03d}.csv"
        result = read_one_result(result_path)
        validate_result_against_manifest(result, manifest_row, result_path)


def select_tasks(manifest: Path, tasks: str | None, results_dir: Path | None) -> str:
    """Return the SLURM array spec after validating submission safety."""

    manifest = manifest.resolve()
    manifest_rows = read_manifest(manifest)
    valid_ids = [int(row["task_id"]) for row in manifest_rows]
    selected = parse_selection(tasks, valid_ids)
    partial = selected != set(valid_ids)
    if partial:
        if results_dir is None:
            raise ValidationError(
                "a partial --tasks selection is a recovery; add --results-dir pointing "
                "to the existing run you want to repair"
            )
        validate_recovery(manifest, manifest_rows, results_dir, selected)
    return compress_ids(selected)


def main() -> int:
    args = parse_args()
    try:
        # Successful subcommands print exactly one machine-readable value to
        # stdout; the Bash wrappers capture it with command substitution.
        if args.command == "resolve":
            print(guard_path(args.path))
        elif args.command == "prepare":
            print(
                prepare_directory(
                    args.manifest, args.results_dir, clean=bool(args.clean)
                )
            )
        elif args.command == "invalidate":
            print(
                invalidate_outputs(
                    args.manifest,
                    args.results_dir,
                    task_id=args.task_id,
                    aggregates=bool(args.aggregates),
                )
            )
        elif args.command == "select":
            print(select_tasks(args.manifest, args.tasks, args.results_dir))
        else:  # pragma: no cover - argparse constrains this branch
            raise AssertionError(f"unexpected command: {args.command}")
        return 0
    except (ValidationError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
