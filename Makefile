PYTHON ?= python3
BASH ?= bash

.PHONY: checksums compile package-example preview release-assets release-check \
	scheduler-free syntax test test-local validate

validate:
	$(PYTHON) tools/validate_repo.py

syntax:
	find examples -type f \( -name '*.sh' -o -name '*.sbatch' \) \
		-exec $(BASH) -n {} \;

compile:
	$(PYTHON) -m compileall -q examples/analysis tools

test: test-local

test-local:
	$(BASH) examples/tests/test_local_pipeline.sh

package-example:
	$(PYTHON) tools/package_example.py

checksums:
	$(PYTHON) tools/update_checksums.py

release-assets: package-example
	$(PYTHON) tools/update_checksums.py

release-check:
	$(PYTHON) tools/package_example.py --check
	$(PYTHON) tools/update_checksums.py --check

# Everything in this target runs on a workstation or hosted runner. It never
# submits a job and does not require Slurm commands to be installed.
scheduler-free: validate syntax compile test-local release-check

preview:
	cd docs && bundle exec jekyll serve
