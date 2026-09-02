---
layout: default
title: Troubleshooting
parent: Core Guide
nav_order: 8
---

# Troubleshooting

Do not start by doubling memory or walltime. Start with state and reason, then follow the evidence in a fixed order.

## Diagnostic order

1. **State / pending reason**
2. **Element-specific logs**
3. **Exit code**
4. **CPU, memory, and elapsed evidence**
5. **Environment and executable versions**
6. **Working directory, paths, permissions, quotas, and inodes**
7. **Shared-filesystem I/O and concurrency**

## Fast commands

```bash
squeue -j JOB_ID -o '%.20i %.2t %.10M %R'
scontrol show job -dd JOB_ID
sacct -j JOB_ID --units=G \
  -o JobIDRaw,State,Elapsed,AllocCPUS,ReqMem,MaxRSS,TotalCPU,ExitCode
tail -n 200 logs/JOB_SPECIFIC.err
```

## Symptom table

| Symptom | Evidence to collect | Likely causes | Corrective direction |
|---|---|---|---|
| `sbatch` rejects immediately | Full submission error | Invalid account/partition, malformed directive, missing file, permission, limit | Correct the exact rejected field; do not change unrelated resources. |
| Pending with `Priority` | `%R`, priority/fair-share info | Higher-priority eligible jobs | Wait; a smaller accurate request may have more placement opportunities. |
| Pending with `Resources` | Requested nodes/CPU/memory/time/features | No current placement for the envelope | Verify the request and constraints; avoid inferring from queue time alone. |
| Pending with `Dependency` | Upstream job state and dependency string | Upstream still active, failed, or impossible dependency | Inspect upstream. A failed `afterok` dependency will not release normally. |
| Pending with `JobArrayTaskLimit` | Array specification | `%K` cap reached | Usually expected. Wait or revise the cap only after checking I/O/account impact. |
| `OUT_OF_MEMORY` | MaxRSS, stderr, task size | Memory limit exceeded or extreme task | Add evidence-based margin, reduce chunk, or separate outlier class. |
| `TIMEOUT` | Elapsed, progress logs, I/O | Limit too short, stall, or one extreme task | Diagnose progress; increase modestly, split, or checkpoint. |
| Exit code 127 | stderr, `command -v`, module/Conda logs | Command not found or environment not initialized | Load runtime inside batch; print executable path/version. |
| `COMPLETED` but output missing | Script logic, paths, shell safety | Masked failure, wrong workdir, conditional skipped, stale output | Use strict shell behavior and explicit output validation. |
| Log path missing | `--output`, `--error`, parent directory | Parent directory did not exist at submission | Create `logs/` before `sbatch`. |
| Login process killed | Location and resource use | Computation exceeded the shared login envelope | Use `salloc`, debug partition, or Open OnDemand. |
| Many tasks slow together | I/O metrics, concurrency, shared inputs | I/O storm or metadata contention | Lower `%K`, stage/chunk data, reduce tiny files. |
| Input disappeared | Scratch location and access age | Retention policy or cleanup | Restore from durable storage; redesign staging. |

## Login-node computation

Great Lakes and Armis2 login nodes are for file management, editing, and scheduler interaction. Use an interactive allocation, an appropriate development partition, or Open OnDemand for computation. The current login-node envelope and partition rules are linked from the [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}).

## Environment differs in batch

A robust script shows its work:

```bash
module purge
module load YOUR_MODULE/VERSION
source /path/to/conda.sh
conda activate YOUR_ENVIRONMENT

command -v python
python --version
```

Replace `YOUR_MODULE/VERSION`, `/path/to/conda.sh`, and `YOUR_ENVIRONMENT` with the approved setup for the project. They are intentionally visible placeholders.

Avoid relying on `.bashrc` side effects that differ between interactive and non-interactive shells.

## Shared I/O

More CPUs do not repair storage latency. Warning signs include low CPU efficiency, many tasks slowing at once, long startup phases, and heavy simultaneous reads of one file. Reduce concurrent readers, stage shared inputs, aggregate tiny outputs, and use formats designed for partial access.

{: .tip }
Logs are also the best input for an AI troubleshooting assistant. Share the minimal non-sensitive command, batch script, state, exit code, and relevant stderr—not a paraphrase such as “SLURM failed.”
