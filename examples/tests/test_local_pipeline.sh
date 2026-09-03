#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/slurm-playbook-test.XXXXXX")
TEST_ROOT=$(cd "$TEST_ROOT" && pwd -P)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

printf 'test_root=%s\n' "$TEST_ROOT"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

# Verify fail-loud behavior and atomic publication.
mkdir -p "$TEST_ROOT/intentional-failure"
if SIMULATE_FAILURE_TASK_ID=11 RESULTS_DIR="$TEST_ROOT/intentional-failure" \
  "$SCRIPT_DIR/run_local.sh" 11 >/dev/null 2>&1; then
  fail 'intentional task failure unexpectedly succeeded'
fi
[[ ! -e "$TEST_ROOT/intentional-failure/task_011.csv" ]] || \
  fail 'failed task published a result file'

# Invalidation is intentionally narrow: a bad task ID or a non-canonical
# output name must never turn a command-line typo into an unrelated deletion.
printf 'keep this file\n' > "$TEST_ROOT/do-not-delete.txt"
if python3 "$PROJECT_ROOT/analysis/analyze_one_trait.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --task-id 999 \
  --output "$TEST_ROOT/do-not-delete.txt" >/dev/null 2>&1; then
  fail 'worker accepted an invalid task ID and unrelated output path'
fi
[[ $(cat "$TEST_ROOT/do-not-delete.txt") == 'keep this file' ]] || \
  fail 'invalid task selection deleted an unrelated output path'
if python3 "$PROJECT_ROOT/analysis/analyze_one_trait.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --task-id 11 \
  --output "$TEST_ROOT/do-not-delete.txt" >/dev/null 2>&1; then
  fail 'worker accepted a non-canonical output filename'
fi
[[ $(cat "$TEST_ROOT/do-not-delete.txt") == 'keep this file' ]] || \
  fail 'non-canonical output validation deleted an unrelated file'

# A final-component symlink must never redirect invalidation outside the run.
# The worker rejects it without touching either the link or its target.
mkdir -p "$TEST_ROOT/symlink-worker" "$TEST_ROOT/outside-worker"
printf 'outside worker sentinel\n' > "$TEST_ROOT/outside-worker/task_011.csv"
ln -s "$TEST_ROOT/outside-worker/task_011.csv" \
  "$TEST_ROOT/symlink-worker/task_011.csv"
if SIMULATE_FAILURE_TASK_ID=11 python3 \
  "$PROJECT_ROOT/analysis/analyze_one_trait.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --task-id 11 \
  --output "$TEST_ROOT/symlink-worker/task_011.csv" >/dev/null 2>&1; then
  fail 'worker accepted a symbolic-link output target'
fi
[[ $(cat "$TEST_ROOT/outside-worker/task_011.csv") == \
  'outside worker sentinel' ]] || \
  fail 'worker followed a task-output symlink and changed its outside target'
[[ -L "$TEST_ROOT/symlink-worker/task_011.csv" ]] || \
  fail 'worker changed a rejected symbolic-link output entry'

# Execute and combine all manifest rows.
"$SCRIPT_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/complete" \
  --clean >/dev/null

python3 - \
  "$TEST_ROOT/complete/combined_results.csv" \
  "$TEST_ROOT/complete/summary.md" \
  "$PROJECT_ROOT" <<'PY_VALIDATE'
from __future__ import annotations

import csv
from pathlib import Path
import sys

csv_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
project_root = Path(sys.argv[3])
with csv_path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
assert len(rows) == 24, f"expected 24 rows, found {len(rows)}"
assert [int(row["task_id"]) for row in rows] == list(range(1, 25))
assert all(0.0 <= float(row["fdr_q_value"]) <= 1.0 for row in rows)
assert all(len(row["manifest_row_sha256"]) == 64 for row in rows)
summary = summary_path.read_text(encoding="utf-8")
assert "Validated task results:** 24" in summary
assert "not scientific findings" in summary

# A known-value check for the dependency-free BH implementation.
sys.path.insert(0, str(project_root / "analysis"))
from combine_results import benjamini_hochberg  # noqa: E402

