#!/usr/bin/env bash
# Test the runnable workflow and recovery contract without contacting SLURM.
set -Eeuo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$TEST_DIR/.." && pwd)
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/slurm-playbook-test.XXXXXX")
TEST_ROOT=$(cd "$TEST_ROOT" && pwd -P)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

printf 'test_root=%s\n' "$TEST_ROOT"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

# Help should work without a task ID and identify the wrapper being invoked.
"$SCRIPTS_DIR/run_local.sh" --help | \
  grep -F 'Usage: ./scripts/run_local.sh' >/dev/null || \
  fail 'run_local --help failed before positional validation'
"$SCRIPTS_DIR/submit_pipeline.sh" --help | \
  grep -F 'Usage: ./scripts/submit_pipeline.sh' >/dev/null || \
  fail 'submit_pipeline --help named the wrong wrapper'

# Local execution: one task, then the complete manifest and combine stage.
"$SCRIPTS_DIR/run_local.sh" 3 \
  --results-dir "$TEST_ROOT/one-task" >/dev/null
[[ -s "$TEST_ROOT/one-task/task_003.csv" ]] || \
  fail 'one-task local run did not publish task 3'
if "$SCRIPTS_DIR/run_local.sh" 999 \
  --results-dir "$TEST_ROOT/invalid-task" >/dev/null 2>&1; then
  fail 'local wrapper accepted a task absent from the manifest'
fi
[[ ! -e "$TEST_ROOT/invalid-task/task_999.csv" ]] || \
  fail 'invalid task published a result file'

"$SCRIPTS_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/complete" --clean >/dev/null

python3 - \
  "$TEST_ROOT/complete/combined_results.csv" \
  "$TEST_ROOT/complete/summary.md" \
  "$TEST_ROOT/complete/.slurm-playbook-run" <<'PY_VALIDATE'
from __future__ import annotations

import csv
import json
from pathlib import Path
import sys

csv_path, summary_path, marker_path = map(Path, sys.argv[1:])
with csv_path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
assert len(rows) == 24, f"expected 24 rows, found {len(rows)}"
assert [int(row["task_id"]) for row in rows] == list(range(1, 25))
assert all(len(row["manifest_row_sha256"]) == 64 for row in rows)
assert all(0.0 <= float(row["fdr_q_value"]) <= 1.0 for row in rows)
assert "Validated task results:** 24" in summary_path.read_text(encoding="utf-8")
marker = json.loads(marker_path.read_text(encoding="utf-8"))
assert marker["format"] == "slurm-playbook-results"
assert len(marker["manifest_sha256"]) == 64
PY_VALIDATE

# Failure contract: a failed task must not publish a plausible result.
mkdir -p "$TEST_ROOT/intentional-failure"
if SIMULATE_FAILURE_TASK_ID=11 \
  "$SCRIPTS_DIR/run_local.sh" 11 \
    --results-dir "$TEST_ROOT/intentional-failure" >/dev/null 2>&1; then
  fail 'intentional task failure unexpectedly succeeded'
fi
[[ ! -e "$TEST_ROOT/intentional-failure/task_011.csv" ]] || \
  fail 'failed task published a result file'

# Combine guards: missing work and a stale manifest fingerprint are rejected.
cp -a "$TEST_ROOT/complete" "$TEST_ROOT/incomplete"
rm -f -- "$TEST_ROOT/incomplete/task_024.csv"
if python3 "$PROJECT_ROOT/analysis/combine_results.py" \
  --manifest "$PROJECT_ROOT/data/manifest.tsv" \
  --input-dir "$TEST_ROOT/incomplete" \
  --output "$TEST_ROOT/incomplete/recombined.csv" \
  --summary "$TEST_ROOT/incomplete/recombined.md" \
  --run-label incomplete >/dev/null 2>&1; then
  fail 'combine accepted an incomplete result set'
