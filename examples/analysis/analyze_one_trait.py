#!/usr/bin/env python3
"""Run one deterministic synthetic task selected from a manifest.

This is a training worker, not a scientifically valid association model. Its
purpose is to demonstrate a durable interface: one manifest row in, one
validated result row out, non-zero exit on failure, and atomic publication.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import random
import sys
import tempfile
import time
from typing import Final, Iterable

REQUIRED_COLUMNS: Final[tuple[str, ...]] = (
    "task_id",
    "phenotype",
    "outcome_type",
    "n",
    "seed",
    "work",
    "resource_class",
)
VALID_OUTCOME_TYPES: Final[set[str]] = {"continuous", "binary"}
RESULT_FIELDS: Final[tuple[str, ...]] = (
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


class UserInputError(ValueError):
    """Raised for a malformed manifest or invalid task request."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run one deterministic synthetic task from a TSV manifest."
    )
    parser.add_argument("--manifest", required=True, type=Path, help="TSV manifest")
    parser.add_argument("--task-id", required=True, type=int, help="Stable task ID")
    parser.add_argument("--output", required=True, type=Path, help="Result CSV path")
    return parser.parse_args()


def _require_columns(fieldnames: Iterable[str] | None) -> None:
    present = set(fieldnames or [])
    missing = [column for column in REQUIRED_COLUMNS if column not in present]
    if missing:
        raise UserInputError(f"manifest is missing required columns: {', '.join(missing)}")


def read_manifest_row(manifest: Path, task_id: int) -> dict[str, str]:
    if task_id < 1:
        raise UserInputError("task ID must be a positive integer")
    if not manifest.is_file():
        raise UserInputError(f"manifest does not exist: {manifest}")

    matches: list[dict[str, str]] = []
    seen_ids: set[int] = set()
    with manifest.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        _require_columns(reader.fieldnames)
        for line_number, row in enumerate(reader, start=2):
            try:
                row_id = int(row["task_id"])
            except (TypeError, ValueError) as exc:
                raise UserInputError(
                    f"invalid task_id on manifest line {line_number}: {row.get('task_id')!r}"
                ) from exc
            if row_id in seen_ids:
                raise UserInputError(f"duplicate task_id {row_id} in manifest")
            seen_ids.add(row_id)
            if row_id == task_id:
                matches.append(row)

    if len(matches) != 1:
        raise UserInputError(
            f"task ID {task_id} must match exactly one manifest row; found {len(matches)}"
        )
    return matches[0]


def validate_row(row: dict[str, str]) -> tuple[int, int, int, str]:
    outcome_type = row["outcome_type"].strip().lower()
    if outcome_type not in VALID_OUTCOME_TYPES:
        raise UserInputError(
            f"outcome_type must be one of {sorted(VALID_OUTCOME_TYPES)}; "
            f"got {row['outcome_type']!r}"
        )
    try:
        n = int(row["n"])
        seed = int(row["seed"])
        work = int(row["work"])
    except ValueError as exc:
        raise UserInputError("n, seed, and work must be integers") from exc
    if n < 100:
        raise UserInputError("n must be at least 100 for this demonstration")
    if work < 1:
        raise UserInputError("work must be positive")
    if not row["phenotype"].strip():
        raise UserInputError("phenotype must not be empty")
    return n, seed, work, outcome_type


def row_fingerprint(row: dict[str, str]) -> str:
    payload = {key: row[key] for key in REQUIRED_COLUMNS}
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def logistic(value: float) -> float:
    # Protect against overflow with larger-magnitude inputs.
    if value >= 0:
        exp_neg = math.exp(-value)
        return 1.0 / (1.0 + exp_neg)
    exp_pos = math.exp(value)
    return exp_pos / (1.0 + exp_pos)


