import copy
import importlib.util
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "renovate_safety", ROOT / ".github/scripts/renovate_safety.py"
)
SAFETY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SAFETY)

RESULT = {
    "verdict": "safe",
    "repairable": False,
    "classification": "low-risk",
    "confidence": 90,
    "summary": "Routine update; no deployment blocker found.",
    "updates": ["Example 1.0.0 → 1.0.1"],
    "risks": [],
    "uncertainties": [],
    "hard_blockers": [],
    "checks": ["Targeted tests passed."],
    "rationale": "The API and deployment settings are unchanged.",
    "evidence": ["https://example.com/releases/1.0.1"],
    "changes": "None",
    "reviewed_sha": "a" * 40,
}


def change(old, new, **overrides):
    file = {
        "filename": ".github/workflows/renovate-safety.yml",
        "status": "modified",
        "deletions": 1,
        "additions": 1,
        "patch": f"@@ -1 +1 @@\n-{old}\n+{new}",
        "old_content": f"jobs:\n  test:\n    steps:\n      - name: Example\n{old}\n",
        "new_content": f"jobs:\n  test:\n    steps:\n      - name: Example\n{new}\n",
    }
    file.update(overrides)
    return file


OLD_PIN = f"        uses: pullfrog/pullfrog@{'a' * 40} # v0.1.82"
NEW_PIN = f"        uses: pullfrog/pullfrog@{'b' * 40} # v0.1.95"


class SafetyTest(unittest.TestCase):
    def assess(self, files=None, **updates):
        result = copy.deepcopy(RESULT)
        result.update(updates)
        return SAFETY.assess(result, files or [])

    def test_confidence_boundary(self):
        self.assertEqual(self.assess(confidence=80)["verdict"], "unsafe")
        self.assertEqual(self.assess(confidence=81)["verdict"], "safe")

    def test_high_confidence_cannot_override_risk(self):
        for updates in (
            {"classification": "needs-attention"},
            {"classification": "blocked"},
            {"hard_blockers": ["Drops user data."]},
            {"uncertainties": ["New minimum Kubernetes version is unknown."]},
            {"repairable": True},
            {"verdict": "unsafe"},
        ):
            with self.subTest(updates=updates):
                self.assertEqual(
                    self.assess(confidence=100, **updates)["verdict"], "unsafe"
                )

    def test_invalid_result_fails_closed(self):
        for updates in (
            {"confidence": True},
            {"confidence": 101},
            {"confidence": "90"},
            {"classification": "unknown"},
            {"verdict": "unknown"},
            {"hard_blockers": "None"},
            {"reviewed_sha": "invalid"},
            {"repairable": "false"},
            {"rationale": ""},
            {"updates": []},
            {"checks": []},
            {"evidence": []},
        ):
            with self.subTest(updates=updates), self.assertRaises(ValueError):
                self.assess(**updates)

    def test_existing_action_sha_pin_update_allowed(self):
        self.assertEqual(self.assess([change(OLD_PIN, NEW_PIN)])["verdict"], "safe")

    def test_script_text_is_not_an_action_reference(self):
        prefix = "jobs:\n  test:\n    steps:\n      - run: |\n"
        old, new = "  " + OLD_PIN, "  " + NEW_PIN
        file = change(
            old,
            new,
            old_content=prefix + old + "\n",
            new_content=prefix + new + "\n",
        )
        self.assertFalse(SAFETY.action_pin_only(file))

    def test_full_source_required_and_other_source_changes_blocked(self):
        file = change(OLD_PIN, NEW_PIN)
        del file["old_content"]
        self.assertFalse(SAFETY.action_pin_only(file))
        file = change(OLD_PIN, NEW_PIN)
        file["new_content"] += "permissions: write-all\n"
        self.assertFalse(SAFETY.action_pin_only(file))

    def test_other_workflow_changes_blocked(self):
        for new in (
            NEW_PIN.replace("pullfrog/pullfrog", "other/action"),
            NEW_PIN.replace("        uses:", "      - uses:"),
            "        uses: pullfrog/pullfrog@v0.1.95",
            NEW_PIN + " malicious text",
            "        run: echo changed",
        ):
            with self.subTest(new=new):
                self.assertEqual(
                    self.assess([change(OLD_PIN, new)])["verdict"], "unsafe"
                )

    def test_missing_truncated_and_renamed_patches_blocked(self):
        for overrides in ({"patch": ""}, {"additions": 2}, {"status": "renamed"}):
            with self.subTest(overrides=overrides):
                self.assertFalse(
                    SAFETY.action_pin_only(change(OLD_PIN, NEW_PIN, **overrides))
                )

    def test_mixed_workflow_changes_blocked(self):
        file = change(
            OLD_PIN,
            NEW_PIN,
            additions=2,
            deletions=2,
            patch=f"@@ -1,2 +1,2 @@\n-{OLD_PIN}\n+{NEW_PIN}\n-    push: disabled\n+    push: restricted",
        )
        self.assertEqual(self.assess([file])["verdict"], "unsafe")

    def test_scripts_and_validation_config_blocked(self):
        for path in (
            ".github/scripts/check.sh",
            ".github/renovate-safety-review.md",
            "Taskfile.dist.yml",
            "taskfiles/hooks.yml",
            "mise.toml",
            "hk.pkl",
        ):
            with self.subTest(path=path):
                result = self.assess([change(OLD_PIN, NEW_PIN, filename=path)])
                self.assertEqual(result["classification"], "blocked")
                self.assertEqual(result["verdict"], "unsafe")

    def test_comment_is_organized_and_collapsed(self):
        text = SAFETY.comment(self.assess())
        for expected in (
            "### What changes",
            "- Example 1.0.0 → 1.0.1",
            "90%",
            "<details>",
            "<summary>Review rationale, checks, and sources</summary>",
            "### Checks",
            "### Sources",
            "</details>",
            RESULT["reviewed_sha"],
        ):
            self.assertIn(expected, text)


