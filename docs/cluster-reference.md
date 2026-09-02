---
layout: default
title: U-M Cluster Reference
nav_order: 6
has_toc: true
---

# Great Lakes and Armis2 operational reference

**Checked against U-M ARC documentation: September 2, 2026.** Account, association, partition, and project-specific limits can be stricter than these cluster-wide values.

Use this page as the one place to check U-M-specific values before a run. The worked example is tested on Great Lakes. Its SLURM pattern also applies on Armis2; what you need to re-check there is policy and data handling, not the training computation.

| Setting | Great Lakes | Armis2 |
|---|---:|---:|
| Default walltime | 60 minutes | 60 minutes |
| Default memory per CPU | 768 MB | 768 MB |
| Standard maximum walltime | 14 days | 14 days |
| Max queued jobs per user per account | 5,000 | 5,000 |
| Login-node envelope | 2 CPUs / 4 GB | 2 CPUs / 4 GB |
| Home quota | 80 GB per user | 80 GB per user |
| Scratch quota | 10 TB + 1 million inodes per root account | 10 TB per root account |
| Scratch lifecycle | 60 days without access; no backup | 60 days without access; no backup |
| Debug profile | 1 job/user; 4 hours; 8 CPUs; 40 GB | 1 job/user; 4 hours; up to 8 CPUs / 40 GB |
| Sensitive data | HIPAA/PHI not permitted | Sensitive/HIPAA work with approved storage and compliance |

{: .cluster }
These values are convenient defaults and maxima, not a recommendation to request them. Always specify the smallest defensible CPU, memory, and time envelope for the task.

## A conservative training profile

- Use **debug** for a single smoke or troubleshooting job that fits its limits.
- Use **standard** for a visible parallel array.
- Start with array concurrency around eight or lower, then adjust from I/O and account evidence.
- Pass account and partition through the submission wrapper rather than hard-coding them.

## Login nodes

Login nodes are shared and intended for editing, file management, compilation/setup, and scheduler interaction. Use one of these for computation:

```bash
export SLURM_ACCOUNT='<your-account>'
salloc --account="$SLURM_ACCOUNT" \
       --partition=debug \
       --time=00:30:00 \
       --nodes=1 \
       --ntasks=1 \
       --cpus-per-task=4 \
       --mem=8G
```

Or use Open OnDemand for interactive applications.

## Scratch

Files not accessed for 60 days are subject to purge, and scratch is not backed up. The current ARC policy treats deliberate timestamp manipulation to avoid the purge as misuse. Store durable data elsewhere and build explicit stage-in/stage-out steps.

## Billing and credits

Inaccurate requests waste shared resources and consume credits. Current Great Lakes policy calculates a job's charge from the maximum weighted share of CPU, memory, and GPU. A memory-heavy request can therefore dominate billing even when CPU use is small. Armis2 accounts also have charge and association controls; verify the current project/account terms in ARC documentation or the Research Management Portal.

## Data boundary

- **Great Lakes:** HIPAA/PHI is not permitted. Verify requirements for any other restricted data with the data owner and ARC before transfer.
- **Armis2:** designed for regulated/sensitive workloads, but only when approved storage, access controls, and handling requirements are followed.
- **AI services:** cluster approval does not imply that external APIs are approved for the same data.

## Verify before a large run

- correct account and partition;
- remaining credits or spending limit;
- association-specific job/CPU/memory limits;
- current maintenance notices;
- storage quota and inode usage;
- scratch age and durable copy status;
- approved data location.

See [References]({{ site.baseurl }}{% link references.md %}) for the official ARC pages used for this card.