assert benjamini_hochberg([0.01, 0.04, 0.03, 0.002]) == [
    0.02,
    0.04,
    0.04,
    0.008,
]
PY_VALIDATE

# A failed retry must invalidate the old result before it fails. Otherwise a
# later combine could silently accept the result from the earlier attempt.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/failed-retry"
[[ -s "$TEST_ROOT/failed-retry/task_011.csv" ]] || fail 'retry fixture is missing task 11'
if SIMULATE_FAILURE_TASK_ID=11 "$SCRIPT_DIR/run_local.sh" 11 \
  --results-dir "$TEST_ROOT/failed-retry" >/dev/null 2>&1; then
  fail 'intentional retry failure unexpectedly succeeded'
fi
[[ ! -e "$TEST_ROOT/failed-retry/task_011.csv" ]] || \
  fail 'failed retry left the older task result in place'
[[ ! -e "$TEST_ROOT/failed-retry/combined_results.csv" ]] || \
  fail 'failed retry left an older combined result in place'

# The wrapper's guarded invalidation removes a task symlink itself, never the
# target it points to, before the worker has a chance to fail.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/symlink-retry"
mkdir -p "$TEST_ROOT/outside-retry"
printf 'outside retry sentinel\n' > "$TEST_ROOT/outside-retry/task_011.csv"
rm -f -- "$TEST_ROOT/symlink-retry/task_011.csv"
ln -s "$TEST_ROOT/outside-retry/task_011.csv" \
  "$TEST_ROOT/symlink-retry/task_011.csv"
if SIMULATE_FAILURE_TASK_ID=11 "$SCRIPT_DIR/run_local.sh" 11 \
  --results-dir "$TEST_ROOT/symlink-retry" >/dev/null 2>&1; then
  fail 'symbolic-link retry failure unexpectedly succeeded'
fi
[[ $(cat "$TEST_ROOT/outside-retry/task_011.csv") == \
  'outside retry sentinel' ]] || \
  fail 'guarded retry followed a task-output symlink outside the result run'
[[ ! -e "$TEST_ROOT/symlink-retry/task_011.csv" && \
   ! -L "$TEST_ROOT/symlink-retry/task_011.csv" ]] || \
  fail 'guarded retry did not invalidate the task symlink itself'

# Guarded invalidation has to happen before runtime setup. This mock delegates
# only ownership/invalidation commands to real Python, then fails the version
# check that runtime_setup.sh performs.
REAL_PYTHON=$(command -v python3)
export REAL_PYTHON
cat > "$TEST_ROOT/guard-only-python" <<'MOCK_GUARD_PYTHON'
#!/usr/bin/env bash
case "${1:-}" in
  *pipeline_guard.py) exec "${REAL_PYTHON:?}" "$@" ;;
  *) exit 1 ;;
esac
MOCK_GUARD_PYTHON
chmod +x "$TEST_ROOT/guard-only-python"

cp -a "$TEST_ROOT/complete" "$TEST_ROOT/setup-failure-local"
if PYTHON_BIN="$TEST_ROOT/guard-only-python" "$SCRIPT_DIR/run_local.sh" 11 \
  --results-dir "$TEST_ROOT/setup-failure-local" >/dev/null 2>&1; then
  fail 'local runtime-setup failure unexpectedly succeeded'
fi
[[ ! -e "$TEST_ROOT/setup-failure-local/task_011.csv" ]] || \
  fail 'runtime-setup failure left an older local task result in place'
[[ ! -e "$TEST_ROOT/setup-failure-local/combined_results.csv" && \
   ! -e "$TEST_ROOT/setup-failure-local/summary.md" ]] || \
  fail 'runtime-setup failure left older local aggregate files in place'

cp -a "$TEST_ROOT/complete" "$TEST_ROOT/setup-failure-array"
if PROJECT_ROOT="$PROJECT_ROOT" \
  MANIFEST="$PROJECT_ROOT/data/manifest.tsv" \
  RESULTS_DIR_OVERRIDE="$TEST_ROOT/setup-failure-array" \
  PYTHON_BIN="$TEST_ROOT/guard-only-python" \
  SLURM_ARRAY_JOB_ID=9100 \
  SLURM_ARRAY_TASK_ID=11 \
  SLURM_JOB_ID=9100 \
  "$PROJECT_ROOT/slurm/array.sbatch" >/dev/null 2>&1; then
  fail 'array runtime-setup failure unexpectedly succeeded'
