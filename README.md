# Rhythians browser client

Play at https://evaxle.github.io/Web-Rhythians/.

This version is based on [Evaxle/Rhythian-client](https://github.com/Evaxle/Rhythian-client), pinned to `3d7f153d92aa9fa0922b9d474c5fead5d97ccb72`. It replaces the earlier RhythiaRewrite port. Source licences remain in the submodule. Browser changes are in `patches/web.patch`; GitHub Actions applies them, builds with Godot 3.6.1, runs smoke tests, and publishes Pages.

The web interface uses the Rhythians logo and links accounts through the RhythKit device authorization flow on `https://www.rhythians.com`. The browser never needs the user's Rhythians password. The linked installation token is stored locally and is used for authenticated maps, profile data, public user search, public profiles, leaderboards, clips, wiki content, and supported client submissions.

The portal offers server-paginated maps (40 per page), ratings, ranked status, thumbnails with fallbacks, streamed download progress, an IndexedDB map library, profile and rank progress, public Rhythians user search and profiles, Lock/Spin leaderboards, wiki articles, and clips. Battles and tournaments are excluded. The engine loads only when a map is played. Downloaded maps are playable without signing in.

## Browser storage

Anything the native Godot client normally stores in `%APPDATA%` through `user://` is kept in Godot's browser filesystem backed by IndexedDB. The web shell requests persistent browser storage and flushes that filesystem periodically, when the page becomes hidden, and when the page is closed or navigated away from. Settings, replays, native client state, map metadata, and other `user://` files therefore survive ordinary reloads and browser restarts.

The surrounding portal uses a separate `RhythiansBrowser` IndexedDB database for the linked account, downloaded map blobs, map metadata, preferences, and pending score submissions. Browser persistence is still controlled by the browser: clearing site data removes local content, and a browser can decline the persistent-storage request.

Choose a map, then use the client's native modifier and settings controls before starting. Spin controls `Rhythia.cam_unlock`, and the score camera mode is captured when gameplay begins.

SSPM v1/v2 files can be dropped onto the page or added to the repository's `maps/` folder. Native libraries remain available through the game's Maps tab. Uploaded repository maps increase the game download size.

## Rhythians integration

Production client API traffic targets `https://www.rhythians.com/api/rhythkit/*`. Login uses device authorization: the browser receives a short code, the user approves it on Rhythians, and the browser receives a scoped installation token. The GitHub Pages origin is permitted only for the RhythKit API surface rather than normal account/admin APIs.

Maps, the linked user's profile and rank data, public user search, other users' public profiles, leaderboards, clips, wiki data, and other supported portal data come from Rhythians. Public profile views expose the same public-facing information used by the Rhythians portal rather than private account fields.

## Current service limits

The Rhythians server's bandwidth protection currently pauses map downloads and some media. The client shows the server's explanation and does not bypass that protection.

Client passes are saved to the account with Lock/Spin mode and modifiers. Replay playback, autoplayer, and no-fail runs are excluded. The existing rank system verifies rewards against official Rhythia scores: a browser pass is recorded but does not independently award RPL/RPS/RHP. A separate trusted verification policy would be needed for browser-only rank rewards. The UI explicitly reports pending verification rather than claiming points were granted.

Local verification covers client initialization, both SSPM versions, embedded audio, the real menu, settings restoration, mode-tagged score payloads, no-fail exclusion, production API configuration, browser persistence hooks, and public-user integration. Authenticated downloads, real rewarded passes, and interactive browser gameplay still depend on the live Rhythians services.

## Local build

Install Godot 3.6.1 headless and matching WebAssembly templates, then:

```sh
git clone --recurse-submodules https://github.com/Evaxle/Web-Rhythians.git
cd Web-Rhythians
bash scripts/build-web.sh
python3 -m http.server 8080 --directory source/build/web
```

Local browsing of public UI and downloaded maps works on localhost. Account API requests are intentionally allowed only from the production GitHub Pages origin and the Rhythians site.
