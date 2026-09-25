#!/usr/bin/env bash
set -euo pipefail

# The agent's output is evidence, not authority to bypass these checks.
verdict=$(jq -er '.verdict' <<<"$RESULT")
findings=$(jq -er '.findings' <<<"$RESULT")
changes=$(jq -er '.changes' <<<"$RESULT")
reviewed_sha=$(jq -er '.reviewed_sha' <<<"$RESULT")

pr=$(gh api "repos/$REPO/pulls/$PR_NUMBER")
head=$(jq -r '.head.sha' <<<"$pr")
base=$(jq -r '.base.sha' <<<"$pr")
if [ "$(jq -r '.state' <<<"$pr")" != open ] ||
	[ "$(jq -r '.user.login' <<<"$pr")" != 'renovate[bot]' ] ||
	[ "$(jq -r '.base.ref' <<<"$pr")" != main ] ||
	[ "$(jq -r '.head.repo.full_name == .base.repo.full_name' <<<"$pr")" != true ] ||
	[ "$(jq -r '[.labels[].name] | index("renovate-unsafe") != null' <<<"$pr")" = true ]; then
	echo 'PR is no longer eligible; refusing to act' >&2
	exit 1
fi
if [ "$head" != "$reviewed_sha" ]; then
	echo 'PR head does not match the head reviewed by the agent' >&2
	exit 1
fi

# The CI gate must not execute checks redefined by the dependency update.
files=$(gh api --paginate "repos/$REPO/pulls/$PR_NUMBER/files?per_page=100" \
	--jq '.[].filename')
if grep -Eq '^(\.github/|scripts/|taskfiles/|Taskfile\.dist\.yml$|mise\.toml$)' <<<"$files"; then
	echo 'PR changes validation or workflow code; human review required' >&2
	verdict=unsafe
	findings="$findings

This PR changes workflow or validation code. The automated CI gate cannot be trusted; a human must review it."
fi
if [ "$head" != "$INITIAL_SHA" ]; then
	# A repair is acceptable only when it is based on the discovered head.
	gh api "repos/$REPO/compare/$INITIAL_SHA...$head" \
		--jq '.status' | grep -qx ahead || {
		echo 'PR head is not a descendant of the initially discovered commit' >&2
		exit 1
	}
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT
{
	printf '## Automated Renovate safety review\n\n**Verdict:** %s\n\n### Findings\n%s\n\n### Changes and validation\n%s\n' \
		"$verdict" "$findings" "$changes"
} >"$body"
gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file "$body"

if [ "$verdict" = unsafe ]; then
	if [ "$(gh label list --repo "$REPO" --limit 1000 --json name \
		--jq 'any(.[]; .name == "renovate-unsafe")')" != true ]; then
		gh label create renovate-unsafe --repo "$REPO" \
			--description 'Requires human review before deployment' --color B60205 ||
			test "$(gh label list --repo "$REPO" --limit 1000 --json name \
				--jq 'any(.[]; .name == "renovate-unsafe")')" = true
	fi
	gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label renovate-unsafe
	exit 0
fi

if [ "$verdict" != safe ]; then
	echo 'Unrecognized verdict' >&2
	exit 1
fi

# A changed head is expected only if the agent pushed a fix; a later push during
# CI invalidates this review. GitHub checks are tied to this exact head SHA.
for attempt in $(seq 1 90); do
	current=$(gh api "repos/$REPO/pulls/$PR_NUMBER")
	if [ "$(jq -r '.head.sha' <<<"$current")" != "$head" ] ||
		[ "$(jq -r '.base.sha' <<<"$current")" != "$base" ]; then
		echo 'PR head or base changed since the review; refusing to merge' >&2
		exit 1
	fi

	runs=$(gh api "repos/$REPO/actions/workflows/ci.yml/runs?head_sha=$head&event=pull_request&per_page=100")
	run=$(jq -c --arg sha "$head" --arg base "$base" --argjson number "$PR_NUMBER" \
		'[.workflow_runs[] | select(.head_sha == $sha and any(.pull_requests[]; .number == $number and .base.sha == $base))] | sort_by(.created_at) | last // {}' <<<"$runs")
	run_id=$(jq -r '.id // empty' <<<"$run")
	if [ -n "$run_id" ]; then
		jobs=$(gh api --paginate "repos/$REPO/actions/runs/$run_id/jobs?per_page=100" \
			--jq '.jobs[]' | jq -sc '.')
		if [ "$(jq -r '.conclusion' <<<"$run")" = success ] &&
			jq -e '["Validate", "CRD Schema Annotations", "Values Schema Annotations", "Validator Tests"] as $required |
      all($required[]; . as $name | any($jobs[]; .name == $name and .conclusion == "success"))' \
				--argjson jobs "$jobs" -n >/dev/null; then
			break
		fi
		if [ "$(jq -r '.status' <<<"$run")" = completed ] &&
			[ "$(jq -r '.conclusion' <<<"$run")" != success ]; then
			gh pr comment "$PR_NUMBER" --repo "$REPO" \
				--body "Automated merge stopped: CI run $run_id failed on reviewed head $head. A human must investigate before merging."
			echo "CI run $run_id failed; not merging" >&2
			exit 1
		fi
	fi
	if [ "$attempt" -eq 90 ]; then
		gh pr comment "$PR_NUMBER" --repo "$REPO" \
			--body "Automated merge stopped: all four CI jobs did not pass on reviewed head $head within 30 minutes. A human must investigate before merging."
		echo 'Timed out waiting for all four CI jobs; not merging' >&2
		exit 1
	fi
	sleep 20
done

# Never use --admin or --auto: this repository currently has no branch protection.
# The expected head guards against merging a newly pushed, unreviewed update.
current=$(gh api "repos/$REPO/pulls/$PR_NUMBER")
if [ "$(jq -r '.head.sha' <<<"$current")" != "$head" ] ||
	[ "$(jq -r '.base.sha' <<<"$current")" != "$base" ] ||
	[ "$(jq -r '[.labels[].name] | index("renovate-unsafe") != null' <<<"$current")" = true ] ||
	[ "$(jq -r '.state' <<<"$current")" != open ]; then
	echo 'PR changed before merge; refusing to merge' >&2
	exit 1
fi
gh pr merge "$PR_NUMBER" --repo "$REPO" --squash --match-head-commit "$head"