fi
[[ ! -e "$TEST_ROOT/setup-failure-array/task_011.csv" ]] || \
  fail 'runtime-setup failure left an older array task result in place'
[[ ! -e "$TEST_ROOT/setup-failure-array/combined_results.csv" && \
   ! -e "$TEST_ROOT/setup-failure-array/summary.md" ]] || \
  fail 'runtime-setup failure left older array aggregate files in place'

cp -a "$TEST_ROOT/complete" "$TEST_ROOT/setup-failure-all-local"
if PYTHON_BIN="$TEST_ROOT/guard-only-python" "$SCRIPT_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/setup-failure-all-local" >/dev/null 2>&1; then
  fail 'full local runtime-setup failure unexpectedly succeeded'
fi
[[ ! -e "$TEST_ROOT/setup-failure-all-local/combined_results.csv" && \
   ! -e "$TEST_ROOT/setup-failure-all-local/summary.md" ]] || \
  fail 'runtime-setup failure left older full-run aggregate files in place'

# A full rerun also invalidates its old aggregate before the loop. If an
# element fails halfway through, the previous completion signal must be gone.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/failed-full-rerun"
if SIMULATE_FAILURE_TASK_ID=11 "$SCRIPT_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/failed-full-rerun" >/dev/null 2>&1; then
  fail 'intentional full-rerun failure unexpectedly succeeded'
fi
[[ ! -e "$TEST_ROOT/failed-full-rerun/combined_results.csv" ]] || \
  fail 'failed full rerun left an older combined result in place'
[[ ! -e "$TEST_ROOT/failed-full-rerun/summary.md" ]] || \
  fail 'failed full rerun left an older summary in place'

# Verify that the combine stage rejects a result from a different manifest row.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/stale"
python3 - "$TEST_ROOT/stale/task_001.csv" <<'PY_CORRUPT'
from pathlib import Path
import csv
import sys

path = Path(sys.argv[1])
with path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
rows[0]["manifest_row_sha256"] = "0" * 64
with path.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
PY_CORRUPT

if python3 "$PROJECT_ROOT/analysis/combine_results.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --input-dir "$TEST_ROOT/stale" \
  --output "$TEST_ROOT/stale/should_not_exist.csv" \
  --summary "$TEST_ROOT/stale/should_not_exist.md" \
  --run-label stale >/dev/null 2>&1; then
  fail 'combine accepted a stale manifest fingerprint'
fi
[[ ! -e "$TEST_ROOT/stale/should_not_exist.csv" ]] || \
  fail 'failed combine published an output'

# NaN and infinity compare surprisingly in ordinary range checks, so verify
# that aggregation explicitly rejects non-finite values.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/non-finite"
python3 - "$TEST_ROOT/non-finite/task_001.csv" <<'PY_NON_FINITE'
from pathlib import Path
import csv
import sys

path = Path(sys.argv[1])
with path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
rows[0]["beta"] = "nan"
with path.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
PY_NON_FINITE

if python3 "$PROJECT_ROOT/analysis/combine_results.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --input-dir "$TEST_ROOT/non-finite" \
  --output "$TEST_ROOT/non-finite/should_not_exist.csv" \
  --summary "$TEST_ROOT/non-finite/should_not_exist.md" \
  --run-label non-finite >/dev/null 2>&1; then
  fail 'combine accepted a non-finite estimate'
fi

# Binary event rate is part of the result contract, not an optional decoration.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/missing-event-rate"
python3 - "$TEST_ROOT/missing-event-rate/task_006.csv" <<'PY_MISSING_EVENT_RATE'
from pathlib import Path
import csv
import sys

