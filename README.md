# Web Rhythia

Browser port of [kermeow/RhythiaRewrite](https://github.com/kermeow/RhythiaRewrite), pinned to upstream commit `e1cfba6f23975d18eb111c3c99a6687e39c4278f`.

The `source` submodule contains the original game and its GPL-3.0 licence. Browser compatibility changes live in `patches/web.patch`. GitHub Actions applies the patch and builds with Godot 4.4.1 for GitHub Pages.

GitHub Pages must use **GitHub Actions** as its publishing source in repository Settings → Pages.

The web build uses WebAssembly, WebGL 2 and a single thread. Maps and preferences are stored in this browser. Upstream multiplayer is unfinished.

## Build locally

Install Godot 4.4.1 and its matching web export templates, then run:

```bash
git clone --recurse-submodules https://github.com/Evaxle/Web-Rhythia.git
cd Web-Rhythia
bash scripts/build-web.sh
python3 -m http.server 8080 --directory source/build/web
```

Open `http://localhost:8080`. Do not open `index.html` as a local file.

The launch screen shows download progress, reports startup failures and waits for the main menu before showing the game. Empty map lists and small browser windows are handled without invalid pagination. The upstream repository does not bundle playable maps or implement multiplayer.

## Browser data and map import

Play at https://evaxle.github.io/Web-Rhythia/ using a desktop browser with WebGL 2 enabled. Launch the game, then drop an SSPM file onto the game or use **Import .sspm**. Imports support SSPM v1 and v2 with embedded audio, reject malformed files, detect duplicates, and update the library immediately. The per-file limit is 128 MiB. Return to the menu before importing. Gameplay starts paused; click Resume to grant mouse capture when needed.

The browser port stores settings, maps, map cache, playlists, and replays under `user://WebRhythia`. Godot maps its `/userfs` filesystem to IndexedDB, with file changes synchronized to browser storage. Data belongs to this browser profile and site; clearing site data deletes it. Storage availability and save failures are shown in the page. Desktop paths remain supported for native builds.

## Verification

The build script and Pages workflow generate original SSPM v1/v2 fixtures, run the actual drop/import handler, validate notes and decoded audio duration, check duplicate and truncated-file handling, load gameplay, test pause/resume, save settings and a replay, and restore the map library. A separate Godot process verifies saved maps, settings, and replay restoration. Test fixtures are excluded from the published game.

These headless tests exercise game code and filesystem persistence. They do not prove browser IndexedDB persistence, mouse capture, audio playback, or rendering. The available cloud browser reports WebGL 2 unavailable, so only the published launch screen and its unsupported-browser error have been verified there. Full interactive browser verification remains outstanding. Native test shutdown currently reports upstream resource cleanup warnings. Upstream multiplayer remains unfinished.
