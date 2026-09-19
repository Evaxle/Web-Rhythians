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
        and "res://vr/" not in entry
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

text = "\n".join(out) + "\n"
text = text.replace("threads/thread_model=2", "threads/thread_model=0")
text = text.replace("quality/directional_shadow/size=1024", "quality/directional_shadow/size=512")
text = text.replace("quality/shadow_atlas/size=2048", "quality/shadow_atlas/size=1024")
text = text.replace("quality/filters/msaa=1", "quality/filters/msaa=0")
path.write_text(text)
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
import json
import re

preset = Path("export_presets.cfg")
text = preset.read_text()
blocked_prefixes = (
    "addons/", "vr/", "test_assets/", "scenes/test/", "debug/", "web/tests/",
)
blocked_exact = {
    "assets/images/ui/dya.webm",
    "assets/worlds/event_horizon/starmap_4k.png",
}
resource_suffixes = {
    ".gd", ".tscn", ".tres", ".res", ".obj", ".dae", ".glb", ".gltf", ".csv",
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".ttf", ".otf",
    ".wav", ".mp3", ".ogg", ".webm", ".shader",
}

def allowed(rel):
    return rel not in blocked_exact and not rel.startswith(blocked_prefixes)

selected = set()
scan_files = []

for base in (Path("scripts"), Path("web")):
    if not base.exists():
        continue
    for path in base.rglob("*.gd"):
        rel = path.as_posix()
        if allowed(rel) and not rel.startswith("web/tests/"):
            selected.add("res://" + rel)
            scan_files.append(path)

pack_smoke = Path("web/PackSmoke.gd")
if pack_smoke.exists():
    selected.add("res://web/PackSmoke.gd")

for core in [
    "default_bus_layout.tres",
    "default_env.tres",
    "uitheme.tres",
    "localization/localization.csv",
]:
    if Path(core).exists():
        selected.add("res://" + core)

for locale in ["en", "ja", "fr", "es", "es (lat)", "de", "pl", "it"]:
    selected.add(f"res://localization/localization.{locale}.translation")

scan_files.append(Path("project.godot"))
path_pattern = re.compile(r'res://[^"\']+')
for path in scan_files:
    try:
        body = path.read_text(errors="ignore")
    except OSError:
        continue
    for match in path_pattern.findall(body):
        rel = match[len("res://"):].strip()
        candidate = Path(rel)
        if not allowed(rel) or not candidate.is_file():
            continue
        if candidate.suffix.lower() in resource_suffixes:
            selected.add("res://" + rel)

for path in Path("assets/songs").glob("*"):
    if path.is_file() and path.suffix.lower() in {".mp3", ".ogg", ".wav"}:
        selected.add("res://" + path.as_posix())

for locale in ["en", "fr", "ja", "pl", "es", "it"]:
    selected.add(f"res://localization/localization.{locale}.translation")

selected = sorted(selected)
encoded = ", ".join(json.dumps(item) for item in selected)
line = "export_files=PoolStringArray(" + encoded + ")"
text = re.sub(r"^export_files=PoolStringArray\(.*\)$", line, text, flags=re.MULTILINE)
preset.write_text(text)
print(f"Web export selected resources: {len(selected)}")
for item in selected:
    print("WEB_RESOURCE", item)
PY

python3 - <<'PY'
from pathlib import Path
import base64
Path("web/rhythians-client.png").write_bytes(base64.b64decode(Path("web/logo.b64").read_text().strip()))
PY

python3 - <<'PY'
from pathlib import Path

limits = {
    "assets/worlds/baseplate/skybox.png.import": 1024,
    "assets/worlds/event_horizon/starmap.png.import": 1024,
    "assets/images/ui/flashlight.png.import": 1024,
    "assets/images/grid_inner.png.import": 1024,
    "assets/images/grid_outer.png.import": 1024,
    "assets/images/spawn_effect.png.import": 1024,
    "assets/notefx/miss/miss.png.import": 1024,
    "assets/notefx/ripple/ripple.png.import": 1024,
    "assets/notefx/shards/shard.png.import": 1024,
    "assets/worlds/neon_tunnel/ring.png.import": 1024,
    "assets/worlds/neon_tunnel/space_ring.png.import": 1024,
    "assets/worlds/neon_tunnel/space_ring_b.png.import": 1024,
}
for name, limit in limits.items():
    path = Path(name)
    if not path.exists():
        continue
    text = path.read_text()
    for mode in ("compress/mode=1", "compress/mode=2", "compress/mode=3"):
        text = text.replace(mode, "compress/mode=0")
    text = text.replace("flags/mipmaps=true", "flags/mipmaps=false")
    text = text.replace("size_limit=0", f"size_limit={limit}")
    path.write_text(text)