path = Path(sys.argv[1])
with path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
fieldnames = [name for name in rows[0] if name != "event_rate"]
with path.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)
PY_MISSING_EVENT_RATE
if python3 "$PROJECT_ROOT/analysis/combine_results.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --input-dir "$TEST_ROOT/missing-event-rate" \
  --output "$TEST_ROOT/missing-event-rate/should_not_exist.csv" \
  --summary "$TEST_ROOT/missing-event-rate/should_not_exist.md" \
  --run-label missing-event-rate >/dev/null 2>&1; then
  fail 'combine accepted a binary result without event_rate'
fi

# Relative output paths belong to the caller, even though the wrapper changes
# to the example project before launching the worker.
mkdir -p "$TEST_ROOT/caller"
(
  cd "$TEST_ROOT/caller"
  "$SCRIPT_DIR/run_local.sh" 3 --results-dir relative-output >/dev/null
)
[[ -s "$TEST_ROOT/caller/relative-output/task_003.csv" ]] || \
  fail 'run_local resolved a relative output path against the wrong directory'

# --clean refuses a populated unowned directory and leaves its contents alone.
mkdir -p "$TEST_ROOT/keep-me"
printf 'important fixture\n' > "$TEST_ROOT/keep-me/do-not-delete.txt"
if "$SCRIPT_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/keep-me" --clean >/dev/null 2>&1; then
  fail '--clean accepted a populated directory without an ownership marker'
fi
[[ $(cat "$TEST_ROOT/keep-me/do-not-delete.txt") == 'important fixture' ]] || \
  fail '--clean changed a file in an unowned directory'

# The same cleanup is allowed for a marked directory created by this pipeline.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/owned-clean"
printf 'discard me\n' > "$TEST_ROOT/owned-clean/old-sentinel.txt"
"$SCRIPT_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/owned-clean" --clean >/dev/null
[[ ! -e "$TEST_ROOT/owned-clean/old-sentinel.txt" ]] || \
  fail '--clean did not clear a pipeline-owned directory'
[[ -s "$TEST_ROOT/owned-clean/combined_results.csv" ]] || \
  fail 'clean rerun did not republish combined results'

# Run the wrapper with Apple's stock Bash when it is available. This catches
# accidental use of Bash 4 features such as associative arrays.
MAC_BASH=/bin/bash
[[ -x $MAC_BASH ]] || MAC_BASH=$(command -v bash)
mac_dry_run=$($MAC_BASH "$SCRIPT_DIR/submit_array.sh" \
  --account training \
  --partition standard \
  --max-concurrent 8 \
  --dry-run 2>"$TEST_ROOT/mac-dry-run.err")
[[ $mac_dry_run == DRY_RUN ]] || fail 'stock-Bash dry run returned unexpected stdout'
grep -F -- '--array=1-24%8' "$TEST_ROOT/mac-dry-run.err" >/dev/null || \
  fail 'default array spec was not derived from the manifest IDs'
grep -F -- '--chdir=' "$TEST_ROOT/mac-dry-run.err" >/dev/null || \
  fail 'array submission omitted an explicit project working directory'
grep -F -- '--output=' "$TEST_ROOT/mac-dry-run.err" >/dev/null || \
  fail 'array submission omitted an explicit output option'
grep -F -- 'logs/%x_%A_%a.out' "$TEST_ROOT/mac-dry-run.err" >/dev/null || \
  fail 'array submission omitted the absolute log path'

# Both common option spellings are supported. Several playbook pages use
# --option=value, while the standalone README also demonstrates --option value.
equals_array_dry_run=$($MAC_BASH "$SCRIPT_DIR/submit_array.sh" \
  --account=training \
  --partition=standard \
  --max-concurrent=8 \
  --python="$REAL_PYTHON" \
  --dry-run 2>"$TEST_ROOT/equals-array-dry-run.err")
[[ $equals_array_dry_run == DRY_RUN ]] || \
  fail '--option=value array dry run returned unexpected stdout'
grep -F -- '--array=1-24%8' "$TEST_ROOT/equals-array-dry-run.err" >/dev/null || \
  fail '--option=value array submission produced the wrong array spec'

