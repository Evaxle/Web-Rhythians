#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p build/web

PROJECT_BACKUP="$(mktemp)"
CONTENTMGR_BACKUP="$(mktemp)"
NATIVE_BACKUP="$(mktemp -d)"
cp project.godot "$PROJECT_BACKUP"
cp scenes/menu/contentmgr.tscn "$CONTENTMGR_BACKUP"

restore_project() {
  cp "$PROJECT_BACKUP" project.godot
  cp "$CONTENTMGR_BACKUP" scenes/menu/contentmgr.tscn
  for addon in discord_game_sdk godot-openvr native_dialogs; do
    if [ -d "$NATIVE_BACKUP/$addon" ]; then
      rm -rf "addons/$addon"
      mv "$NATIVE_BACKUP/$addon" "addons/$addon"
    fi
  done
  rm -f "$PROJECT_BACKUP" "$CONTENTMGR_BACKUP"
  rmdir "$NATIVE_BACKUP" 2>/dev/null || true
}
trap restore_project EXIT

for addon in discord_game_sdk godot-openvr native_dialogs; do
  if [ -d "addons/$addon" ]; then
    mv "addons/$addon" "$NATIVE_BACKUP/$addon"
  fi
done

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

icons_start = text.find("_global_script_class_icons={")
if icons_start != -1:
    icons_end = text.find("\n}\n\n[application]", icons_start)
    if icons_end != -1:
        text = text[:icons_start] + text[icons_end + 3:]

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

path = Path("scenes/menu/contentmgr.tscn")
text = path.read_text()
text = text.replace("res://addons/native_dialogs/bin/native_dialog_open_file.gdns", "res://web/NativeDialogDisabled.gd")
text = text.replace("res://addons/native_dialogs/bin/native_dialog_select_folder.gdns", "res://web/NativeDialogDisabled.gd")
path.write_text(text)
PY

python3 - <<'PY'
from pathlib import Path
import base64
Path("web/logo.png").write_bytes(base64.b64decode(Path("web/logo.b64").read_text().strip()))
PY

rm -f localization/localization.csv.import

python3 web/tests/make_fixtures.py
node web/tests/sspm.mjs
cp web/app.js /tmp/rhythians-app.mjs
node --check /tmp/rhythians-app.mjs

run_godot() {
  local logfile="$1"
  shift
  local rc=0
  echo "Running: $*"
  timeout 300s "$@" >"$logfile" 2>&1 || rc=$?
  sed -e '/VisualServer attempted to free a NULL RID/d' -e '/at: free (servers\/visual\/visual_server_raster.cpp:69)/d' "$logfile"
  if [ "$rc" -eq 124 ]; then
    echo "Godot command timed out after 300 seconds: $*" >&2
  fi
  return "$rc"
}

run_smoke() {
  local logfile="$1"
  shift
  local rc=0
  echo "Running smoke: $*"
  timeout 300s "$@" >"$logfile" 2>&1 || rc=$?
  awk '/SMOKE_FAILURES=0/ { print; exit } /VisualServer attempted to free a NULL RID/ { next } /at: free \(servers\/visual\/visual_server_raster.cpp:69\)/ { next } { print }' "$logfile"
  if [ "$rc" -eq 124 ]; then
    echo "Godot smoke test timed out after 300 seconds: $*" >&2
    return 124
  fi
  if ! grep -q 'SMOKE_FAILURES=0' "$logfile"; then
    echo "Godot smoke test did not report success." >&2
    if [ "$rc" -ne 0 ]; then return "$rc"; else return 1; fi
  fi
  if grep -E 'SCRIPT ERROR|Parse Error|No library set for this platform|does not have a library for the current platform' "$logfile"; then
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    echo "Smoke assertions passed; ignoring Godot headless teardown exit code $rc."
  fi
  return 0
}

check_log() {
  local logfile="$1"
  if grep -E 'SCRIPT ERROR|Parse Error|No library set for this platform|does not have a library for the current platform' "$logfile"; then
    return 1
  fi
}



run_godot /tmp/export.log "$GODOT_BIN" --path . --export Web build/web/index.html
check_log /tmp/export.log

run_smoke /tmp/smoke.log "$GODOT_BIN" --path . web/tests/Smoke.tscn

cp web/app.js web/app.css web/sspm.mjs web/logo.png web/manifest.webmanifest build/web/

require_file() {
  if [ ! -s "$1" ]; then
    echo "Missing or empty build output: $1" >&2
    return 1
  fi
}

require_text() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "Missing expected build content: $label ($file)" >&2
    return 1
  fi
}

reject_text_tree() {
  local pattern="$1"
  shift
  if grep -RqsF --exclude="build-web.sh" "$pattern" "$@"; then
    echo "Forbidden stale build content found: $pattern" >&2
    return 1
  fi
}

require_file build/web/index.html
require_file build/web/index.wasm
require_file build/web/index.pck
require_text 'https://www.rhythians.com' web/app.js 'Rhythians production URL'
require_text 'id="launch-play"' build/web/index.html 'launcher play button'
require_text 'id="signin-rhythians"' build/web/index.html 'Rhythians sign-in button'
require_text 'id="play-guest"' build/web/index.html 'guest play button'
require_text 'id="import-sspm"' build/web/index.html 'SSPM import button'
require_text 'id="fullscreen"' build/web/index.html 'fullscreen button'
require_text 'id="change-account"' build/web/index.html 'account button'
require_text 'type="module" src="app.js"' build/web/index.html 'application module'
require_text 'href="logo.png" type="image/png"' build/web/index.html 'web icon'
require_text 'RhythiansBrowser' web/app.js 'browser storage bridge'
require_text 'rhythiansPersistUserData' web/shell.html 'persistent user data bridge'
require_text 'NativeDialogDisabled.gd' scenes/menu/contentmgr.tscn 'web-safe native dialog replacement'
require_text 'rhythiansMobileInputMode' web/app.js 'mobile input mode'
require_text 'id="mobile-mode-choice"' build/web/index.html 'mobile mode chooser'
require_text 'fallbackStorageKey' web/app.js 'resilient browser storage'
require_text 'immersive-fallback' web/app.js 'fullscreen fallback'
require_text '"cameraMode": "spin" if Rhythia.cam_unlock else "lock"' scripts/Rhythian.gd 'web score camera mode'
require_text 'sidebar.has_method("to_play")' web/Bridge.gd 'normal client play navigation'
if grep -Fq 'sidebar.press(' web/Bridge.gd; then
  echo "Obsolete Sidebar.press call found in web bridge" >&2
  exit 1
fi
reject_text_tree 'rhythians-evans-projects-edff1a37.vercel.app' project.godot scripts web
