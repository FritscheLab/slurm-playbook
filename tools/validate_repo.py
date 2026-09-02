#!/usr/bin/env python3
"""Structural validator for the SLURM playbook repository.

The checks intentionally use only the Python standard library so they run in a
fresh GitHub Actions runner before Ruby/Jekyll dependencies are installed.
"""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import re
import stat
import sys
from typing import Final
from zipfile import BadZipFile, ZIP_STORED, ZipFile

REPO_ROOT: Final[Path] = Path(__file__).resolve().parents[1]
DOCS_ROOT: Final[Path] = REPO_ROOT / "docs"
ALLOWED_DOWNLOAD_NAMES: Final[frozenset[str]] = frozenset(
    {
        "slurm-example-pipeline.zip",
        "slurm-session-cheatsheets.pdf",
        "slurm-tutorial-slides.pdf",
    }
)

REQUIRED_FILES: Final[tuple[str, ...]] = (
    "README.md",
    "LICENSE",
    "CONTRIBUTING.md",
    "SECURITY.md",
    ".editorconfig",
    ".ruby-version",
    "Makefile",
    "SHA256SUMS.txt",
    ".github/workflows/validate.yml",
    ".github/dependabot.yml",
    ".github/pull_request_template.md",
    "docs/_config.yml",
    "docs/Gemfile",
    "docs/index.md",
    "docs/quick-reference.md",
    "docs/example-pipeline.md",
    "docs/references.md",
    "docs/assets/downloads/slurm-tutorial-slides.pdf",
    "docs/assets/downloads/slurm-session-cheatsheets.pdf",
    "docs/assets/downloads/slurm-example-pipeline.zip",
    "examples/README.md",
    "examples/data/manifest.tsv",
    "examples/analysis/analyze_one_trait.py",
    "examples/analysis/combine_results.py",
    "examples/scripts/test_local_pipeline.sh",
    "examples/slurm/array.sbatch",
    "tools/package_example.py",
    "tools/update_checksums.py",
)

FORBIDDEN_PUBLIC_PATHS: Final[tuple[str, ...]] = ("source-material",)

LINK_TAG_RE: Final[re.Pattern[str]] = re.compile(
    r"{%\s*link\s+([^\s%]+)\s*%}"
)
MARKDOWN_LINK_RE: Final[re.Pattern[str]] = re.compile(
    r"!?\[[^\]]*\]\(([^)]+)\)"
)
BASEURL_ASSET_RE: Final[re.Pattern[str]] = re.compile(
    r"{{\s*site\.baseurl\s*}}(/assets/[^\s\"')}>]+)"
)
MERMAID_BLOCK_RE: Final[re.Pattern[str]] = re.compile(
    r"```mermaid\s*\n(.*?)\n```", re.DOTALL
)
FRONT_MATTER_RE: Final[re.Pattern[str]] = re.compile(
    r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL
)