def run_synthetic_model(
    *, task_id: int, n: int, seed: int, work: int, outcome_type: str
) -> dict[str, float]:
    """Generate deterministic synthetic observations and fit a simple slope.

    The model intentionally uses only the Python standard library. For binary
    outcomes it reports a linear-probability slope solely to keep the example
    dependency-free; it is not a replacement for logistic regression.
    """

    rng = random.Random(seed)
    true_beta = 0.018 + (task_id % 7) * 0.004 + work * 0.0015
    intercept = -0.7 + (task_id % 5) * 0.18

    sum_x = 0.0
    sum_y = 0.0
    sum_xx = 0.0
    sum_xy = 0.0
    event_count = 0

    # Stream observations so memory stays effectively constant as n grows.
    for _ in range(n):
        x = rng.gauss(0.0, 1.0)
        if outcome_type == "continuous":
            y = true_beta * x + rng.gauss(0.0, 1.0)
        else:
            probability = logistic(intercept + true_beta * x)
            y = 1.0 if rng.random() < probability else 0.0
            event_count += int(y)
        sum_x += x
        sum_y += y
        sum_xx += x * x
        sum_xy += x * y

    mean_x = sum_x / n
    mean_y = sum_y / n
    sxx = sum_xx - n * mean_x * mean_x
    sxy = sum_xy - n * mean_x * mean_y
    if sxx <= 0:
        raise RuntimeError("synthetic predictor variance is zero")

    beta = sxy / sxx

    # A second deterministic pass computes residual variance without retaining
    # the full data. Replaying the same seed reproduces the observations.
    rng = random.Random(seed)
    residual_sum_squares = 0.0
    fitted_intercept = mean_y - beta * mean_x
    for _ in range(n):
        x = rng.gauss(0.0, 1.0)
        if outcome_type == "continuous":
            y = true_beta * x + rng.gauss(0.0, 1.0)
        else:
            probability = logistic(intercept + true_beta * x)
            y = 1.0 if rng.random() < probability else 0.0
        residual = y - (fitted_intercept + beta * x)
        residual_sum_squares += residual * residual

    degrees_of_freedom = n - 2
    residual_variance = residual_sum_squares / degrees_of_freedom
    standard_error = math.sqrt(residual_variance / sxx)
    if standard_error <= 0:
        raise RuntimeError("computed standard error is not positive")
    z_score = beta / standard_error
    p_value = math.erfc(abs(z_score) / math.sqrt(2.0))

    return {
        "beta": beta,
        "standard_error": standard_error,
        "z_score": z_score,
        "p_value": max(0.0, min(1.0, p_value)),
        "event_rate": event_count / n if outcome_type == "binary" else math.nan,
    }


def atomic_write_csv(output: Path, row: dict[str, object]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent, text=True
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=RESULT_FIELDS)
            writer.writeheader()
            writer.writerow(row)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, output)
    except BaseException:
        temp_path.unlink(missing_ok=True)
        raise


def main() -> int:
    args = parse_args()
    started = time.perf_counter()
    try:
        manifest = args.manifest.resolve()
        # Resolve the containing directory, but never the final path component.
        # Resolving the complete path would follow an existing task-file
        # symlink and could unlink or replace a file outside the result run.
        requested_output = args.output.expanduser()
        output = requested_output.parent.resolve() / requested_output.name
        row = read_manifest_row(manifest, args.task_id)
        expected_output_name = f"task_{args.task_id:03d}.csv"
        if output.name != expected_output_name:
            raise UserInputError(
                "output filename must match the selected task: "
                f"expected {expected_output_name!r}, got {output.name!r}"
            )
        if output.is_symlink():
            raise UserInputError(
                f"refusing symbolic-link output target; remove it first: {output}"
            )
        # A retry must never leave an older successful result masquerading as
        # the output of a new failed attempt. Invalidate the selected task's
        # prior publication after its manifest row and canonical filename are
        # validated, but before row validation or simulated/runtime failure.
        output.unlink(missing_ok=True)
        n, seed, work, outcome_type = validate_row(row)

        requested_failure = os.environ.get("SIMULATE_FAILURE_TASK_ID")
        if requested_failure is not None:
            try:
                failure_task = int(requested_failure)
            except ValueError as exc:
                raise UserInputError(
                    "SIMULATE_FAILURE_TASK_ID must be an integer when set"
                ) from exc
            if args.task_id == failure_task:
                raise RuntimeError(
                    f"intentional training failure for task {args.task_id}; no result published"
                )

        print(
            f"task={args.task_id} phenotype={row['phenotype']} "
            f"type={outcome_type} n={n} seed={seed} output={output}",
            flush=True,
        )
        estimates = run_synthetic_model(
            task_id=args.task_id,
            n=n,
            seed=seed,
            work=work,
            outcome_type=outcome_type,
        )
        elapsed = time.perf_counter() - started
        for name in ("beta", "standard_error", "z_score", "p_value"):
            if not math.isfinite(estimates[name]):
                raise RuntimeError(f"computed {name} is not finite")
        if outcome_type == "binary" and not math.isfinite(estimates["event_rate"]):
            raise RuntimeError("computed event_rate is not finite")
        if not math.isfinite(elapsed) or elapsed < 0.0:
            raise RuntimeError("measured runtime is not finite and non-negative")
        result: dict[str, object] = {
            "task_id": args.task_id,
            "phenotype": row["phenotype"],
            "outcome_type": outcome_type,
            "n": n,
            "seed": seed,
            "work": work,
            "resource_class": row["resource_class"],
            "beta": f"{estimates['beta']:.10g}",
            "standard_error": f"{estimates['standard_error']:.10g}",
            "z_score": f"{estimates['z_score']:.10g}",
            "p_value": f"{estimates['p_value']:.12g}",
            "event_rate": (
                "" if math.isnan(estimates["event_rate"]) else f"{estimates['event_rate']:.10g}"
            ),
            "runtime_seconds": f"{elapsed:.6f}",
            "manifest_row_sha256": row_fingerprint(row),
        }
        atomic_write_csv(output, result)
        print(f"published={output} elapsed_seconds={elapsed:.3f}", flush=True)
        return 0
    except (UserInputError, RuntimeError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr, flush=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
