#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
git submodule update --init --recursive
if git -C source apply --check ../patches/web.patch; then
  git -C source apply ../patches/web.patch
elif ! git -C source apply --reverse --check ../patches/web.patch; then
  echo 'The source conflicts with the web patch.' >&2
  exit 1
fi
python3 - <<'PY'
from pathlib import Path
root = Path("source")
prod = "https://www.rhythians.com"
for rel in ["project.godot", "web/app.js"]:
    path = root / rel
    text = path.read_text()
    text = text.replace("https://rhythians.vercel.app", prod)
    path.write_text(text)
shell_path = root / "web/shell.html"
shell = shell_path.read_text()
runtime = """<script>
window.rhythiansPersistUserData=()=>new Promise((resolve,reject)=>{
  const fs=globalThis.FS||(globalThis.Module&&globalThis.Module.FS);
  if(!fs||typeof fs.syncfs!=='function'){resolve(false);return;}
  fs.syncfs(false,error=>error?reject(error):resolve(true));
});
if(navigator.storage&&navigator.storage.persist)navigator.storage.persist().catch(()=>{});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')window.rhythiansPersistUserData().catch(()=>{});});
addEventListener('pagehide',()=>window.rhythiansPersistUserData().catch(()=>{}));
setInterval(()=>window.rhythiansPersistUserData().catch(()=>{}),10000);
</script>"""
if "rhythiansPersistUserData" not in shell:
    shell = shell.replace("$GODOT_HEAD_INCLUDE", "$GODOT_HEAD_INCLUDE" + runtime)
shell_path.write_text(shell)
PY
python3 - <<'PY'
from pathlib import Path
import base64
root = Path('source')
logo = base64.b64decode((root / 'web/logo.b64').read_text())
for name in ['logo.png', 'icon.png', 'splash.png', 'rhythians.png', 'sspicon.png']:
    (root / 'assets/images/branding' / name).write_bytes(logo)
(root / 'web/logo.png').write_bytes(logo)
PY
grep -q "https://www.rhythians.com" source/web/app.js
grep -q 'networking/rhythians_url="https://www.rhythians.com"' source/project.godot
grep -q "RhythiansBrowser" source/web/app.js
grep -q "rhythiansPersistUserData" source/web/shell.html
if grep -Rqs "https://rhythians.vercel.app" source/web source/project.godot; then exit 1; fi
mkdir -p source/bundled_maps source/build/web
find maps -maxdepth 1 -type f -iname '*.sspm' -exec cp {} source/bundled_maps/ \;
python3 source/web/tests/make_fixtures.py
node source/web/tests/sspm.mjs
"$GODOT_BIN" --path source --export-pack Web /tmp/rhythians-import.pck > /tmp/rhythians-import.log 2>&1
"$GODOT_BIN" --path source --export Web build/web/index.html 2>&1 | tee /tmp/rhythians-export.log
if grep -Eq 'SCRIPT ERROR|Parse Error|Failed loading resource' /tmp/rhythians-export.log; then exit 1; fi
test_data=$(mktemp -d)
timeout 30s env XDG_DATA_HOME="$test_data" "$GODOT_BIN" --path source web/tests/Smoke.tscn 2>&1 | tee /tmp/rhythians-smoke.log
grep -q 'SMOKE_FAILURES=0' /tmp/rhythians-smoke.log
if grep -Eq 'SCRIPT ERROR|FAIL:' /tmp/rhythians-smoke.log; then exit 1; fi
cp source/web/app.js source/web/sspm.mjs source/web/app.css source/web/logo.png source/build/web/
cp source/web/logo.png source/build/web/favicon.ico
test -s source/build/web/index.wasm
test -s source/build/web/index.pck
touch source/build/web/.nojekyll