# Prove that selection generation follows IDs, rather than assuming 1..N.
python3 - "$PROJECT_ROOT/data/manifest.tsv" "$TEST_ROOT/noncontiguous.tsv" <<'PY_MANIFEST'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
kept = [source[0], *(line for line in source[1:] if not line.startswith("2\t"))]
Path(sys.argv[2]).write_text("\n".join(kept) + "\n", encoding="utf-8")
PY_MANIFEST
selection=$(python3 "$PROJECT_ROOT/analysis/pipeline_guard.py" select \
  --manifest "$TEST_ROOT/noncontiguous.tsv")
[[ $selection == '1,3-24|0' ]] || \
  fail "non-contiguous manifest produced the wrong array selection: $selection"

if "$SCRIPT_DIR/submit_array.sh" \
  --account training \
  --partition standard \
  --tasks 25 \
  --dry-run >/dev/null 2>&1; then
  fail 'submission wrapper accepted a task absent from the manifest'
fi

# A partial recovery must point to a pre-existing, pipeline-owned result set.
if "$SCRIPT_DIR/submit_pipeline.sh" \
  --account training \
  --partition standard \
  --tasks 6,11,19 \
  --dry-run >/dev/null 2>&1; then
  fail 'pipeline wrapper accepted partial tasks without --results-dir'
fi

if "$SCRIPT_DIR/submit_pipeline.sh" \
  --account training \
  --partition standard \
  --tasks 6,11,19 \
  --results-dir "$TEST_ROOT/not-created" \
  --dry-run >/dev/null 2>&1; then
  fail 'pipeline wrapper accepted a new recovery directory'
fi

mkdir -p "$TEST_ROOT/empty-recovery"
if "$SCRIPT_DIR/submit_pipeline.sh" \
  --account training \
  --partition standard \
  --tasks 6,11,19 \
  --results-dir "$TEST_ROOT/empty-recovery" \
  --dry-run >/dev/null 2>&1; then
  fail 'pipeline wrapper accepted an empty unowned recovery directory'
fi

# Even an owned recovery directory is rejected when an unselected result is
# stale or malformed.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/bad-recovery"
python3 - "$TEST_ROOT/bad-recovery/task_001.csv" <<'PY_BAD_RECOVERY'
from pathlib import Path
import csv
import sys

path = Path(sys.argv[1])
with path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
rows[0]["manifest_row_sha256"] = "f" * 64
with path.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
PY_BAD_RECOVERY
if "$SCRIPT_DIR/submit_pipeline.sh" \
  --account training \
  --partition standard \
  --tasks 6,11,19 \
  --results-dir "$TEST_ROOT/bad-recovery" \
  --dry-run >/dev/null 2>&1; then
  fail 'pipeline wrapper accepted a stale unselected recovery result'
fi

# Missing/stale files for the selected IDs are allowed; every unselected task
# must still validate before the replacement array and combine are scheduled.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/valid-recovery"
rm -f -- \
  "$TEST_ROOT/valid-recovery/task_006.csv" \
  "$TEST_ROOT/valid-recovery/task_011.csv" \
  "$TEST_ROOT/valid-recovery/task_019.csv"
(
  cd "$TEST_ROOT"
  recovery_dry_run=$($MAC_BASH "$SCRIPT_DIR/submit_pipeline.sh" \
    --account=training \
    --partition=standard \
    --tasks=6,11,19 \
    --max-concurrent=3 \
    --results-dir=valid-recovery \
    --python="$REAL_PYTHON" \
    --dry-run 2>"$TEST_ROOT/recovery-dry-run.err")
  [[ $recovery_dry_run == *"results_dir=$TEST_ROOT/valid-recovery"* ]] || \
    fail 'recovery dry run did not preserve the caller-relative result path'
)
tr -d '\\' < "$TEST_ROOT/recovery-dry-run.err" > "$TEST_ROOT/recovery-dry-run.normalized"
grep -F -- '--array=6,11,19%3' "$TEST_ROOT/recovery-dry-run.normalized" >/dev/null || \
  fail 'recovery dry run produced the wrong selected array spec'