class FinishTest(unittest.TestCase):
    def test_optional_step_outputs_have_json_fallbacks(self):
        workflow = (ROOT / ".github/workflows/renovate-safety.yml").read_text()
        calls = re.findall(r"fromJSON\((steps\.[^)]+)\)", workflow)
        self.assertTrue(calls)
        for call in calls:
            with self.subTest(expression=call):
                self.assertRegex(call, r"outputs\.result\s*\|\|\s*'\{\}'$")

    def test_workflow_schema_contract(self):
        steps = json.loads(
            subprocess.check_output(
                [
                    "yq",
                    "-o=json",
                    ".jobs.review.steps",
                    str(ROOT / ".github/workflows/renovate-safety.yml"),
                ],
                text=True,
            )
        )
        schemas = [
            json.loads(step["with"]["output_schema"])
            for step in steps
            if step.get("id") in {"review", "verify"}
        ]
        self.assertEqual(len(schemas), 2)
        self.assertEqual(schemas[0], schemas[1])
        self.assertEqual(set(schemas[0]["required"]), set(RESULT))
        self.assertEqual(set(schemas[0]["properties"]), set(RESULT))
        fields = list(schemas[0]["properties"])
        for before, after in (
            ("rationale", "classification"),
            ("classification", "confidence"),
            ("confidence", "verdict"),
        ):
            self.assertLess(fields.index(before), fields.index(after))

    def run_finish(self, result, files, changed_head=False):
        # Execute the real shell gate with mocked GitHub calls; no remote writes.
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            fixture = {
                "pr": {
                    "state": "open",
                    "user": {"login": "renovate[bot]"},
                    "head": {
                        "sha": "c" * 40 if changed_head else RESULT["reviewed_sha"],
                        "repo": {"full_name": "example/repo"},
                    },
                    "base": {
                        "sha": "b" * 40,
                        "ref": "main",
                        "repo": {"full_name": "example/repo"},
                    },
                    "labels": [],
                    "draft": False,
                },
                "files": files,
            }
            (path / "fixture.json").write_text(json.dumps(fixture))
            gh = path / "gh"
            gh.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["MOCK_ROOT"])
