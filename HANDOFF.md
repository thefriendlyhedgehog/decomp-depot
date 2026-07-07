# Decomp Depot — Development Handoff

**Last updated:** 2026-07-07
**Script version:** 2,058 lines, 53 functions
**Status:** Ready to fork/commit

## Current State

### What works
- All 5 game ports download, install, detect, migrate, and uninstall correctly
- Mod manager with size display, conflict warnings, enable/disable, remove
- Steam shortcuts with backup, display names, and status indicators
- Install location migration with single summary popup and previous-location tracking
- Inline changelogs with "Close" buttons
- ROM dumping guide
- QA checker validates all configs, URLs, and code structure

### What's disabled
- **OoTMM Randomizer** — hidden from menu, code retained. Broken by SteamOS webkit2gtk regression (July 4, 2026 update). Re-enable by uncommenting 2 lines in main dispatch + 1 line in main_menu.

### Known limitations
- Steam `shortcuts.vdf` is a binary format — there's no clean API; we write directly with backup
- Zenity `--text-info` always shows two buttons (can't hide one)
- GameBanana doesn't return Content-Length for some mod URLs (size shows as unknown)
- OoTMM generation hangs on Steam Deck (upstream issue)

## Architecture

### Config arrays (top of script)
```
GAME_NAME, GAME_REPO, GAME_ASSET_PREFIX, GAME_APPIMAGE, GAME_DIR, GAME_OTR, GAME_CHANGELOG
MODS_AVAILABLE, MOD_URL, MOD_FILE, MOD_DISPLAY_NAME, MOD_DESC
```

### Key functions
- `download_game` — handles both ZIP (HarbourMasters) and direct AppImage (Dusklight) downloads
- `set_install_location` — migration with both-location detection and single summary
- `migrate_dir` — shared helper for moving/merging directories
- `mod_do_download` — data-driven mod installer with size checking
- `add_steam_shortcut` — binary VDF writer with backup
- `github_latest_tag` / `github_latest_asset_url` — shared GitHub API helpers
- `get_ootmm_dir` — dynamic path resolution (was hardcoded, now follows base_dir)
- `ootmm_download` — includes resources.neu extraction to physical directory

### Shared helpers (deduplication)
- `github_latest_tag(repo)` — fetch latest release tag
- `github_latest_asset_url(repo, filter)` — fetch download URL by asset name filter
- `migrate_dir(name, src, target)` — unified merge/move logic
- `extract_z64_from_zip(zipfile)` — extract ROM from ZIP
- `format_size(bytes)` — human-readable file size
- `get_url_size(url)` — HTTP HEAD to get content-length

## Recent Changes (this session)

### Removed
- `play_game()` — users launch via Steam/external
- `convert_rom_to_z64()` — no longer needed without play
- `disable_satella()` — no longer needed without play
- `GAME_ROM_EXTS` array
- SteamID terminal echo
- Changelog browser fallback on cancel
- Dead `Download` handler in OoTMM menu
- `ootmm_play()` and `ootmm_find_emulator()`

### Added
- Dusklight (Twilight Princess) port with direct AppImage download
- `ootmm_uninstall()` function
- Large mod warning with HTTP HEAD size detection
- Mod sizes shown in download confirmation prompt
- `resources.neu` extraction in OoTMM download
- Steam shortcut backup + Steam running detection
- SteamOS webkit env vars for OoTMM launch
- Previous base_dir tracking for migration
- QA checker (`qa-check.sh`)

### Fixed
- OoTMM migration detection (glob patterns instead of hardcoded paths)
- Steam shortcuts showing internal keys instead of display names
- Starship blank name error in Steam shortcuts
- `ootmm_launch_gui` false positive on any .z64 in Downloads
- `set_install_location` early return preventing old-location check
- Migration showing multiple popups (now single summary)
- `changelog_game` using raw `python3` instead of `$PYTHON`
- `ootmm_download` saving empty version tag for fresh installs
- Dusklight missing from main dispatch handler

## Testing

Run `bash qa-check.sh` for automated validation. Manual checklist is printed at the end of the QA output.

## OoTMM Issue Details

- **Symptom:** UI loads, clicking "Generate" shows "Your seed is being generated" but never completes
- **Root cause:** SteamOS July 4, 2026 update broke webkit2gtk Web Worker / WebAssembly
- **Confirmed:** Same version (v31.0) worked July 3, broken after July 4 update
- **Not a script bug:** OoTMM fails even when launched manually outside our script
- **Pinned version:** `OOTMM_PINNED_TAG="v31.0"` in config
- **Resources extracted:** `resources.neu` is now extracted to physical `resources/` directory (workaround for Neutralino bundle reading issue)
- **To re-enable:** Uncomment menu entry in `main_menu()` and dispatch in main loop
