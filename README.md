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
