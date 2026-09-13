# Rhythians Web

Browser/WebAssembly build of the Rhythian client. Gameplay stays in the original Godot client; browser-only compatibility code replaces unsupported desktop APIs.

## Browser features

- Device-code sign-in through `https://www.rhythians.com`; the browser never stores the website password.
- Rhythians maps, profile, leaderboard, wiki and clips integration.
- Godot `user://` data backed by browser persistence and explicitly flushed to IndexedDB.
- `RhythiansBrowser` IndexedDB stores the scoped account token, downloaded SSPM blobs, map metadata, browser settings and pending score submissions.
- SSPM import button, multi-file import, Ctrl/Cmd+O and drag-and-drop.
- Downloaded/local maps remain playable from the browser library.
- Fullscreen gameplay and lazy WebAssembly startup.

Clearing site data removes local maps/settings. Desktop Discord Rich Presence, OpenVR and native OS file dialogs are disabled in the web build. Browser score rewards still require server-side verification.