fi

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
  --output "$TEST_ROOT/stale/recombined.csv" \
  --summary "$TEST_ROOT/stale/recombined.md" \
  --run-label stale >/dev/null 2>&1; then
  fail 'combine accepted a stale manifest fingerprint'
fi
[[ ! -e "$TEST_ROOT/stale/recombined.csv" ]] || \
  fail 'failed combine published an output'

# Cleanup guard: unowned contents survive, while an owned run can be cleaned.
mkdir -p "$TEST_ROOT/unowned"
printf 'keep me\n' > "$TEST_ROOT/unowned/sentinel.txt"
if "$SCRIPTS_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/unowned" --clean >/dev/null 2>&1; then
  fail '--clean accepted a populated directory without an ownership marker'
fi
[[ $(cat "$TEST_ROOT/unowned/sentinel.txt") == 'keep me' ]] || \
  fail '--clean changed an unowned file'

cp -a "$TEST_ROOT/complete" "$TEST_ROOT/owned"
printf 'discard me\n' > "$TEST_ROOT/owned/old-sentinel.txt"
"$SCRIPTS_DIR/run_all_local.sh" \
  --results-dir "$TEST_ROOT/owned" --clean >/dev/null
[[ ! -e "$TEST_ROOT/owned/old-sentinel.txt" ]] || \
  fail '--clean did not clear an owned result directory'
[[ -s "$TEST_ROOT/owned/combined_results.csv" ]] || \
  fail 'clean rerun did not republish combined results'

# Submission dry runs: environment configuration, bounded array, and recovery.
array_dry_run=$(SLURM_ACCOUNT=training SLURM_PARTITION=standard \
  "$SCRIPTS_DIR/submit_array.sh" \
    --max-concurrent 8 --dry-run 2>"$TEST_ROOT/array-dry-run.err")
[[ $array_dry_run == 'array_job=DRY_RUN results_dir=DRY_RUN' ]] || \
  fail "array dry run returned an unexpected receipt: $array_dry_run"
grep -F -- '--array=1-24%8' "$TEST_ROOT/array-dry-run.err" >/dev/null || \
  fail 'array dry run produced the wrong task range or concurrency cap'
grep -F -- 'logs/%x_%A_%a.out' "$TEST_ROOT/array-dry-run.err" >/dev/null || \
  fail 'array dry run omitted task-specific log paths'

# A following option is not a value; reject it before any submission attempt.
for option in --tasks --results-dir --max-concurrent; do
  set +e
  SLURM_ACCOUNT=training SLURM_PARTITION=standard \
    "$SCRIPTS_DIR/submit_array.sh" "$option" --dry-run >/dev/null 2>&1
  status=$?
  set -e
  [[ $status -eq 64 ]] || \
    fail "$option followed by another option returned $status instead of 64"
done

# A partial selection is valid only for a compatible, pipeline-owned run.
if SLURM_ACCOUNT=training SLURM_PARTITION=standard \
  "$SCRIPTS_DIR/submit_pipeline.sh" \
    --tasks 6,11,19 --dry-run >/dev/null 2>&1; then
  fail 'partial recovery was accepted without a results directory'
fi

cp -a "$TEST_ROOT/complete" "$TEST_ROOT/recovery"
rm -f -- \
  "$TEST_ROOT/recovery/task_006.csv" \
  "$TEST_ROOT/recovery/task_011.csv" \
  "$TEST_ROOT/recovery/task_019.csv"
recovery_dry_run=$(SLURM_ACCOUNT=training SLURM_PARTITION=standard \
  "$SCRIPTS_DIR/submit_pipeline.sh" \
    --tasks 6,11,19 \
    --results-dir "$TEST_ROOT/recovery" \
    --max-concurrent 3 \
    --dry-run 2>"$TEST_ROOT/recovery-dry-run.err")
[[ $recovery_dry_run == \
  "array_job=DRY_RUN combine_job=DRY_RUN results_dir=$TEST_ROOT/recovery" ]] || \
  fail "recovery dry run returned an unexpected receipt: $recovery_dry_run"