class Validator:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.pages_checked = 0
        self.mermaid_checked = 0
        self.links_checked = 0

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def check_required_files(self) -> None:
        for relative in REQUIRED_FILES:
            path = REPO_ROOT / relative
            if not path.is_file():
                self.error(f"missing required file: {relative}")
            elif path.stat().st_size == 0:
                self.error(f"required file is empty: {relative}")

    def check_forbidden_public_files(self) -> None:
        found: set[Path] = set()
        for relative in FORBIDDEN_PUBLIC_PATHS:
            path = REPO_ROOT / relative
            if path.exists():
                found.add(path)
        for path in DOCS_ROOT.rglob("*"):
            normalized_name = path.name.casefold()
            if path.is_file() and (
                ("meeting" in normalized_name and "minutes" in normalized_name)
                or ("zoom" in normalized_name and "summary" in normalized_name)
            ):
                found.add(path)
        for path in sorted(found):
            self.error(
                "private source material must not ship in the public repository: "
                f"{path.relative_to(REPO_ROOT)}"
            )

        download_dir = DOCS_ROOT / "assets/downloads"
        if download_dir.is_dir():
            entries = list(download_dir.iterdir())
            observed = {path.name for path in entries}
            unexpected = observed - ALLOWED_DOWNLOAD_NAMES
            missing = ALLOWED_DOWNLOAD_NAMES - observed
            if unexpected:
                self.error(
                    "downloads directory contains uncurated files: "
                    f"{sorted(unexpected)}"
                )
            if missing:
                self.error(
                    "downloads directory is missing curated files: "
                    f"{sorted(missing)}"
                )
            for path in entries:
                if path.name in ALLOWED_DOWNLOAD_NAMES and (
                    path.is_symlink() or not path.is_file()
                ):
                    self.error(
                        "curated download must be a regular, non-symlink file: "
                        f"{path.relative_to(REPO_ROOT)}"
                    )

    @staticmethod
    def parse_front_matter(text: str) -> dict[str, str]:
        match = FRONT_MATTER_RE.search(text)
        if match is None:
            return {}
        values: dict[str, str] = {}
        for raw_line in match.group(1).splitlines():
            if not raw_line.strip() or raw_line.lstrip().startswith("#"):
                continue
            if raw_line.startswith((" ", "\t", "-")) or ":" not in raw_line:
                continue
            key, value = raw_line.split(":", 1)
            values[key.strip()] = value.strip().strip('"\'')
        return values

    def check_front_matter_and_navigation(self) -> None:
        pages: list[tuple[Path, dict[str, str]]] = []
        titles: set[str] = set()
        for path in sorted(DOCS_ROOT.rglob("*.md")):
            if "assets" in path.parts:
                continue
            text = path.read_text(encoding="utf-8")
            metadata = self.parse_front_matter(text)
            relative = path.relative_to(REPO_ROOT)
            if not metadata:
                self.error(f"missing YAML front matter: {relative}")
                continue
            if not metadata.get("title"):
                self.error(f"front matter has no title: {relative}")
            if metadata.get("layout") != "default":
                self.error(f"layout should be 'default': {relative}")
            title = metadata.get("title")
            if title:
                titles.add(title)
            pages.append((path, metadata))
            self.pages_checked += 1

        for path, metadata in pages:
            parent = metadata.get("parent")
            if parent and parent not in titles:
                self.error(
                    f"navigation parent {parent!r} has no matching page title: "
                    f"{path.relative_to(REPO_ROOT)}"
                )

    def check_jekyll_link_tags(self) -> None:
        for path in sorted(DOCS_ROOT.rglob("*")):
            if not path.is_file() or path.suffix not in {".md", ".html"}:
                continue
            text = path.read_text(encoding="utf-8")
            for target in LINK_TAG_RE.findall(text):
                self.links_checked += 1
                resolved = DOCS_ROOT / target
                if not resolved.is_file():
                    self.error(
                        f"broken Jekyll link target {target!r} in "
                        f"{path.relative_to(REPO_ROOT)}"
                    )

    def check_local_asset_links(self) -> None:
        for path in sorted(DOCS_ROOT.rglob("*")):
            if not path.is_file() or path.suffix not in {".md", ".html", ".yml"}:
                continue
            text = path.read_text(encoding="utf-8")

            for asset in BASEURL_ASSET_RE.findall(text):
                self.links_checked += 1
                target = DOCS_ROOT / asset.lstrip("/")
                if not target.is_file():
                    self.error(
                        f"missing baseurl asset {asset!r} referenced by "
                        f"{path.relative_to(REPO_ROOT)}"
                    )

            if path.suffix != ".md":
                continue
            for raw_target in MARKDOWN_LINK_RE.findall(text):
                target = raw_target.strip().split()[0].strip("<>")
                if not target or target.startswith(("#", "http://", "https://", "mailto:")):
                    continue
                if "{{" in target or "{%" in target:
                    continue
                target_without_fragment = target.split("#", 1)[0]
                if not target_without_fragment:
                    continue
                self.links_checked += 1
                candidate = (
                    DOCS_ROOT / target_without_fragment.lstrip("/")
                    if target_without_fragment.startswith("/")
                    else path.parent / target_without_fragment
                )
                if not candidate.exists():
                    self.error(
                        f"broken local Markdown link {target!r} in "
                        f"{path.relative_to(REPO_ROOT)}"
                    )

    def check_mermaid(self) -> None:
        for path in sorted(DOCS_ROOT.rglob("*.md")):
            if "assets" in path.parts:
                continue
            text = path.read_text(encoding="utf-8")
            openings = text.count("```mermaid")
            blocks = MERMAID_BLOCK_RE.findall(text)
            if openings != len(blocks):
                self.error(
                    f"unbalanced or malformed Mermaid fence in {path.relative_to(REPO_ROOT)}"
                )
            for index, block in enumerate(blocks, start=1):
                self.mermaid_checked += 1
                if "accTitle:" not in block:
                    self.error(
                        f"Mermaid block {index} lacks accTitle in {path.relative_to(REPO_ROOT)}"
                    )
                if "accDescr:" not in block:
                    self.error(
                        f"Mermaid block {index} lacks accDescr in {path.relative_to(REPO_ROOT)}"
                    )
                first_nonempty = next(
                    (line.strip() for line in block.splitlines() if line.strip()), ""
                )
                if re.fullmatch(
                    r"(?:flowchart|graph)\s+(?:TD|TB|LR)",
                    first_nonempty,
                    re.IGNORECASE,
                ) or first_nonempty.startswith("sequenceDiagram"):
                    self.error(
                        f"Mermaid block {index} uses a disallowed generic layout in "
                        f"{path.relative_to(REPO_ROOT)}: {first_nonempty!r}"
                    )
                if not first_nonempty.startswith(
                    ("flowchart", "graph", "sequenceDiagram", "stateDiagram", "classDiagram")
                ):
                    self.warn(
                        f"unrecognized Mermaid diagram declaration in "
                        f"{path.relative_to(REPO_ROOT)} block {index}: {first_nonempty!r}"
                    )

    def check_mermaid_config(self) -> None:
        path = DOCS_ROOT / "_includes/mermaid_config.js"
        try:
            config = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            self.error(f"invalid Mermaid configuration JSON: {exc}")
            return
        if config.get("startOnLoad") is not True:
            self.error("Mermaid startOnLoad should be true")
        if config.get("securityLevel") not in {"strict", "loose", "antiscript", "sandbox"}:
            self.error("Mermaid securityLevel is missing or invalid")

    def check_pinned_versions(self) -> None:
        config_path = DOCS_ROOT / "_config.yml"
        text = config_path.read_text(encoding="utf-8")
        if not re.search(
            r"remote_theme:\s*just-the-docs/just-the-docs@v\d+\.\d+\.\d+", text
        ):
            self.error("Just the Docs remote_theme should be pinned to a release")
        if not re.search(r"mermaid:\s*\n\s+version:\s*[\"']?\d+\.\d+\.\d+", text):
            self.error("Mermaid version should be pinned in docs/_config.yml")

        ruby_path = REPO_ROOT / ".ruby-version"
        gemfile_path = DOCS_ROOT / "Gemfile"
        workflow_path = REPO_ROOT / ".github/workflows/validate.yml"
        try:
            ruby_version = ruby_path.read_text(encoding="utf-8").strip()
            gemfile = gemfile_path.read_text(encoding="utf-8")
            workflow = workflow_path.read_text(encoding="utf-8")
        except OSError as exc:
            self.error(f"cannot validate Ruby version alignment: {exc}")
            return
        if not re.fullmatch(r"\d+\.\d+\.\d+", ruby_version):
            self.error(".ruby-version should pin an exact X.Y.Z release")
        if not re.search(
            rf"^ruby\s+[\"']{re.escape(ruby_version)}[\"']\s*$",
            gemfile,
            re.MULTILINE,
        ):
            self.error("docs/Gemfile Ruby version does not match .ruby-version")
        if not re.search(
            rf"^\s*ruby-version:\s*[\"']?{re.escape(ruby_version)}[\"']?\s*$",
            workflow,
            re.MULTILINE,
        ):
            self.error("CI Ruby version does not match .ruby-version")

    def check_manifest(self) -> None:
        path = REPO_ROOT / "examples/data/manifest.tsv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            required = {
                "task_id",
                "phenotype",
                "outcome_type",
                "n",
                "seed",
                "work",
                "resource_class",
            }
            missing = required - set(reader.fieldnames or [])
            if missing:
                self.error(f"example manifest missing columns: {sorted(missing)}")
                return
            rows = list(reader)
        try:
            task_ids = [int(row["task_id"]) for row in rows]
        except ValueError:
            self.error("example manifest contains a non-integer task_id")
            return
        if task_ids != list(range(1, 25)):
            self.error(
                "example manifest task IDs must be the stable ordered sequence 1..24; "
                f"found {task_ids}"
            )
        if len({row["phenotype"] for row in rows}) != len(rows):
            self.error("example manifest phenotypes must be unique")
        if not all(row["outcome_type"] in {"continuous", "binary"} for row in rows):
            self.error("example manifest has an unsupported outcome_type")

    def check_batch_portability(self) -> None:
        for path in sorted((REPO_ROOT / "examples/slurm").glob("*.sbatch")):
            text = path.read_text(encoding="utf-8")
            if "#SBATCH --account=" in text or "#SBATCH --partition=" in text:
                self.error(
                    f"reusable batch file hard-codes account/partition: "
                    f"{path.relative_to(REPO_ROOT)}"
                )
            if "set -Eeuo pipefail" not in text:
                self.error(f"batch file does not fail loudly: {path.relative_to(REPO_ROOT)}")
            if "#SBATCH --output=" in text and "logs/" in text:
                # The wrappers and README must make the directory before submission.
                pass


    def check_example_archive(self) -> None:
        archive = DOCS_ROOT / "assets/downloads/slurm-example-pipeline.zip"
        source = REPO_ROOT / "examples"
        expected: dict[str, bytes] = {}
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if path.is_symlink():
                self.error(f"example pipeline source contains a symlink: {relative}")
                continue
            if not path.is_file():
                continue
            if (
                path.name == ".DS_Store"
                or path.suffix in {".pyc", ".pyo"}
                or any(
                    part in {"__pycache__", ".pytest_cache", ".mypy_cache"}
                    for part in relative.parts
                )
            ):
                continue
            if relative.parts[0] in {"logs", "results"} and path.name != ".gitkeep":
                continue
            member = (
                Path("slurm-example-pipeline") / relative
            ).as_posix()
            expected[member] = path.read_bytes()
        try:
            with ZipFile(archive) as handle:
                file_infos = [info for info in handle.infolist() if not info.is_dir()]
                actual_names = {info.filename for info in file_infos}
                if len(file_infos) != len(actual_names):
                    self.error("example pipeline ZIP contains duplicate members")
                expected_names = set(expected)
                if actual_names != expected_names:
                    missing = sorted(expected_names - actual_names)
                    extra = sorted(actual_names - expected_names)
                    self.error(
                        "example pipeline ZIP content list is stale; "
                        f"missing={missing}, extra={extra}"
                    )
                    return
                if [info.filename for info in file_infos] != sorted(expected_names):
                    self.error("example pipeline ZIP members are not in stable order")
                for member, source_bytes in expected.items():
                    if handle.read(member) != source_bytes:
                        self.error(f"example pipeline ZIP has stale content: {member}")
                    info = handle.getinfo(member)
                    source_path = source / Path(member).relative_to(
                        "slurm-example-pipeline"
                    )
                    expected_mode = (
                        0o755 if source_path.stat().st_mode & 0o111 else 0o644
                    )
                    archived_mode = (info.external_attr >> 16) & 0o777
                    archived_type = (info.external_attr >> 16) & 0o170000
                    if info.create_system != 3 or archived_type != stat.S_IFREG:
                        self.error(
                            f"example pipeline ZIP lacks POSIX file metadata: {member}"
                        )
                    if info.date_time != (1980, 1, 1, 0, 0, 0):
                        self.error(
                            f"example pipeline ZIP has a variable timestamp: {member}"
                        )
                    if info.compress_type != ZIP_STORED:
                        self.error(
                            "example pipeline ZIP must use stored entries for "
                            f"cross-platform reproducibility: {member}"
                        )
                    if archived_mode != expected_mode:
                        self.error(
                            "example pipeline ZIP has incorrect mode for "
                            f"{member}: expected {expected_mode:o}, "
                            f"found {archived_mode:o}"
                        )
        except (OSError, BadZipFile) as exc:
            self.error(f"cannot read example pipeline ZIP: {exc}")


    def check_checksums(self) -> None:
        checksum_file = REPO_ROOT / "SHA256SUMS.txt"
        try:
            lines = checksum_file.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            self.error(f"cannot read SHA256SUMS.txt: {exc}")
            return
        if not lines:
            self.error("SHA256SUMS.txt is empty")
            return
        seen: set[str] = set()
        for line_number, line in enumerate(lines, start=1):
            parts = line.split(maxsplit=1)
            if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{64}", parts[0]):
                self.error(f"malformed SHA256SUMS.txt line {line_number}: {line!r}")
                continue
            expected_hash, relative = parts
            relative = relative.lstrip("* ")
            relative_path = Path(relative)
            if relative_path.is_absolute() or ".." in relative_path.parts:
                self.error(f"unsafe checksum target on line {line_number}: {relative!r}")
                continue
            if relative in seen:
                self.error(f"duplicate checksum target: {relative}")
                continue
            seen.add(relative)
            target = REPO_ROOT / relative
            if not target.is_file():
                self.error(f"checksum target does not exist: {relative}")
                continue
            actual_hash = hashlib.sha256(target.read_bytes()).hexdigest()
            if actual_hash != expected_hash:
                self.error(f"checksum mismatch for {relative}")
        download_dir = DOCS_ROOT / "assets/downloads"
        expected_targets = {
            path.relative_to(REPO_ROOT).as_posix()
            for path in download_dir.iterdir()
            if path.is_file() and not path.name.startswith(".")
        }
        missing = expected_targets - seen
        if missing:
            self.error(f"SHA256SUMS.txt omits download files: {sorted(missing)}")
        extra = seen - expected_targets
        if extra:
            self.error(f"SHA256SUMS.txt includes non-download files: {sorted(extra)}")

    def check_ci_site_build(self) -> None:
        path = REPO_ROOT / ".github/workflows/validate.yml"
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            self.error(f"cannot read validation workflow: {exc}")
            return
        if "bundle exec jekyll build" not in text:
            self.error("validation workflow should perform a full Jekyll site build")
        if "working-directory: docs" not in text:
            self.error("Jekyll validation should run from the docs directory")

    def run(self) -> int:
        self.check_required_files()
        self.check_forbidden_public_files()
        self.check_front_matter_and_navigation()
        self.check_jekyll_link_tags()
        self.check_local_asset_links()
        self.check_mermaid()
        self.check_mermaid_config()
        self.check_pinned_versions()
        self.check_manifest()
        self.check_batch_portability()
        self.check_example_archive()
        self.check_checksums()
        self.check_ci_site_build()

        for warning in self.warnings:
            print(f"WARNING: {warning}")
        if self.errors:
            for error in self.errors:
                print(f"ERROR: {error}", file=sys.stderr)
            print(
                f"FAILED: {len(self.errors)} error(s), {len(self.warnings)} warning(s)",
                file=sys.stderr,
            )
            return 1
        print(
            "PASS: repository structure validated "
            f"({self.pages_checked} pages, {self.links_checked} internal links/assets, "
            f"{self.mermaid_checked} Mermaid diagrams)."
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(Validator().run())
