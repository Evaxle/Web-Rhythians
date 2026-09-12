# Rhythians browser client

Play at https://evaxle.github.io/Web-Rhythia/.

This version is based on [Evaxle/Rhythian-client](https://github.com/Evaxle/Rhythian-client), pinned to `3d7f153d92aa9fa0922b9d474c5fead5d97ccb72`. It replaces the earlier RhythiaRewrite port. Source licences remain in the submodule. Browser changes are in `patches/web.patch`; GitHub Actions applies them, builds with Godot 3.6.1, runs smoke tests, and publishes Pages.

The web interface uses the Rhythians logo and links to the existing account through the RhythKit device authorization flow. It offers server-paginated maps (40 per page), ratings, ranked status, thumbnails with fallbacks, streamed download progress, an IndexedDB map library, profile and rank progress, Lock/Spin leaderboards, wiki articles, and clips. Battles and tournaments are excluded. The engine loads only when a map is played. Downloaded maps are playable without signing in.

Choose a map, then use the client's native modifier and settings controls before starting. Spin controls `Rhythia.cam_unlock`, and the score camera mode is captured when gameplay begins. Native settings and replays use Godot's IndexedDB-backed user filesystem. The portal stores its account, maps, preferences, and pending score submissions in `RhythiansBrowser` IndexedDB. Clearing site data deletes local content. This replacement does not automatically migrate the earlier rewrite's local profiles.

SSPM v1/v2 files can be dropped onto the page or added to the repository's `maps/` folder. Native libraries remain available through the game's Maps tab. Uploaded repository maps increase the game download size.

## Current service limits

The Rhythians server's bandwidth protection currently pauses map downloads and some media. The client shows the server's explanation and does not bypass that protection.

Client passes are saved to the account with Lock/Spin mode and modifiers. Replay playback, autoplayer, and no-fail runs are excluded. The existing rank system verifies rewards against official Rhythia scores: a browser pass is recorded but does not independently award RPL/RPS/RHP. A separate trusted verification policy would be needed for browser-only rank rewards. The UI explicitly reports pending verification rather than claiming points were granted.

Local verification covers client initialization, both SSPM versions, embedded audio, the real menu, settings restoration, mode-tagged score payloads, and no-fail exclusion. The API changes have TypeScript and CORS checks. Authenticated downloads, real rewarded passes, and interactive browser gameplay require live verification; headless tests do not establish those outcomes.

## Local build

Install Godot 3.6.1 headless and matching WebAssembly templates, then:

```sh
git clone --recurse-submodules https://github.com/Evaxle/Web-Rhythia.git
cd Web-Rhythia
bash scripts/build-web.sh
python3 -m http.server 8080 --directory source/build/web
```

Local browsing of public UI and downloaded maps works on localhost. Account API requests are intentionally allowed only from the production GitHub Pages origin and the Rhythians site.
