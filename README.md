# Web Rhythia

Browser port of [kermeow/RhythiaRewrite](https://github.com/kermeow/RhythiaRewrite), pinned to upstream commit `e1cfba6f23975d18eb111c3c99a6687e39c4278f`.

The `source` submodule contains the original game and its GPL-3.0 licence. Browser compatibility changes live in `patches/web.patch`. GitHub Actions applies the patch and builds with Godot 4.4.1 for GitHub Pages.

GitHub Pages must use **GitHub Actions** as its publishing source in repository Settings → Pages.

The web build uses WebAssembly, WebGL 2 and a single thread. Maps and preferences are stored in this browser. Upstream multiplayer is unfinished.