grep -F -- '--dependency=afterok:<array_job_id>' \
  "$TEST_ROOT/recovery-dry-run.normalized" >/dev/null || \
  fail 'recovery dry run omitted the replacement fan-in dependency'

# Mock sbatch so the scheduler-facing command semantics are tested without a
# cluster. The wrapper must submit the array first and combine second.
mkdir -p "$TEST_ROOT/mock-bin"
cat > "$TEST_ROOT/mock-bin/sbatch" <<'MOCK_SBATCH'
#!/usr/bin/env bash
{
  printf 'CALL'
  for argument in "$@"; do
    printf '\t%s' "$argument"
  done
  printf '\n'
} >> "${MOCK_SBATCH_LOG:?}"
case " $* " in
  *'/slurm/array.sbatch '*) printf '7001\n' ;;
  *'/slurm/combine.sbatch '*) printf '7002\n' ;;
  *) printf 'unexpected mock sbatch call\n' >&2; exit 2 ;;
esac
MOCK_SBATCH
cat > "$TEST_ROOT/mock-bin/sacct" <<'MOCK_SACCT'
#!/usr/bin/env bash
printf '%s\n' \
  '7001_6|FAILED|2:0' \
  '7001_11|COMPLETED|0:0' \
  '7001_19|TIMEOUT|0:0' \
  '7001_23|CANCELLED by 123|0:15'
MOCK_SACCT
chmod +x "$TEST_ROOT/mock-bin/sbatch" "$TEST_ROOT/mock-bin/sacct"
export MOCK_SBATCH_LOG="$TEST_ROOT/mock-sbatch.log"
mock_submission=$(PATH="$TEST_ROOT/mock-bin:$PATH" \
  "$SCRIPT_DIR/submit_pipeline.sh" \
    --account training \
    --partition standard \
    --tasks 6,11,19 \
    --max-concurrent 3 \
    --results-dir "$TEST_ROOT/valid-recovery")
[[ $mock_submission == \
  "array_job=7001 combine_job=7002 results_dir=$TEST_ROOT/valid-recovery" ]] || \
  fail "mock scheduler returned unexpected pipeline output: $mock_submission"
[[ $(wc -l < "$MOCK_SBATCH_LOG" | tr -d ' ') == 2 ]] || \
  fail 'pipeline did not make exactly two scheduler submissions'
sed -n '1p' "$MOCK_SBATCH_LOG" | grep -F -- '--array=6,11,19%3' >/dev/null || \
  fail 'mocked array submission had the wrong selection'
sed -n '1p' "$MOCK_SBATCH_LOG" | grep -F -- "--chdir=$PROJECT_ROOT" >/dev/null || \
  fail 'mocked array submission had the wrong working directory'
sed -n '2p' "$MOCK_SBATCH_LOG" | grep -F -- '--dependency=afterok:7001' >/dev/null || \
  fail 'mocked combine submission lacked afterok on the replacement array'

# The diagnostic helper suggests the full recovery pipeline so every repair
# includes a replacement combine job.
rerun_suggestion=$(PATH="$TEST_ROOT/mock-bin:$PATH" \
  "$SCRIPT_DIR/rerun_failed.sh" 7001 \
    --results-dir "$TEST_ROOT/valid-recovery" \
    --max-concurrent 2)
rerun_normalized=$(printf '%s' "$rerun_suggestion" | tr -d '\\')
[[ $rerun_normalized == *'submit_pipeline.sh'* ]] || \
  fail 'failed-task helper did not suggest submit_pipeline.sh'
[[ $rerun_normalized == *'--tasks 6,19,23'* ]] || \
  fail 'failed-task helper suggested the wrong failed task IDs'
[[ $rerun_normalized == *'--max-concurrent 2'* ]] || \
  fail 'failed-task helper dropped the requested concurrency cap'
[[ $rerun_normalized == \
  *'SLURM_ACCOUNT=YOUR_ACCOUNT SLURM_PARTITION=YOUR_PARTITION'* ]] || \
  fail 'failed-task helper emitted unsafe or unclear account placeholders'

printf '%s\n' \
  'PASS: local outputs, safe cleanup, guarded recovery, and scheduler commands all checked out.'
