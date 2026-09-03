#!/usr/bin/env python3
"""Validate and combine one-result-per-task CSV files.

The script fails closed: missing, duplicate, stale, malformed, or unexpected
results prevent publication of the combined output.

Its order is deliberate: establish the expected task set from the manifest,
reject suspicious filenames, validate every expected row, calculate the FDR
columns, and only then publish the summary and combined table.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Final, Iterable, Sequence

# The manifest defines task identity; the result schema carries those fields
# forward with estimates, runtime evidence, and a manifest-row fingerprint.
MANIFEST_REQUIRED: Final[tuple[str, ...]] = (
    "task_id",
    "phenotype",
    "outcome_type",
    "n",
    "seed",
    "work",
    "resource_class",
)
RESULT_REQUIRED: Final[tuple[str, ...]] = (
    "task_id",
    "phenotype",
    "outcome_type",
    "n",
    "seed",
    "work",
    "resource_class",
    "beta",
    "standard_error",
    "z_score",
    "p_value",
    "event_rate",
    "runtime_seconds",
    "manifest_row_sha256",
)
TASK_FILE_PATTERN: Final[re.Pattern[str]] = re.compile(r"^task_(\d+)\.csv$")


class ValidationError(ValueError):
    """Raised when input files do not form one complete, coherent run."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Combine validated task result CSVs.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--run-label", default="local")
    return parser.parse_args()


def _require_columns(
    fieldnames: Iterable[str] | None, required: Sequence[str], context: str
) -> None:
    present = set(fieldnames or [])
    missing = [column for column in required if column not in present]
    if missing:
        raise ValidationError(f"{context} is missing columns: {', '.join(missing)}")


def manifest_fingerprint(row: dict[str, str]) -> str:
    """Recreate the worker's fingerprint from task-defining manifest fields."""

    payload = {key: row[key] for key in MANIFEST_REQUIRED}
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def read_manifest(path: Path) -> list[dict[str, str]]:
    """Read a non-empty manifest with positive, unique task identifiers."""

    if not path.is_file():
        raise ValidationError(f"manifest does not exist: {path}")
    rows: list[dict[str, str]] = []
    seen: set[int] = set()
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        _require_columns(reader.fieldnames, MANIFEST_REQUIRED, "manifest")
        for line_number, row in enumerate(reader, start=2):
            try:
                task_id = int(row["task_id"])
            except ValueError as exc:
                raise ValidationError(
                    f"invalid task_id on manifest line {line_number}"
                ) from exc
            if task_id < 1:
                raise ValidationError(
                    f"task_id must be positive on manifest line {line_number}"
                )
            if task_id in seen:
                raise ValidationError(f"duplicate task_id {task_id} in manifest")
            seen.add(task_id)
            rows.append(row)
    if not rows:
        raise ValidationError("manifest contains no tasks")
    return rows


def read_one_result(path: Path) -> dict[str, str]:
    """Read exactly one result row with the complete worker output schema."""

    if not path.is_file() or path.stat().st_size == 0:
        raise ValidationError(f"missing or empty result: {path}")
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        _require_columns(reader.fieldnames, RESULT_REQUIRED, str(path))
        rows = list(reader)
    if len(rows) != 1:
        raise ValidationError(f"{path} must contain exactly one data row; found {len(rows)}")
    return rows[0]


def validate_numeric(row: dict[str, str], source: Path) -> None:
    """Reject non-finite estimates and values outside their valid domains."""

    try:
        p_value = float(row["p_value"])
        beta = float(row["beta"])
        standard_error = float(row["standard_error"])
        z_score = float(row["z_score"])
        runtime = float(row["runtime_seconds"])
    except ValueError as exc:
        raise ValidationError(f"non-numeric estimate in {source}") from exc
    numeric_values = {
        "beta": beta,
        "standard_error": standard_error,
        "z_score": z_score,
        "p_value": p_value,
        "runtime_seconds": runtime,
    }
    for name, value in numeric_values.items():
        if not math.isfinite(value):
            raise ValidationError(f"{name} must be finite in {source}")
    if not 0.0 <= p_value <= 1.0:
        raise ValidationError(f"p_value outside [0,1] in {source}")
    if standard_error <= 0.0:
        raise ValidationError(f"standard_error must be positive in {source}")
    if runtime < 0.0:
        raise ValidationError(f"runtime_seconds must be non-negative in {source}")
    event_rate_text = row["event_rate"]
    if row["outcome_type"] == "binary" and not event_rate_text:
        raise ValidationError(f"binary event_rate is missing in {source}")
    if event_rate_text:
        try:
            event_rate = float(event_rate_text)
        except ValueError as exc:
            raise ValidationError(f"non-numeric event_rate in {source}") from exc
        if not math.isfinite(event_rate) or not 0.0 <= event_rate <= 1.0:
            raise ValidationError(f"event_rate must be finite and inside [0,1] in {source}")


def validate_result_against_manifest(
    result: dict[str, str], manifest_row: dict[str, str], source: Path
) -> None:
    """Prove that one result is coherent with its exact manifest task."""

    expected_id = int(manifest_row["task_id"])
    try:
        observed_id = int(result["task_id"])
    except ValueError as exc:
        raise ValidationError(f"invalid result task_id in {source}") from exc
    if observed_id != expected_id:
        raise ValidationError(
            f"task ID mismatch in {source}: expected {expected_id}, got {observed_id}"
        )
    for field in ("phenotype", "outcome_type", "n", "seed", "work", "resource_class"):
        if result[field] != manifest_row[field]:
            raise ValidationError(
                f"{field} mismatch for task {expected_id} in {source}: "
                f"expected {manifest_row[field]!r}, got {result[field]!r}"
            )
    expected_hash = manifest_fingerprint(manifest_row)
    if result["manifest_row_sha256"] != expected_hash:
        raise ValidationError(
            f"manifest fingerprint mismatch for task {expected_id}; "
            "the result may belong to a different manifest version"
        )
    validate_numeric(result, source)