fixture = json.loads((root / "fixture.json").read_text())
args = sys.argv[1:]
with (root / "calls").open("a") as log:
    log.write(json.dumps(args) + "\\n")
if args[0] == "api":
    endpoint = next(a for a in args if a.startswith("repos/"))
    if endpoint.endswith("/files?per_page=100"):
        for file in fixture["files"]:
            print(json.dumps(file))
    elif endpoint.endswith("/pulls/1"):
        print(json.dumps(fixture["pr"]))
    elif endpoint.endswith("/branches/main"):
        print("b" * 40)
    elif "/contents/" in endpoint:
        file = next(file for file in fixture["files"] if file["filename"] in endpoint)
        key = "old_content" if endpoint.endswith("b" * 40) else "new_content"
        print(file[key], end="")
    elif "/actions/workflows/" in endpoint:
        print(json.dumps({"workflow_runs": [{"id": 7, "head_sha": "a" * 40,
            "pull_requests": [{"number": 1, "base": {"sha": "b" * 40}}],
            "created_at": "2026-10-03T00:00:00Z", "status": "completed",
            "conclusion": "success"}]}))
    elif "/actions/runs/7/jobs" in endpoint:
        for name in ["Validate", "CRD Schema Annotations", "Values Schema Annotations", "Validator Tests"]:
            print(json.dumps({"name": name, "conclusion": "success"}))
    else:
        sys.exit("Unexpected API call: " + endpoint)
elif args[:2] == ["label", "list"]:
    print("true")
elif args[:2] == ["pr", "edit"] or args[:2] == ["pr", "merge"]:
    pass
elif args[:2] == ["pr", "comment"]:
    (root / "comment").write_text(pathlib.Path(args[args.index("--body-file") + 1]).read_text())
else:
    sys.exit("Unexpected gh command: " + str(args))
""")
            gh.chmod(0o755)
            env = dict(
                os.environ,
                PATH=f"{directory}:{os.environ['PATH']}",
                MOCK_ROOT=directory,
                REPO="example/repo",
                PR_NUMBER="1",
                RESULT=json.dumps(result),
            )
            run = subprocess.run(
                ["bash", ".github/scripts/renovate-safety-finish.sh"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            calls = [
                json.loads(line) for line in (path / "calls").read_text().splitlines()
            ]
            comment_path = path / "comment"
            return calls, comment_path.read_text() if comment_path.exists() else ""

    def test_finish_allows_verified_pin_update_after_ci(self):
        calls, text = self.run_finish(copy.deepcopy(RESULT), [change(OLD_PIN, NEW_PIN)])
        self.assertTrue(any(call[:2] == ["pr", "merge"] for call in calls))
        self.assertIn("**Verdict:** safe", text)

    def test_finish_labels_low_confidence_and_behavior_changes(self):
        for score, file in (
            (80, change(OLD_PIN, NEW_PIN)),
            (100, change("    push: disabled", "    push: restricted")),
        ):
            with self.subTest(score=score):
                result = copy.deepcopy(RESULT)
                result["confidence"] = score
                calls, text = self.run_finish(result, [file])
                self.assertFalse(any(call[:2] == ["pr", "merge"] for call in calls))
                self.assertTrue(any("--add-label" in call for call in calls))
                self.assertIn("**Verdict:** unsafe", text)

    def test_changed_head_does_not_comment_label_or_merge(self):
        calls, text = self.run_finish(copy.deepcopy(RESULT), [], changed_head=True)
        self.assertEqual(text, "")
        self.assertFalse(any(call[0] == "pr" for call in calls))


if __name__ == "__main__":
    unittest.main()
