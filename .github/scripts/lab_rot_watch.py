#!/usr/bin/env python3
"""Static lab-rot scanner for azure-ai-security-sandbox.

This script is intentionally read-only and CI-friendly:
- no Azure auth
- no deployment
- deterministic checks that map to learner-facing drift
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Iterable


LAB_FILE_PATTERN = re.compile(r"^lab-(\d+)-.+\.md$")
VALIDATE_LAB_HEADER_PATTERN = re.compile(r'header\s+"Lab\s+(\d+):')
BICEP_RESOURCE_PATTERN = re.compile(r"'([^'@]+)@(\d{4}-\d{2}-\d{2})(-preview)?'")
REQ_LINE_PATTERN = re.compile(r"^([A-Za-z0-9_.-]+)(\[[^\]]+\])?\s*([<>=!~]{1,2})\s*([A-Za-z0-9_.+-]+)")
URL_PATTERN = re.compile(r"https?://[^\s)\]>\"']+")
MD_LINK_PATTERN = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
DOCKER_FROM_PATTERN = re.compile(r"^\s*FROM\s+([^\s]+)", re.IGNORECASE | re.MULTILINE)
ARG_ASSIGN_PATTERN = re.compile(r"^\s*ARG\s+([A-Za-z_][A-Za-z0-9_]*)=(.+?)\s*$", re.MULTILINE)

IGNORED_PATH_PARTS = {
    ".git",
    ".venv",
    ".venv-tests",
    "venv",
    "node_modules",
    "__pycache__",
}


def path_is_ignored(path: pathlib.Path) -> bool:
    return any(part in IGNORED_PATH_PARTS for part in path.parts)


def rglob_in_dirs(base_dirs: list[pathlib.Path], pattern: str) -> list[pathlib.Path]:
    paths: list[pathlib.Path] = []
    for base in base_dirs:
        if not base.exists() or not base.is_dir():
            continue
        for p in base.rglob(pattern):
            if path_is_ignored(p):
                continue
            paths.append(p)
    return paths


@dataclass
class Finding:
    severity: str
    title: str
    detail: str

    def to_markdown(self) -> str:
        return f"- **[{self.severity}] {self.title}**\n  - {self.detail}"


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def find_lab_files(labs_dir: pathlib.Path) -> list[pathlib.Path]:
    return sorted([p for p in labs_dir.glob("lab-*.md") if p.is_file()])


def parse_lab_numbers_from_files(lab_files: Iterable[pathlib.Path]) -> list[int]:
    numbers: list[int] = []
    for file_path in lab_files:
        match = LAB_FILE_PATTERN.match(file_path.name)
        if match:
            numbers.append(int(match.group(1)))
    return sorted(numbers)


def parse_lab_numbers_from_validate(validate_path: pathlib.Path) -> list[int]:
    numbers = [int(m.group(1)) for m in VALIDATE_LAB_HEADER_PATTERN.finditer(read_text(validate_path))]
    return sorted(set(numbers))


def extract_links(markdown_text: str) -> list[str]:
    return [m.group(1).strip() for m in MD_LINK_PATTERN.finditer(markdown_text)]


def extract_urls(text: str) -> list[str]:
    return sorted(set(URL_PATTERN.findall(text)))


def is_external_url(link: str) -> bool:
    return link.startswith("http://") or link.startswith("https://")


def check_internal_markdown_links(repo_root: pathlib.Path, markdown_files: list[pathlib.Path]) -> list[Finding]:
    findings: list[Finding] = []
    for md_file in markdown_files:
        text = read_text(md_file)
        for raw_link in extract_links(text):
            if (
                not raw_link
                or raw_link.startswith("#")
                or is_external_url(raw_link)
                or raw_link.startswith("mailto:")
            ):
                continue

            link_path = raw_link.split("#", 1)[0].strip()
            if not link_path:
                continue

            resolved = (md_file.parent / link_path).resolve()
            try:
                resolved.relative_to(repo_root.resolve())
            except ValueError:
                findings.append(
                    Finding(
                        "high",
                        "Suspicious path traversal in markdown link",
                        f"{md_file.relative_to(repo_root)} -> {raw_link}",
                    )
                )
                continue

            if not resolved.exists():
                findings.append(
                    Finding(
                        "high",
                        "Broken internal markdown link",
                        f"{md_file.relative_to(repo_root)} -> {raw_link}",
                    )
                )
    return findings


def check_external_links(
    markdown_files: list[pathlib.Path],
    repo_root: pathlib.Path,
    timeout_seconds: int = 8,
    max_urls: int = 40,
) -> list[Finding]:
    findings: list[Finding] = []
    urls: set[str] = set()
    for md_file in markdown_files:
        urls.update(extract_urls(read_text(md_file)))

    skip_domains = {
        "localhost",
        "127.0.0.1",
    }

    url_list = sorted(urls)
    for url in url_list[:max_urls]:
        parsed = urllib.parse.urlparse(url)
        if parsed.hostname in skip_domains:
            continue

        # HEAD first, then GET fallback for hosts that do not support HEAD.
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "lab-rot-watch/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as resp:
                status = resp.status
        except urllib.error.HTTPError as err:
            status = err.code
            if status in (405, 403, 429):
                try:
                    req_get = urllib.request.Request(url, method="GET", headers={"User-Agent": "lab-rot-watch/1.0"})
                    with urllib.request.urlopen(req_get, timeout=timeout_seconds) as resp:
                        status = resp.status
                except Exception as get_err:  # noqa: BLE001
                    findings.append(Finding("medium", "External link check failed", f"{url} ({get_err})"))
                    continue
            elif status >= 400:
                findings.append(Finding("medium", "External link returned error", f"{url} (HTTP {status})"))
                continue
        except Exception as err:  # noqa: BLE001
            findings.append(Finding("medium", "External link check failed", f"{url} ({err})"))
            continue

        if status >= 400:
            findings.append(Finding("medium", "External link returned error", f"{url} (HTTP {status})"))

    if len(url_list) > max_urls:
        findings.append(
            Finding(
                "low",
                "External link scan sampled",
                f"Checked {max_urls} of {len(url_list)} URLs to keep runtime bounded.",
            )
        )

    return findings


def check_preview_api_age(bicep_files: list[pathlib.Path], repo_root: pathlib.Path, months_threshold: int = 18) -> list[Finding]:
    findings: list[Finding] = []
    now = dt.date.today()
    seen: set[tuple[str, str, str]] = set()

    for bicep_file in bicep_files:
        text = read_text(bicep_file)
        for match in BICEP_RESOURCE_PATTERN.finditer(text):
            resource_type = match.group(1)
            version_date = match.group(2)
            is_preview = bool(match.group(3))
            if not is_preview:
                continue

            try:
                version_dt = dt.date.fromisoformat(version_date)
            except ValueError:
                continue

            age_months = (now.year - version_dt.year) * 12 + (now.month - version_dt.month)
            if age_months >= months_threshold:
                key = (str(bicep_file.relative_to(repo_root)), resource_type, version_date)
                if key in seen:
                    continue
                seen.add(key)
                findings.append(
                    Finding(
                        "medium",
                        "Old preview API version",
                        f"{bicep_file.relative_to(repo_root)} uses {resource_type}@{version_date}-preview (~{age_months} months old)",
                    )
                )

    return findings


def check_sdk_drift(requirement_files: list[pathlib.Path], repo_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []
    packages: dict[str, tuple[str, str, pathlib.Path]] = {}

    for req_file in requirement_files:
        if "upstream" in req_file.parts:
            continue
        for line in read_text(req_file).splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            m = REQ_LINE_PATTERN.match(stripped)
            if not m:
                continue

            pkg = m.group(1).lower()
            op = m.group(3)
            ver = m.group(4)
            packages[pkg] = (op, ver, req_file)

    target_prefixes = ("azure-",)
    target_exact = {"openai"}

    for pkg, (op, local_ver, req_file) in sorted(packages.items()):
        if not (pkg.startswith(target_prefixes) or pkg in target_exact):
            continue

        # Static lab-rot heuristics that avoid external calls:
        # - unbounded minimums (>=) on SDKs can drift behavior over time
        # - wildcard pins are too loose for reproducible labs
        # - very old minimum major versions should be reviewed
        if op == ">=" or "*" in local_ver:
            findings.append(
                Finding(
                    "low",
                    "Potential SDK drift risk",
                    (
                        f"{pkg} in {req_file.relative_to(repo_root)} uses {op}{local_ver}. "
                        "For lab stability, consider pinning or scheduling regular review bumps."
                    ),
                )
            )

        version_match = re.match(r"^(\d+)", local_ver)
        if version_match:
            major = int(version_match.group(1))
            if major == 0:
                findings.append(
                    Finding(
                        "low",
                        "Pre-1.0 SDK in lab-critical dependency",
                        f"{pkg} in {req_file.relative_to(repo_root)} is {op}{local_ver}; review for stability risk.",
                    )
                )

    return findings


def _normalize_repo_url(url: str) -> str:
    cleaned = url.strip().lower()
    cleaned = cleaned.removeprefix("https://")
    cleaned = cleaned.removeprefix("http://")
    cleaned = cleaned.removeprefix("git@")
    cleaned = cleaned.replace(":", "/")
    if cleaned.endswith(".git"):
        cleaned = cleaned[:-4]
    return cleaned


def check_external_deployment_dependencies(repo_root: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []

    azure_yaml = repo_root / "azure.yaml"
    dockerfile = repo_root / "app" / "backend" / "Dockerfile"
    gitmodules = repo_root / ".gitmodules"

    azure_text = read_text(azure_yaml) if azure_yaml.exists() else ""
    docker_text = read_text(dockerfile) if dockerfile.exists() else ""
    gitmodules_text = read_text(gitmodules) if gitmodules.exists() else ""

    args = {m.group(1): m.group(2).strip() for m in ARG_ASSIGN_PATTERN.finditer(docker_text)}
    upstream_repo = args.get("UPSTREAM_REPO", "")
    upstream_ref = args.get("UPSTREAM_REF", "")

    # 1) Build-time upstream source pinning.
    if upstream_repo and upstream_ref:
        is_commit_sha = bool(re.fullmatch(r"[0-9a-fA-F]{7,40}", upstream_ref))
        if upstream_ref.lower() in {"main", "master", "latest", "head"}:
            findings.append(
                Finding(
                    "high",
                    "Build-time upstream ref is mutable",
                    f"app/backend/Dockerfile uses UPSTREAM_REF={upstream_ref}. Pin to a commit SHA for reproducible deploys.",
                )
            )
        elif not is_commit_sha:
            findings.append(
                Finding(
                    "medium",
                    "Build-time upstream ref is not commit-pinned",
                    f"app/backend/Dockerfile uses UPSTREAM_REF={upstream_ref}. Consider pinning to a commit SHA.",
                )
            )

    # 2) Submodule and build-time clone consistency.
    submodule_url_match = re.search(r"\[submodule\s+\"upstream\"\][\s\S]*?url\s*=\s*(.+)", gitmodules_text)
    submodule_url = submodule_url_match.group(1).strip() if submodule_url_match else ""

    if submodule_url and upstream_repo:
        if _normalize_repo_url(submodule_url) != _normalize_repo_url(upstream_repo):
            findings.append(
                Finding(
                    "high",
                    "Submodule source and Docker build source differ",
                    f".gitmodules upstream URL ({submodule_url}) differs from app/backend/Dockerfile UPSTREAM_REPO ({upstream_repo}).",
                )
            )

    uses_submodule_in_hooks = "git submodule update --init --recursive" in azure_text
    uses_build_time_clone = "git clone" in docker_text and "UPSTREAM_REPO" in docker_text
    if uses_submodule_in_hooks and uses_build_time_clone:
        findings.append(
            Finding(
                "medium",
                "Dual upstream dependency paths detected",
                "azure.yaml postprovision uses upstream submodule while app/backend/Dockerfile clones upstream during image build; these can drift.",
            )
        )

    # 3) Mutable base image tags in Dockerfiles.
    dockerfiles = [
        p
        for p in rglob_in_dirs([repo_root / "app", repo_root / "agents"], "Dockerfile")
        if "upstream" not in p.parts
    ]
    seen_images: set[tuple[str, str]] = set()
    for df in dockerfiles:
        text = read_text(df)
        for image in DOCKER_FROM_PATTERN.findall(text):
            if image.startswith("${"):
                continue
            if "@sha256:" in image:
                continue
            key = (str(df.relative_to(repo_root)), image)
            if key in seen_images:
                continue
            seen_images.add(key)
            findings.append(
                Finding(
                    "low",
                    "Container base image is tag-based",
                    f"{df.relative_to(repo_root)} uses FROM {image} without digest pinning.",
                )
            )

    return findings


def check_lab_validator_parity(repo_root: pathlib.Path, labs_dir: pathlib.Path, validate_path: pathlib.Path) -> list[Finding]:
    findings: list[Finding] = []

    lab_files = find_lab_files(labs_dir)
    file_numbers = parse_lab_numbers_from_files(lab_files)
    validate_numbers = parse_lab_numbers_from_validate(validate_path)

    if not file_numbers:
        findings.append(Finding("high", "No lab guides found", f"Expected lab files under {labs_dir.relative_to(repo_root)}"))
        return findings

    if file_numbers != list(range(1, len(file_numbers) + 1)):
        findings.append(Finding("high", "Lab numbering is not contiguous", f"Found lab numbers: {file_numbers}"))

    missing_in_validate = sorted(set(file_numbers) - set(validate_numbers))
    extra_in_validate = sorted(set(validate_numbers) - set(file_numbers))

    if missing_in_validate:
        findings.append(
            Finding(
                "high",
                "Labs missing from validate.sh",
                f"Missing Lab numbers in scripts/validate.sh: {missing_in_validate}",
            )
        )

    if extra_in_validate:
        findings.append(
            Finding(
                "medium",
                "validate.sh has extra Lab headers",
                f"Lab numbers not represented by docs/labs/lab-*.md: {extra_in_validate}",
            )
        )

    readme_path = labs_dir / "README.md"
    if readme_path.exists():
        readme_links = {
            int(m.group(1))
            for m in re.finditer(r"\(lab-(\d+)-[^)]+\.md\)", read_text(readme_path))
        }
        missing_in_readme = sorted(set(file_numbers) - readme_links)
        if missing_in_readme:
            findings.append(
                Finding(
                    "medium",
                    "Lab README table missing entries",
                    f"docs/labs/README.md is missing links for labs: {missing_in_readme}",
                )
            )
    else:
        findings.append(Finding("medium", "Lab README missing", "docs/labs/README.md not found"))

    return findings


def render_report(repo_root: pathlib.Path, findings: list[Finding], scan_time: str) -> str:
    week = dt.date.today().strftime("%G-W%V")
    lines = [
        f"# Lab Rot Watch Findings ({week})",
        "",
        "This issue was opened automatically by the lab-rot watcher workflow.",
        "",
        f"Scan time (UTC): {scan_time}",
        "",
        "## Summary",
        f"- Total findings: {len(findings)}",
        f"- High: {sum(1 for f in findings if f.severity == 'high')}",
        f"- Medium: {sum(1 for f in findings if f.severity == 'medium')}",
        f"- Low: {sum(1 for f in findings if f.severity == 'low')}",
        "",
        "## Findings",
    ]

    if findings:
        lines.extend(f.to_markdown() for f in findings)
    else:
        lines.append("- No drift findings detected.")

    lines.extend(
        [
            "",
            "## Triage Checklist",
            "- [ ] Confirm each finding is still reproducible",
            "- [ ] Decide fix now vs backlog",
            "- [ ] Update labs and/or scripts/validate.sh together when parity is affected",
            "- [ ] Close this issue after action (or explicit decline rationale)",
            "",
            "_Auto-opened by .github/workflows/lab-rot-watch.yml._",
        ]
    )

    return "\n".join(lines) + "\n"


def run(
    repo_root: pathlib.Path,
    output_json: pathlib.Path,
    output_md: pathlib.Path,
    skip_external_links: bool = False,
    max_external_urls: int = 40,
) -> dict:
    labs_dir = repo_root / "docs" / "labs"
    validate_path = repo_root / "scripts" / "validate.sh"
    markdown_files = [
        repo_root / "README.md",
        repo_root / "HOW_IT_WORKS.md",
        repo_root / "docs" / "labs" / "README.md",
    ]
    markdown_files += find_lab_files(labs_dir)
    markdown_files = [p for p in markdown_files if p.exists()]

    bicep_files = [
        p
        for p in (repo_root / "infra").rglob("*.bicep")
        if "upstream" not in p.parts and not path_is_ignored(p)
    ]
    requirement_files = [
        p
        for p in rglob_in_dirs([repo_root / "app", repo_root / "agents"], "requirements*.txt")
        if "upstream" not in p.parts
    ]

    findings: list[Finding] = []
    findings.extend(check_lab_validator_parity(repo_root, labs_dir, validate_path))
    findings.extend(check_internal_markdown_links(repo_root, markdown_files))
    if not skip_external_links:
        findings.extend(check_external_links(markdown_files, repo_root, max_urls=max_external_urls))
    findings.extend(check_preview_api_age(bicep_files, repo_root))
    findings.extend(check_sdk_drift(requirement_files, repo_root))
    findings.extend(check_external_deployment_dependencies(repo_root))

    # Stable sort for deterministic issue bodies.
    findings.sort(key=lambda f: (f.severity, f.title, f.detail))

    scan_time = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    issue_title = f"Lab rot watch findings - {dt.date.today().strftime('%G-W%V')}"
    report = render_report(repo_root, findings, scan_time)

    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_md.write_text(report, encoding="utf-8")

    payload = {
        "has_findings": bool(findings),
        "finding_count": len(findings),
        "issue_title": issue_title,
        "report_path": str(output_md),
        "findings": [f.__dict__ for f in findings],
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Run static lab-rot checks")
    parser.add_argument("--repo-root", default=".", help="Repository root path")
    parser.add_argument("--output-json", required=True, help="Output JSON path")
    parser.add_argument("--output-md", required=True, help="Output markdown report path")
    parser.add_argument("--skip-external-links", action="store_true", help="Skip HTTP checks for external links")
    parser.add_argument("--max-external-urls", type=int, default=40, help="Maximum external URLs to check")
    args = parser.parse_args()

    repo_root = pathlib.Path(args.repo_root).resolve()
    payload = run(
        repo_root,
        pathlib.Path(args.output_json),
        pathlib.Path(args.output_md),
        skip_external_links=args.skip_external_links,
        max_external_urls=args.max_external_urls,
    )

    print(json.dumps({"has_findings": payload["has_findings"], "finding_count": payload["finding_count"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
