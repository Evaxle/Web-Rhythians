#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p build/web

PROJECT_BACKUP="$(mktemp)"
cp project.godot "$PROJECT_BACKUP"
restore_project() {
  cp "$PROJECT_BACKUP" project.godot
  rm -f "$PROJECT_BACKUP"
}
trap restore_project EXIT

python3 - <<'PY'
from pathlib import Path

path = Path("project.godot")
text = path.read_text()

start = text.find("_global_script_classes=[ {")
end = text.find("} ]\n_global_script_class_icons=", start)
if start != -1 and end != -1:
    prefix = "_global_script_classes=[ {"
    body_start = start + len(prefix)
    body = text[body_start:end]
    entries = body.split("}, {")
    entries = [
        entry for entry in entries
        if '"language": "NativeScript"' not in entry
        and "res://addons/discord_game_sdk/" not in entry
        and "res://addons/godot-openvr/" not in entry
    ]
    rebuilt = prefix + "}, {".join(entries) + "} ]"
    text = text[:start] + rebuilt + text[end + 3:]

lines = text.splitlines()
out = []
skipping = False
for line in lines:
    if line.strip() == "[gdnative]":
        skipping = True
        continue
    if skipping and line.startswith("[") and line.endswith("]"):
        skipping = False
    if not skipping:
        out.append(line)

path.write_text("\n".join(out) + "\n")
PY

python3 - <<'PY'
from pathlib import Path
import base64
Path("web/logo.png").write_bytes(base64.b64decode(Path("web/logo.b64").read_text().strip()))
PY

python3 web/tests/make_fixtures.py
node web/tests/sspm.mjs

run_godot() {
  local logfile="$1"
  shift
  local rc=0
  "$@" >"$logfile" 2>&1 || rc=$?
  sed -e '/VisualServer attempted to free a NULL RID/d' -e '/at: free (servers\/visual\/visual_server_raster.cpp:69)/d' "$logfile"
  return "$rc"
}

check_log() {
  local logfile="$1"
  if grep -E 'SCRIPT ERROR|Parse Error|No library set for this platform|does not have a library for the current platform|Failed loading resource' "$logfile"; then
    return 1
  fi
}

run_godot /tmp/export-pack.log "$GODOT_BIN" --path . --export-pack Web /tmp/rhythians-web-check.pck
check_log /tmp/export-pack.log

run_godot /tmp/export.log "$GODOT_BIN" --path . --export Web build/web/index.html
check_log /tmp/export.log

run_godot /tmp/smoke.log "$GODOT_BIN" --path . web/tests/Smoke.tscn
grep -q 'SMOKE_FAILURES=0' /tmp/smoke.log
check_log /tmp/smoke.log

cp web/app.js web/app.css web/sspm.mjs web/logo.png web/manifest.webmanifest build/web/
test -s build/web/index.html
test -s build/web/index.wasm
test -s build/web/index.pck
grep -q 'https://www.rhythians.com' web/app.js
grep -q 'id="launch-play"' web/shell.html
grep -q 'id="signin-rhythians"' web/shell.html
grep -q 'id="play-guest"' web/shell.html
grep -q 'RhythiansBrowser' web/app.js
grep -q 'rhythiansPersistUserData' web/shell.html
! grep -Rqs 'rhythians-evans-projects-edff1a37.vercel.app' project.godot scripts web
