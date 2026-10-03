"""Deterministic review gates and readable comments; no cluster access."""

import argparse
import json
import re
import subprocess
import sys


PIN = re.compile(
    r"^(\s*(?:-\s+)?uses:\s*)([\w.-]+/[\w./-]+)@([0-9a-f]{40})"
    r"\s+#\s*v\d+(?:\.\d+)*(?:[.-][\w.-]+)?\s*$"
)


def action_pin_patch(file):
    """Fail closed on missing/truncated patches, renames, or other line changes."""
    if file.get("status") != "modified":
        return False
    removed, added = [], []
    for line in file.get("patch", "").splitlines():
        if line.startswith("-"):
            removed.append(line[1:])
        elif line.startswith("+"):
            added.append(line[1:])
    if not removed or len(removed) != len(added):
        return False
    if len(removed) != file.get("deletions") or len(added) != file.get("additions"):
        return False
    for old, new in zip(removed, added):
        before, after = PIN.fullmatch(old), PIN.fullmatch(new)
        if not before or not after or before.group(1, 2) != after.group(1, 2):
            return False
    return True


def normalized_workflow(source):
    # Only real step action references qualify, never text in run/prompt strings.
    workflow = json.loads(
        subprocess.check_output(
            ["yq", "-o=json", "."],
            input=source,
            text=True,
        )
    )
    for job in workflow.get("jobs", {}).values():
        for step in job.get("steps", []):
            reference = step.get("uses", "")
            match = re.fullmatch(r"([\w.-]+/[\w./-]+)@[0-9a-f]{40}", reference)
            if match:
                step["uses"] = f"{match[1]}@PIN"
    return workflow


def action_pin_only(file):
    if not action_pin_patch(file):
        return False
    before, after = file.get("old_content"), file.get("new_content")
    if not isinstance(before, str) or not isinstance(after, str):
        return False
    return normalized_workflow(before) == normalized_workflow(after)


def workflow_sources(files, repo, base, head):
    for file in files:
        path = file["filename"]
        if path.startswith(".github/workflows/") and action_pin_patch(file):
            for key, sha in (("old_content", base), ("new_content", head)):
                file[key] = subprocess.check_output(
                    [
                        "gh",
                        "api",
                        "-H",
                        "Accept: application/vnd.github.raw+json",
                        f"repos/{repo}/contents/{path}?ref={sha}",
                    ],
                    text=True,
                )
    return files


def protected_change(file):
    path = file["filename"]
    if path.startswith(".github/workflows/") and path.endswith((".yml", ".yaml")):
        return not action_pin_only(file)
    return path.startswith((".github/", "scripts/", "taskfiles/")) or path in {
        "Taskfile.dist.yml",
        "mise.toml",
        "hk.pkl",
    }


def assess(result, files):
    # Validate again here: an agent-supplied verdict is not merge authority.
    for field in (
        "updates",
        "risks",
        "uncertainties",
        "hard_blockers",
        "checks",
        "evidence",
    ):
        value = result[field]
        if not isinstance(value, list) or not all(
            isinstance(item, str) for item in value
        ):
            raise ValueError(f"{field} must be a list of strings")
        if field in {"updates", "checks", "evidence"} and not value:
            raise ValueError(f"{field} must not be empty")
    score = result["confidence"]
    if type(score) is not int or not 0 <= score <= 100:
        raise ValueError("confidence must be an integer from 0 to 100")
    if result["classification"] not in {"low-risk", "needs-attention", "blocked"}:
        raise ValueError("invalid classification")
    if result["verdict"] not in {"safe", "unsafe"}:
        raise ValueError("invalid verdict")
    if type(result["repairable"]) is not bool:
        raise ValueError("repairable must be a boolean")
    if not re.fullmatch(r"[0-9a-f]{40}", result["reviewed_sha"]):
        raise ValueError("invalid reviewed_sha")
    for field in ("summary", "rationale", "changes"):
        if not isinstance(result[field], str) or not result[field].strip():
            raise ValueError(f"{field} must be a nonempty string")
    for file in files:
        if protected_change(file):
            result["hard_blockers"].append(
                f"{file['filename']} changes workflow or validation behavior; human review is required."
            )
    if result["hard_blockers"]:
        result["classification"] = "blocked"
    if (
        result["classification"] != "low-risk"
        or score <= 80
        or result["hard_blockers"]
        or result["uncertainties"]
        or result["repairable"]
    ):
        result["verdict"] = "unsafe"
    if result["verdict"] == "unsafe" and result["classification"] == "low-risk":
        result["classification"] = "needs-attention"
    if score <= 80:
        result["uncertainties"].append(
            "Compatibility confidence does not exceed 80%; more evidence is needed before automatic merge."
        )
    return result


def comment(result):
    lines = [
        "## Automated Renovate safety review",
        "",
        f"**Verdict:** {result['verdict']} · **Classification:** {result['classification']}"
        f" · **Compatibility confidence:** {result['confidence']}%",
        "",
        result["summary"],
    ]
    for title, field in (
        ("What changes", "updates"),
        ("Impact and risks", "risks"),
        ("Needs attention", "uncertainties"),
        ("Merge blockers", "hard_blockers"),
    ):
        if result[field]:
            lines.extend(["", f"### {title}"])
            lines.extend(f"- {item}" for item in result[field])
    lines.extend(
        [
            "",
            "<details>",
            "<summary>Review rationale, checks, and sources</summary>",
            "",
            result["rationale"],
            "",
            "### Checks",
        ]
    )
    lines.extend(f"- {item}" for item in result["checks"])
    lines.extend(["", "### Sources"])
    lines.extend(f"- {item}" for item in result["evidence"])
    lines.extend(
        [
            "",
            "### Changes",
            result["changes"],
            "",
            f"Reviewed head: `{result['reviewed_sha']}`",
            "",
            "Confidence is a review judgment, not a measured probability of success.",
            "",
            "</details>",
            "",
        ]
    )
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("assess", "comment"))
    args = parser.parse_args()
    payload = json.load(sys.stdin)
    if args.mode == "assess":
        files = workflow_sources(
            payload["files"], payload["repo"], payload["base"], payload["head"]
        )
        print(json.dumps(assess(payload["result"], files)))
    else:
        print(comment(payload))


if __name__ == "__main__":
    main()