tr -d '\\' < "$TEST_ROOT/recovery-dry-run.err" \
  > "$TEST_ROOT/recovery-dry-run.normalized"
grep -F -- '--array=6,11,19%3' \
  "$TEST_ROOT/recovery-dry-run.normalized" >/dev/null || \
  fail 'recovery dry run produced the wrong selected array'
grep -F -- '--dependency=afterok:DRY_RUN' \
  "$TEST_ROOT/recovery-dry-run.normalized" >/dev/null || \
  fail 'recovery dry run omitted the replacement combine dependency'

# An invalid unselected result makes the same partial recovery fail closed.
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
if SLURM_ACCOUNT=training SLURM_PARTITION=standard \
  "$SCRIPTS_DIR/submit_pipeline.sh" \
    --tasks 6,11,19 \
    --results-dir "$TEST_ROOT/bad-recovery" \
    --dry-run >/dev/null 2>&1; then
  fail 'partial recovery accepted a stale unselected result'
fi

# Mocked scheduler: array first, then an afterok combine job.
mkdir -p "$TEST_ROOT/mock-bin"
cat > "$TEST_ROOT/mock-bin/sbatch" <<'MOCK_SBATCH'
#!/usr/bin/env bash
{
  printf 'CALL'
  for argument in "$@"; do printf '\t%s' "$argument"; done
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
  '7001_19|TIMEOUT|0:0' \
  '7001_23|CANCELLED by 123|0:15'
MOCK_SACCT
chmod +x "$TEST_ROOT/mock-bin/sbatch" "$TEST_ROOT/mock-bin/sacct"
export MOCK_SBATCH_LOG="$TEST_ROOT/mock-sbatch.log"
mock_submission=$(PATH="$TEST_ROOT/mock-bin:$PATH" \
  SLURM_ACCOUNT=training SLURM_PARTITION=standard \
  "$SCRIPTS_DIR/submit_pipeline.sh" \
    --results-dir "$TEST_ROOT/mock-results")
[[ $mock_submission == \
  "array_job=7001 combine_job=7002 results_dir=$TEST_ROOT/mock-results" ]] || \
  fail "mock scheduler returned an unexpected receipt: $mock_submission"
[[ $(wc -l < "$MOCK_SBATCH_LOG" | tr -d ' ') == 2 ]] || \
  fail 'pipeline did not make exactly two scheduler submissions'
sed -n '1p' "$MOCK_SBATCH_LOG" | grep -F -- '/slurm/array.sbatch' >/dev/null || \
  fail 'array was not the first scheduler submission'
sed -n '2p' "$MOCK_SBATCH_LOG" | \
  grep -F -- '--dependency=afterok:7001' >/dev/null || \
  fail 'combine submission lacked its afterok dependency'

# Failed-task helper: report terminal failures and suggest, but do not submit.
rerun_suggestion=$(PATH="$TEST_ROOT/mock-bin:$PATH" MAX_CONCURRENT=2 \
  "$SCRIPTS_DIR/rerun_failed.sh" 7001 "$TEST_ROOT/recovery")
rerun_normalized=$(printf '%s' "$rerun_suggestion" | tr -d '\\')
[[ $rerun_normalized == *'submit_pipeline.sh'* ]] || \
  fail 'failed-task helper did not suggest the pipeline wrapper'
[[ $rerun_normalized == *'--tasks 6,19,23'* ]] || \
  fail 'failed-task helper suggested the wrong failed task IDs'
[[ $rerun_normalized == *'--max-concurrent 2'* ]] || \
  fail 'failed-task helper ignored MAX_CONCURRENT'
[[ $rerun_normalized == *"--results-dir $TEST_ROOT/recovery"* ]] || \
  fail 'failed-task helper suggested the wrong result directory'

printf '%s\n' \
  'PASS: local workflow, guarded recovery, and scheduler commands checked.'
