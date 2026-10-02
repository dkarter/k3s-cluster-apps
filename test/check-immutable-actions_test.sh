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
if check; then
  echo 'Mutable release tag was accepted' >&2
  exit 1
fi

cat >"$temp_dir/workflow.yml" <<'EOF'
steps:
  - uses: owner/action@0123456789abcdef0123456789abcdef01234567
EOF
if check; then
  echo 'SHA without a version comment was accepted' >&2
  exit 1
fi

cat >"$temp_dir/workflow.yml" <<'EOF'
steps:
  - uses: owner/action@v0
EOF
if check; then
  echo 'Unverifiable tag was accepted' >&2
  exit 1
fi