def benjamini_hochberg(p_values: Sequence[float]) -> list[float]:
    """Return monotone Benjamini–Hochberg q-values in original task order."""

    # Work from the largest p-value toward the smallest so running_min enforces
    # the monotonicity required of adjusted p-values.
    count = len(p_values)
    order = sorted(range(count), key=lambda index: p_values[index])
    adjusted = [1.0] * count
    running_min = 1.0
    for reverse_rank, index in enumerate(reversed(order), start=1):
        rank = count - reverse_rank + 1
        candidate = p_values[index] * count / rank
        running_min = min(running_min, candidate)
        adjusted[index] = max(0.0, min(1.0, running_min))
    return adjusted


def atomic_write_text(path: Path, content: str) -> None:
    """Write and flush a neighbor temporary file, then rename it atomically."""

    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, text=True
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    except BaseException:
        temp_path.unlink(missing_ok=True)
        raise


def csv_text(rows: list[dict[str, str]], fieldnames: Sequence[str]) -> str:
    """Render the combined rows in memory before any output is published."""

    import io

    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue()


def markdown_summary(
    *, rows: list[dict[str, str]], run_label: str, input_dir: Path
) -> str:
    """Build a compact human-readable QC companion to the combined CSV."""

    significant = [row for row in rows if row["significant_fdr_0_05"] == "yes"]
    fastest = min(rows, key=lambda row: float(row["runtime_seconds"]))
    slowest = max(rows, key=lambda row: float(row["runtime_seconds"]))
    smallest_p = min(rows, key=lambda row: float(row["p_value"]))
    lines = [
        "# Synthetic SLURM Example Summary",
        "",
        f"- **Run label:** `{run_label}`",
        f"- **Validated task results:** {len(rows)}",
        f"- **Input directory:** `{input_dir}`",
        f"- **FDR-significant at 0.05:** {len(significant)}",
        f"- **Smallest p-value:** `{smallest_p['p_value']}` ({smallest_p['phenotype']})",
        f"- **Fastest task:** {fastest['task_id']} ({fastest['runtime_seconds']} seconds)",
        f"- **Slowest task:** {slowest['task_id']} ({slowest['runtime_seconds']} seconds)",
        "",
        "> These are deterministic synthetic training results, not scientific findings.",
        "",
        "## Results by task",
        "",
        "| Task | Phenotype | Type | Beta | p-value | FDR q-value |",
        "|---:|---|---|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            f"| {row['task_id']} | {row['phenotype']} | {row['outcome_type']} | "
            f"{float(row['beta']):.4g} | {float(row['p_value']):.4g} | "
            f"{float(row['fdr_q_value']):.4g} |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    try:
        manifest = args.manifest.resolve()
        input_dir = args.input_dir.resolve()
        output = args.output.resolve()
        summary = args.summary.resolve()
        manifest_rows = read_manifest(manifest)
        if not input_dir.is_dir():
            raise ValidationError(f"input directory does not exist: {input_dir}")

        # Check the directory inventory before reading expected results. This
        # catches mistyped/non-canonical task files rather than silently
        # ignoring evidence that the run directory may be incoherent.
        expected_ids = {int(row["task_id"]) for row in manifest_rows}
        unexpected_files: list[Path] = []
        for candidate in input_dir.glob("task_*.csv"):
            match = TASK_FILE_PATTERN.match(candidate.name)
            if match is None:
                unexpected_files.append(candidate)
                continue
            candidate_id = int(match.group(1))
            canonical_name = f"task_{candidate_id:03d}.csv"
            if candidate_id not in expected_ids or candidate.name != canonical_name:
                unexpected_files.append(candidate)
        if unexpected_files:
            names = ", ".join(path.name for path in sorted(unexpected_files))
            raise ValidationError(f"unexpected task result files: {names}")

        # Iterate in manifest order so the combined output is stable even when
        # array elements finished in a different order.
        combined: list[dict[str, str]] = []
        for manifest_row in manifest_rows:
            task_id = int(manifest_row["task_id"])
            result_path = input_dir / f"task_{task_id:03d}.csv"
            result = read_one_result(result_path)
            validate_result_against_manifest(result, manifest_row, result_path)
            combined.append(result)

        # Add aggregate-only fields after every individual result has passed.
        p_values = [float(row["p_value"]) for row in combined]
        adjusted = benjamini_hochberg(p_values)
        for row, q_value in zip(combined, adjusted, strict=True):
            row["fdr_q_value"] = f"{q_value:.12g}"
            row["significant_fdr_0_05"] = "yes" if q_value <= 0.05 else "no"
            row["run_label"] = args.run_label

        output_fields = list(combined[0].keys())
        # Publish the human-readable QC summary first and the combined CSV last.
        # Downstream steps can treat the final CSV as the completion marker.
        atomic_write_text(
            summary,
            markdown_summary(rows=combined, run_label=args.run_label, input_dir=input_dir),
        )
        atomic_write_text(output, csv_text(combined, output_fields))
        print(
            f"validated_tasks={len(combined)} output={output} summary={summary}",
            flush=True,
        )
        return 0
    except (ValidationError, OSError, csv.Error, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr, flush=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