PY

python3 web/tests/make_fixtures.py
node web/tests/sspm.mjs
cp web/app.js /tmp/rhythians-app.mjs
node --check /tmp/rhythians-app.mjs

echo "Godot thread usage audit:"
thread_hits="$(grep -RIn --include='*.gd' -E 'Thread\.new\(|\.start\(self|wait_to_finish\(' scripts web 2>/dev/null || true)"
printf '%s\n' "$thread_hits"
if printf '%s\n' "$thread_hits" | grep -v 'scripts/ui/menu/buttons/v3MapList.gd' | grep -q .; then
  echo "Unexpected thread usage remains in Web runtime scripts." >&2
  exit 1
fi

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



rm -f localization/localization.csv.import
echo "Pre-importing Godot resources..."
rm -f localization/localization.csv.import localization/*.translation
"$GODOT_BIN" --path . --editor >/tmp/preimport.log 2>&1 &
preimport_pid=$!
preimport_ok=0
for _ in $(seq 1 480); do
  if [ -s "localization/localization.en.translation" ] \
    && [ -s "localization/localization.ja.translation" ] \
    && [ -s "localization/localization.fr.translation" ] \
    && [ -s "localization/localization.es.translation" ] \
    && [ -s "localization/localization.es (lat).translation" ] \
    && [ -s "localization/localization.de.translation" ] \
    && [ -s "localization/localization.pl.translation" ] \
    && [ -s "localization/localization.it.translation" ]; then
    preimport_ok=1
    break
  fi
  if ! kill -0 "$preimport_pid" 2>/dev/null; then
    break
  fi
  sleep 0.25
done
kill "$preimport_pid" 2>/dev/null || true
wait "$preimport_pid" 2>/dev/null || true
cat /tmp/preimport.log
if [ "$preimport_ok" -ne 1 ]; then
  echo "Godot did not finish generating translation resources before export." >&2
  exit 1
fi

run_godot /tmp/export.log "$GODOT_BIN" --path . --export Web build/web/index.html
check_log /tmp/export.log

PACK_PATH="$(realpath build/web/index.pck)"
rm -rf /tmp/rhythians-pack-smoke
mkdir -p /tmp/rhythians-pack-smoke
pack_rc=0
(
  cd /tmp/rhythians-pack-smoke
  timeout 60s "$GODOT_BIN" --main-pack "$PACK_PATH" --script res://web/PackSmoke.gd
) >/tmp/pack-smoke.log 2>&1 || pack_rc=$?
cat /tmp/pack-smoke.log
if [ "$pack_rc" -ne 0 ] || ! grep -q 'PACK_SMOKE_FAILURES=0' /tmp/pack-smoke.log || grep -E 'SCRIPT ERROR|Parse Error|Cannot load source code|Can.t autoload' /tmp/pack-smoke.log; then
  echo "Exported Web PCK failed runtime dependency validation." >&2
  exit 1
fi

run_smoke /tmp/smoke.log "$GODOT_BIN" --path . web/tests/Smoke.tscn

cp web/app.js web/app.css web/sspm.mjs web/rhythians-client.png web/manifest.webmanifest build/web/

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
echo "Largest imported browser resources:"
find .import -type f -printf '%s %p\n' 2>/dev/null | sort -nr | sed -n '1,25p' || true
echo "Web export sizes:"
du -h build/web/index.wasm build/web/index.pck
pck_bytes="$(stat -c%s build/web/index.pck)"
if [ "$pck_bytes" -gt 83886080 ]; then
  echo "Web PCK is too large ($pck_bytes bytes); keep browser payload below 80 MiB." >&2
  exit 1
fi
require_text 'https://www.rhythians.com' web/app.js 'Rhythians production URL'
require_text 'id="launch-play"' build/web/index.html 'launcher play button'
require_text 'id="signin-rhythians"' build/web/index.html 'Rhythians sign-in button'
require_text 'id="play-guest"' build/web/index.html 'guest play button'
require_text 'id="tools-toggle"' build/web/index.html 'floating browser tools toggle'
require_text 'id="tools-panel"' build/web/index.html 'floating browser tools panel'
require_text 'id="game-toast"' build/web/index.html 'nonblocking game status toast'
require_text 'id="import-sspm"' build/web/index.html 'SSPM import button'
require_text 'id="fullscreen"' build/web/index.html 'fullscreen button'
require_text 'id="change-account"' build/web/index.html 'account button'
require_text 'type="module" src="app.js"' build/web/index.html 'application module'
require_text 'href="rhythians-client.png" type="image/png"' build/web/index.html 'Rhythians-Client web icon'
require_text 'apple-mobile-web-app-title" content="Rhythians-Client"' build/web/index.html 'Rhythians-Client iOS app name'
require_text '"name":"Rhythians-Client"' web/manifest.webmanifest 'Rhythians-Client manifest name'
require_text 'RhythiansBrowser' web/app.js 'browser storage bridge'
require_text 'rhythiansPersistUserData' web/shell.html 'persistent user data bridge'
require_text 'NativeDialogDisabled.gd' scenes/menu/contentmgr.tscn 'web-safe native dialog replacement'
require_text 'rhythiansMobileInputMode' web/app.js 'mobile input mode'
require_text 'id="mobile-mode-choice"' build/web/index.html 'mobile mode chooser'
require_text 'rhythiansAudioContexts' build/web/index.html 'mobile WebAudio context capture'
require_text 'resumeClientAudio' web/app.js 'gesture audio resume'
require_text 'id="mobile-keyboard-textarea"' build/web/index.html 'stable mobile keyboard surface'
require_text 'mobileKeyboardOpen' web/app.js 'mobile keyboard session state'
require_text 'func lookup_song(song,quiet:bool=false):' scripts/Rhythian.gd 'Play-map Rhythians lookup'
require_text 'func start_auto_link_unchecked():' scripts/Rhythian.gd 'startup unchecked-map linking'
require_text 'get_unchecked_local_songs' scripts/Rhythian.gd 'unchecked local map queue'
require_text 'Rhythian.start_auto_link_unchecked()' scripts/ui/menu/buttons/v3MapList.gd 'Play startup auto map check'
require_text 'RhythianStatus' scripts/ui/menu/buttons/v3MapList.gd 'Rhythians status badge on every Play map'
require_text '_rhythian_badge_box' scripts/ui/menu/buttons/v3MapList.gd 'styled Rhythians status badge'
require_text 'abs(run_start_offset)>0.001' web/Bridge.gd 'start-offset score qualification'
require_text 'fallbackStorageKey' web/app.js 'resilient browser storage'
require_text 'immersive-fallback' web/app.js 'fullscreen fallback'
require_text '"cameraMode": "spin" if Rhythia.cam_unlock else "lock"' scripts/Rhythian.gd 'web score camera mode'
require_text 'sidebar.has_method("to_play")' web/Bridge.gd 'normal client play navigation'
require_text 'if not OS.has_feature("HTML5"):' scripts/ui/menu/buttons/v3MapList.gd 'HTML5 cover preload guard'
require_text 'export_filter="resources"' export_presets.cfg 'dependency-based Web export'
require_text 'vram_texture_compression/for_mobile=false' export_presets.cfg 'single browser texture target'
require_text 'maps_page_limit:int = 40' scripts/Rhythian.gd '40-map server-paged browser catalog'
require_text 'if catalog_loading:' scripts/Rhythian.gd 'duplicate map catalog load guard'
require_text 'page_epoch:int=0' scripts/ui/menu/RhythiansPortal.gd 'tab generation guard'
require_text 'var page_size=40' scripts/ui/menu/RhythiansPortal.gd '40-map UI paging'
require_text 'fetch_maps_page' scripts/ui/menu/RhythiansPortal.gd 'server paged Maps requests'
require_text 'copyBrowserFileToFS' web/app.js 'chunked SSPM drag import'
require_text 'MAP_CACHE_NAME="rhythians-map-files-v1"' web/app.js 'map files stored outside WebAssembly'
require_text 'window.rhythiansDownloadMap' web/app.js 'browser cache map download bridge'
require_text 'window.rhythiansOpenDownloadedMap' web/app.js 'cached map materialization bridge'
require_text 'window.gameEngine.copyToFS(path,buffer)' web/app.js 'Godot filesystem fallback for cached SSPMs'
require_text 'dir.copy(temp_path,target)' web/Bridge.gd 'persist downloaded SSPM into user map library'
require_text 'window/stretch/mode.HTML5="2d"' project.godot 'HTML5 responsive 2D stretch'
require_text 'canvasResizePolicy=2' web/shell.html 'adaptive Godot canvas resize policy'
require_text 'action:"mobile-layout"' web/app.js 'mobile viewport bridge'
require_text 'func apply_mobile_layout(width:float,height:float,touch:bool):' scripts/ui/menu/Sidebar.gd 'mobile top navigation layout'
require_text 'catalog_grid.columns=1 if mobile_width<620 else (2 if mobile_width<980 else 4)' scripts/ui/menu/RhythiansPortal.gd 'mobile map catalog columns'
require_text 'const cacheWrite=cache.put(key,response.clone())' web/app.js 'native browser map cache streaming'
require_text 'const reader=response.body.getReader()' web/app.js 'live browser download progress reader'
require_text 'map_download_buttons[id].visible=false' scripts/ui/menu/RhythiansPortal.gd 'Download button replaced after completion'
require_text 'Rhythian.register_runtime_song(song,active_map)' web/Bridge.gd 'cached map metadata bound to Play song'
require_text 'RhythianMeta' scripts/ui/menu/buttons/v3MapList.gd 'Play menu Rhythians difficulty and reward metadata'
require_text 'RhythianIcon' scripts/ui/menu/buttons/v3MapList.gd 'Play menu Rhythians icon'
require_text 'Rhythian.submit_web_score' web/Bridge.gd 'single browser score submission path'
require_text 'WebPortal.finished()' scripts/game/Game.gd 'real browser song-end score submission hook'
require_text 'Rhythia.cam_unlock=value' scripts/ui/menu/RhythiansPortal.gd 'Spin setting controls gameplay and score mode'
if grep -Fq 'Rhythia.cam_unlock = bool(data.get("spin"' web/Bridge.gd; then
  echo "Map opening must not override the Settings spin mode" >&2
  exit 1
fi
require_text 'if not is_visible_in_tree():' scripts/ui/menu/buttons/v3MapList.gd 'hidden Play map processing guard'
require_text '["settings","Settings"]' scripts/ui/menu/Sidebar.gd 'native Settings nav entry'
require_text 'func open_native_page(page:String):' scripts/ui/menu/Sidebar.gd 'native page navigation'
require_text 'var play_root = get_node_or_null("../Main/Maps")' scripts/ui/menu/Sidebar.gd 'Play root restoration'
require_text 'func get_map_summary(map:Dictionary) -> String:' scripts/Rhythian.gd 'persisted Rhythians map metadata summary'
require_text 'RPL %s · RPS %s · RPV %s' scripts/Rhythian.gd 'all rank reward types'
require_text 'func _safe_user_name(user:Dictionary) -> String:' scripts/ui/menu/RhythiansPortal.gd 'online player null-name fallback'
require_text 'func _profile_link(parent:Container,user:Dictionary' scripts/ui/menu/RhythiansPortal.gd 'clickable in-client player links'
require_text 'Open on Rhythians' scripts/ui/menu/RhythiansPortal.gd 'full profile website action'
require_text 'Browse players' scripts/ui/menu/RhythiansPortal.gd 'player browser action'
require_text 'field.connect("text_entered",self,"_run_user_search_entered"' scripts/ui/menu/RhythiansPortal.gd 'keyboard-friendly user search'
require_text 'state_panel.rect_size=Vector2(24,24)' scripts/ui/menu/buttons/v3MapList.gd 'compact map status state chip'
require_text 'get_parent().get_node_or_null("ImportSettings")' web/tests/Smoke.gd 'settings import control smoke test'
require_text 'func request_settings_import():' web/Bridge.gd 'browser settings import bridge'
require_text 'id="settings-picker"' build/web/index.html 'browser settings picker'
require_text 'window.rhythiansRequestSettingsImport' build/web/app.js 'browser settings import request handler'
require_text 'request.use_threads=not OS.has_feature("HTML5")' scripts/network/ClipClient.gd 'Web-safe clip networking'
if grep -Fq 'tween.tween_property(btns[i]' scripts/ui/menu/buttons/v3MapList.gd; then
  echo "Per-frame map-list tween allocation regression found" >&2
  exit 1
fi
if grep -Fq 'sidebar.press(' web/Bridge.gd; then
  echo "Obsolete Sidebar.press call found in web bridge" >&2
  exit 1
fi
if grep -Eq 'calc\(100(d)?vh - 52px\)' web/app.css; then
  echo "Old fixed browser toolbar layout regression found" >&2
  exit 1
fi
reject_text_tree 'rhythians-evans-projects-edff1a37.vercel.app' project.godot scripts web
