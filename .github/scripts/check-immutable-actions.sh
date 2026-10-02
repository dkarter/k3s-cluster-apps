#!/usr/bin/env bash
set -euo pipefail

if (($# == 0)); then
  set -- .github/workflows/*.yml .github/workflows/*.yaml
fi

failed=0
for file in "$@"; do
  [[ -f "$file" ]] || continue
  # shellcheck disable=SC2016 # $line is a yq variable, not a shell variable.
  if ! entries=$(yq -r '.. | select(has("uses")) | (.uses | line) as $line | [.uses, $line] | @tsv' "$file"); then
    echo "$file: could not read workflow actions" >&2
    failed=1
    continue
  fi
  while IFS=$'\t' read -r action line_number; do
    [[ -n "$action" ]] || continue
    source_line=$(awk -v start="$line_number" -v ref="$action" 'NR >= start && index($0, ref) { print; exit }' "$file")

    case "$action" in
    actions/* | github/* | ./*) continue ;;
    docker://*)
      if [[ ! "$action" =~ ^docker://[^@]+@sha256:[0-9a-fA-F]{64}$ ]]; then
        echo "$file: Docker action must use a sha256 digest: $action" >&2
        failed=1
      fi
      continue
      ;;
    esac

    if [[ ! "$action" =~ ^([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)(/[^@]+)?@(.+)$ ]]; then
      echo "$file: invalid third-party action reference: $action" >&2
      failed=1
      continue
    fi

    owner=${BASH_REMATCH[1]}
    repo=${BASH_REMATCH[2]}
    ref=${BASH_REMATCH[4]}
    if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
      if [[ ! "$source_line" =~ \#[[:space:]]*v[0-9]+([.][0-9]+)*([.-][a-zA-Z0-9.-]+)?[[:space:]]*$ ]]; then
        echo "$file: SHA-pinned action needs a version comment (# vX.Y.Z): $action" >&2
        failed=1
      fi
      continue
    fi

    # Immutable GitHub releases lock their associated tags. A comment claiming
    # immutability or a protected tag alone is not proof that the ref cannot move.
    encoded_ref=$(jq -rn --arg ref "$ref" '$ref | @uri')
    if ! immutable=$(gh api "repos/$owner/$repo/releases/tags/$encoded_ref" --jq '.immutable' 2>/dev/null); then
      echo "$file: cannot verify immutable release for $action (pin a full commit SHA or check GitHub API access)" >&2
      failed=1
    elif [[ "$immutable" != true ]]; then
      echo "$file: release tag is not immutable: $action (pin a full commit SHA)" >&2
      failed=1
    fi
  done <<<"$entries"
done

exit "$failed"
