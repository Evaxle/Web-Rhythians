#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p build/web
python3 - <<'PY2'
from pathlib import Path
import base64
Path('web/logo.png').write_bytes(base64.b64decode(Path('web/logo.b64').read_text().strip()))
PY2
python3 web/tests/make_fixtures.py
node web/tests/sspm.mjs
"$GODOT_BIN" --path . --export-pack Web /tmp/rhythians-web-check.pck 2>&1 | tee /tmp/export-pack.log
if grep -E 'SCRIPT ERROR|Parse Error' /tmp/export-pack.log; then exit 1; fi
"$GODOT_BIN" --path . --export Web build/web/index.html 2>&1 | tee /tmp/export.log
if grep -E 'SCRIPT ERROR|Parse Error' /tmp/export.log; then exit 1; fi
"$GODOT_BIN" --path . web/tests/Smoke.tscn 2>&1 | tee /tmp/smoke.log
grep -q 'SMOKE_FAILURES=0' /tmp/smoke.log
cp web/app.js web/app.css web/sspm.mjs web/logo.png web/manifest.webmanifest build/web/
test -s build/web/index.html
test -s build/web/index.wasm
test -s build/web/index.pck
grep -q 'https://www.rhythians.com' web/app.js
grep -q 'id="import-sspm"' web/shell.html
grep -q 'RhythiansBrowser' web/app.js
grep -q 'rhythiansPersistUserData' web/shell.html
! grep -Rqs 'https://rhythians.vercel.app' project.godot scripts/Rhythian.gd web/app.js
