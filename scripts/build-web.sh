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
