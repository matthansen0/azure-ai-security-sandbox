#!/usr/bin/env python3

import pathlib
import tempfile
import unittest
import urllib.error
from unittest import mock

from lab_rot_watch import check_external_links, run


class ExternalLinkTests(unittest.TestCase):
    def test_reports_only_confirmed_missing_links(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            markdown_path = pathlib.Path(temp_dir) / "links.md"
            markdown_path.write_text(
                "\n".join(
                    [
                        "https://${AGENT_FQDN}/chat",
                        "https://<agent-fqdn>/health",
                        "https://.../openai/v1",
                        "https://cognitiveservices.azure.com/.default",
                        "https://example.test/missing",
                        "https://example.test/server-error",
                        "https://example.test/transient",
                    ]
                ),
                encoding="utf-8",
            )

            calls: list[tuple[str, str]] = []

            def fake_urlopen(request, timeout):  # noqa: ANN001, ARG001
                calls.append((request.method, request.full_url))
                if request.full_url.endswith("/missing"):
                    raise urllib.error.HTTPError(request.full_url, 404, "Not Found", None, None)
                if request.full_url.endswith("/server-error"):
                    raise urllib.error.HTTPError(request.full_url, 500, "Server Error", None, None)
                if request.full_url.endswith("/transient"):
                    raise urllib.error.URLError("temporary DNS failure")
                raise AssertionError(f"Unexpected URL checked: {request.full_url}")

            with mock.patch("lab_rot_watch.urllib.request.urlopen", side_effect=fake_urlopen):
                findings = check_external_links([markdown_path])

        self.assertEqual(
            [(finding.severity, finding.title, finding.detail) for finding in findings],
            [("medium", "External link returned error", "https://example.test/missing (HTTP 404)")],
        )
        self.assertEqual(
            calls,
            [
                ("HEAD", "https://example.test/missing"),
                ("GET", "https://example.test/missing"),
                ("HEAD", "https://example.test/server-error"),
                ("HEAD", "https://example.test/transient"),
            ],
        )


class ScannerScopeTests(unittest.TestCase):
    def test_maintenance_posture_does_not_create_lab_rot_findings(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_root = pathlib.Path(temp_dir)
            files = {
                "README.md": "# Test repo\n",
                "HOW_IT_WORKS.md": "# How it works\n",
                "docs/labs/README.md": "[Lab 1](lab-1-test.md)\n",
                "docs/labs/lab-1-test.md": "# Lab 1\n",
                "scripts/validate.sh": 'header "Lab 1: Test"\n',
                "infra/main.bicep": "resource old 'Example/type@2020-01-01-preview' = {}\n",
                "agents/test/requirements.txt": "azure-identity>=1.15.0\nopenai>=1.10.0\n",
                "agents/test/Dockerfile": "FROM python:3.11-slim\n",
                "app/backend/Dockerfile": (
                    "FROM python:3.12-slim\n"
                    "ARG UPSTREAM_REPO=https://github.com/example/upstream.git\n"
                    "ARG UPSTREAM_REF=main\n"
                ),
            }
            for relative_path, content in files.items():
                file_path = repo_root / relative_path
                file_path.parent.mkdir(parents=True, exist_ok=True)
                file_path.write_text(content, encoding="utf-8")

            payload = run(
                repo_root,
                repo_root / "out" / "findings.json",
                repo_root / "out" / "report.md",
                skip_external_links=True,
            )

        self.assertFalse(payload["has_findings"])
        self.assertEqual(payload["findings"], [])


if __name__ == "__main__":
    unittest.main()