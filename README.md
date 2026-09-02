# Fritsche Lab SLURM Playbook

A hands-on, GitHub Pages-ready guide for building measurable and recoverable CPU workflows on U-M's SLURM clusters.

Reach for this playbook when you need to run a first job, choose realistic resources, parallelize independent work, inspect a failure, or recover selected array elements. The dependency-free 24-task example lets you practice each pattern locally before involving the scheduler.

[Open the playbook website](https://fritschelab.github.io/slurm-playbook/) *(available after GitHub Pages is enabled)*

## Audience and scope

If you can work in a Unix shell, this resource gives you a reliable path from one local command to a single-node SLURM job or job array. The worked example requires Bash 3.2+ and Python 3.10+; you need a U-M account, allocation, and valid partition only for live submission.

The examples cover serial and threaded CPU programs, single-node process pools, independent array tasks, one fan-in stage, accounting, and targeted recovery. They do not teach MPI, multi-node jobs, GPUs, cluster administration, or project-specific compliance decisions.

The worked example is tested on **Great Lakes**. The same SLURM pattern transfers to Armis2; the differences that matter here are operational policy and approved-data boundaries, so there is no need to repeat the training run there. Check the [dated U-M cluster reference](docs/cluster-reference.md) before a substantial run.

## What is included

- Searchable Just the Docs website in `docs/`
- A checkpoint-based [Start Here](docs/slurm-guide/quick-start.md) walkthrough
- Copy/paste templates with explanations and guardrails
- Focused Mermaid state diagrams for the job lifecycle, resource-tuning loop, and fan-out/fan-in dependency pattern
- A tested synthetic 24-task array example in `examples/`
- Optional downloadable tutorial slides, quick-reference PDF, and standalone example ZIP
- Repository validation workflow and local smoke tests

## Start locally

From a repository clone:

```bash
git clone https://github.com/FritscheLab/slurm-playbook.git
cd slurm-playbook/examples
./scripts/run_local.sh 3
./scripts/test_local_pipeline.sh
```

`run_local.sh` writes `results/local/task_003.csv`. The test finishes with:

```text
PASS: local outputs, safe cleanup, guarded recovery, and scheduler commands all checked out.
```

If you use the standalone download instead, unzip `slurm-example-pipeline.zip` and run the same commands from its top-level directory:

```bash
unzip slurm-example-pipeline.zip
cd slurm-example-pipeline
./scripts/run_local.sh 3
./scripts/test_local_pipeline.sh
```

Continue with [Start Here](docs/slurm-guide/quick-start.md) for dry-run validation and the Great Lakes acceptance path.

## Publish on GitHub Pages

1. Confirm that these values in `docs/_config.yml` match the repository:
   - `url`
   - `baseurl`
   - `repository`
   - `gh_edit_repository`
   - the repository-specific paths under `aux_links`
2. Commit the files and push the `main` branch to GitHub.
3. In GitHub, open **Settings → Pages**.
4. Under **Build and deployment**, choose **Deploy from a branch**.
5. Select branch **main** and folder **/docs**, then save.
6. In **Settings → Advanced Security**, [enable private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository) so the route in `SECURITY.md` is available.

The site will be published at a URL like:

```text
https://fritschelab.github.io/slurm-playbook/
```

The repository pins the Just the Docs and Mermaid releases to reduce version drift. The included CI workflow checks the documented Python 3.10 minimum, macOS Bash 3.2 compatibility, and a full site build.

## Local preview

The site toolchain is pinned to Ruby 3.3.12. Select that version with your Ruby manager before installing the bundle; the system Ruby included with older macOS releases is not sufficient.

```bash
ruby --version             # should report 3.3.12
cd docs
bundle install
bundle exec jekyll serve
```

Then open `http://127.0.0.1:4000/slurm-playbook/`.

## Validate before publishing

From the repository root:

```bash
make release-assets
make scheduler-free
```

The first command reproducibly rebuilds the standalone ZIP and checksums. The second validates the site structure, shell and Python syntax, local workflow, and packaged artifacts. GitHub Actions runs the same checks on pushes and pull requests, then performs a full Jekyll/Just the Docs build.

## Customize for the lab

- Update cluster/account examples without hard-coding a real shortcode.
- Add lab-specific module or Conda setup to `examples/scripts/runtime_setup.sh`.
- If you fork or rename the repository, update its URL and base path in `docs/_config.yml`.
- Re-check time-sensitive U-M cluster facts and update the verification date on `docs/cluster-reference.md`.

## Feedback and policy corrections

If a command is unclear, an example fails, or a cluster policy appears outdated, [open a GitHub issue](https://github.com/FritscheLab/slurm-playbook/issues/new). Include the page, the command or policy in question, and a non-sensitive log excerpt or official source. Do not include credentials, account names, restricted paths, PHI, or private results.

## AI assistance and validation

This playbook was developed with substantial generative AI assistance. The commands and examples—including those covered by repository tests—are starting points, not guarantees that they will work unchanged in your environment. Cluster configurations, software environments, and policies change. Always begin with a small, non-sensitive test, inspect the logs and results, and confirm current requirements in the official [U-M ARC](https://documentation.its.umich.edu/arc-hpc/slurm-user-guide) and [SchedMD](https://slurm.schedmd.com/) documentation before scaling up.

## License

MIT. See `LICENSE`.
