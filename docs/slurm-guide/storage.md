---
layout: default
title: Storage and Compliance
parent: Core Guide
nav_order: 9
---

# Storage and compliance

Scratch is a fast workspace for active computation. It is not a backup, archive, or compliance decision.

For each run, follow one explicit path: **durable input → scratch staging → computation → validation → durable publication → temporary-file cleanup**. If validation fails, restart from the durable input rather than treating scratch as the source of truth.

## Great Lakes and Armis2 scratch

Scratch has a purge policy and is not durable storage. Keep critical data elsewhere, and do not manipulate timestamps to work around retention rules. Check the current lifecycle, quotas, backup status, and permitted-data boundaries in the dated [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}) before relying on scratch.

Use scratch for:

- active input staging;
- large temporary intermediates;
- task-specific working directories;
- outputs that are still undergoing validation.

Do not use scratch as the only copy of:

- irreplaceable raw data;
- final tables and figures;
- manifests and task metadata needed to reproduce a run;
- validated logs and accounting summaries;
- manuscripts or long-term project records.

## A durable run record

For each important run, preserve:

```text
manifest and exact input identifiers
code version or Git commit
batch scripts and submission command
account/partition and resource request
software environment and versions
array and combine job IDs
stdout/stderr and accounting summary
validated result files and QC report
```

## Sensitive data boundary

Great Lakes and Armis2 have different approved-data boundaries. Verify the project, storage, and access requirements in the [U-M Cluster Reference]({{ site.baseurl }}{% link cluster-reference.md %}) and current ARC documentation before transferring restricted data.

{: .danger }
Moving code to Armis2 does not automatically make every path or external service approved. Confirm where inputs, temporary files, logs, prompts, model outputs, and backups are stored.

## Scratch review checklist

- Which directories contain the only copy of an important file?
- Which active pipelines may pause long enough to cross the current scratch-retention window?
- Are final outputs automatically copied and verified?
- Can a clean rerun reconstruct every temporary file from durable inputs?
- Are permissions appropriate for the project group?
- Are quota and inode limits monitored, especially for many tiny files?

{: .tip }
Make “publish durable outputs” an explicit pipeline stage rather than a manual task remembered at the end.
