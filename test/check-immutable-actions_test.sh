#!/usr/bin/env bash
set -euo pipefail

temp_dir=$(mktemp -d)
trap 'rm -f "$temp_dir/gh" "$temp_dir/workflow.yml"; rmdir "$temp_dir"' EXIT
cat >"$temp_dir/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  */v1.2.3) echo true ;;
  */v2.0.0) echo false ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$temp_dir/gh"

check() {
  PATH="$temp_dir:$PATH" bash .github/scripts/check-immutable-actions.sh "$temp_dir/workflow.yml"
}

expect_rejection() {
  local output
  if output=$(check 2>&1); then
    echo "Expected rejection: $1" >&2
    exit 1
  fi
  if [[ "$output" != *"$1"* ]]; then
    printf 'Expected diagnostic: %s\nActual output: %s\n' "$1" "$output" >&2
    exit 1
  fi
}

cat >"$temp_dir/workflow.yml" <<'EOF'
steps:
  - uses: actions/checkout@v7
  - uses: ./local-action
  - uses: owner/action@v1.2.3
  - uses: owner/action/path@0123456789abcdef0123456789abcdef01234567 # v1.2.3
EOF
check

cat >"$temp_dir/workflow.yml" <<'EOF'
steps:
  - uses: owner/action@v2.0.0
EOF
expect_rejection 'release tag is not immutable: owner/action@v2.0.0'

cat >"$temp_dir/workflow.yml" <<'EOF'
steps:
  - uses: owner/action@0123456789abcdef0123456789abcdef01234567
EOF
expect_rejection 'SHA-pinned action needs a version comment (# vX.Y.Z)'

cat >"$temp_dir/workflow.yml" <<'EOF'
steps:
  - uses: owner/action@v0
EOF
expect_rejection 'cannot verify immutable release for owner/action@v0'
