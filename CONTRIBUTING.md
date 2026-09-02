# Contributing

This playbook is intended to stay practical, source-grounded, and safe for a public lab site.

Before opening a pull request:

1. Explain whether the change comes from a measured job, a tested example, or an official documentation update.
2. Do not include credentials, real shortcodes, PHI, restricted paths, sensitive logs, or private result data.
3. Keep cluster-wide defaults distinct from account-, association-, and project-specific limits.
4. Preserve stable task IDs and one-result-per-task behavior in the example pipeline.
5. Run:

   ```bash
   make release-assets
   make scheduler-free
   ```

6. Preview the Just the Docs site when navigation, callouts, CSS, or Mermaid diagrams change. New diagrams need an accessibility title and description and should be used only when they clarify a relationship that prose cannot.

Time-sensitive cluster facts belong in `docs/cluster-reference.md`, must include a verification date, and must point to the current official source. Other pages should link to that reference rather than copy policy values that can drift.

The runnable pipeline must continue to work with Bash 3.2+ and Python 3.10+. Scheduler-free tests are required for every change to the example. Changes to submission or dependency behavior should also be accepted on Great Lakes before release; a separate Armis2 run is not required because cluster-specific differences are documented as policy and data-boundary concerns.

For a documentation problem or a suspected outdated policy, [open an issue](https://github.com/FritscheLab/slurm-playbook/issues/new) even if you are not ready to propose an edit. Never attach sensitive logs, real accounts, restricted paths, PHI, or private results.
