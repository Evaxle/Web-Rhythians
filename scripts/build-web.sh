#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
git submodule update --init --recursive
if git -C source apply --check ../patches/web.patch; then
  git -C source apply ../patches/web.patch
elif ! git -C source apply --reverse --check ../patches/web.patch; then
  echo 'The source contains changes that conflict with the web patch.' >&2
  exit 1
fi
"$GODOT_BIN" --headless --editor --path source --import
python3 source/tests/make_fixtures.py
test_data=$(mktemp -d)
timeout 30s env XDG_DATA_HOME="$test_data" "$GODOT_BIN" --headless --path source tests/Integration.tscn 2>&1 | tee "$test_data/integration.log"
grep -q 'INTEGRATION_FAILURES=0' "$test_data/integration.log"
if grep -Eq 'SCRIPT ERROR|FAIL:' "$test_data/integration.log"; then exit 1; fi
timeout 30s env XDG_DATA_HOME="$test_data" "$GODOT_BIN" --headless --path source tests/Restore.tscn 2>&1 | tee "$test_data/restore.log"
grep -q 'FRESH_PROCESS_RESTORE=true' "$test_data/restore.log"
if grep -q 'SCRIPT ERROR' "$test_data/restore.log"; then exit 1; fi
mkdir -p source/build/web
export_log=$(mktemp)
trap 'rm -f "$export_log"' EXIT
"$GODOT_BIN" --headless --path source --export-release Web build/web/index.html 2>&1 | tee "$export_log"
if grep -Eq 'SCRIPT ERROR|Failed to load script|Parse Error' "$export_log"; then
  exit 1
fi
test -s source/build/web/index.html
test -s source/build/web/index.wasm
test -s source/build/web/index.pck
touch source/build/web/.nojekyll
