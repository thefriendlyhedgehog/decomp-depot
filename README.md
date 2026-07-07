# Decomp Depot

A desktop-friendly installer, updater, and mod manager for **decompilation ports** of classic games. Designed for the Steam Deck but works on any Linux distro.

## Supported Ports

| Port | Game | Source | Repo |
|------|------|--------|------|
| **Ship of Harkinian** (SoH) | Ocarina of Time | HarbourMasters | [Shipwright](https://github.com/HarbourMasters/Shipwright) |
| **2 Ship 2 Harkinian** (2S2H) | Majora's Mask | HarbourMasters | [2ship2harkinian](https://github.com/HarbourMasters/2ship2harkinian) |
| **Ghostship** | Super Mario 64 | HarbourMasters | [Ghostship](https://github.com/HarbourMasters/Ghostship) |
| **Starship** | Star Fox 64 | HarbourMasters | [Starship](https://github.com/HarbourMasters/Starship) |
| **Dusklight** | Twilight Princess | TwilitRealm | [dusklight](https://github.com/TwilitRealm/dusklight) |
| ~~OoTMM Randomizer~~ | OoT + MM combo | OoTMM | Temporarily disabled (SteamOS webkit2gtk regression — see [Issue Notes](#ootmm-known-issue)) |

## Features

### Game Management
- **One-click download & update** — fetches the latest AppImage release directly from GitHub
- **Smart install detection** — scans common locations (`~/Applications`, `~/Downloads`, `~/Games`, custom paths) for existing installs
- **Install location migration** — change your base directory; existing installs are detected and moved with a single confirmation and summary
- **Uninstall** — removes the AppImage while preserving your ROMs, saves, mods, and configuration
- **Inline changelogs** — view release notes without leaving the menu

### Mod Manager
- **Download mods** with file size shown in the confirmation prompt
- **Large file warnings** — mods over 50MB show a patience warning with exact size
- **Enable/Disable toggle** — rename `.disabled` suffix without re-downloading
- **Conflict detection** — warns when installing conflicting mods (e.g., 3DS + Reloaded)
- **Remove all mods** — one-click cleanup
- **Browse for more** — links to GameBanana mod pages

### Steam Shortcuts
- **Add non-Steam shortcuts** — writes directly to `shortcuts.vdf` with automatic backup
- **Steam running detection** — warns if Steam is open (it can overwrite changes on exit)
- **Display names** — uses proper game names (e.g., "Ship of Harkinian (OoT)") not internal keys
- **Status indicators** — shows "Installed" / "Not installed" for each game

### ROM Dumping Guide
- Built-in guide for dumping N64 ROMs via Wii/GameCube
- Supports `.z64`, `.n64`, and `.v64` formats

## Quick Start

### Steam Deck (Desktop Mode)
1. Download [`decomp-depot.desktop`](https://raw.githubusercontent.com/thefriendlyhedgehog/decomp-depot/main/decomp-depot.desktop) (right-click → Save Link As...)
2. Place it in `~/Desktop/` or `~/.local/share/applications/`
3. Double-click to launch

### Any Linux distro
```bash
curl -L https://raw.githubusercontent.com/thefriendlyhedgehog/decomp-depot/main/decomp-depot.sh | sh
```

Or clone and run:
```bash
git clone https://github.com/thefriendlyhedgehog/decomp-depot.git
cd decomp-depot
bash decomp-depot.sh
```

### Dependencies

| Package | Required? | Purpose |
|---------|-----------|---------|
| `zenity` | ✅ Required | All dialog menus (pre-installed on Steam Deck) |
| `unzip` | ✅ Required | Extract game downloads (pre-installed on Steam Deck) |
| `curl` | ✅ Required | Download games and mods |
| `python3` | Optional | Steam shortcut management (pre-installed on Steam Deck) |
| `7za` (p7zip) | Optional | Extract `.7z` mod archives |

## Install Locations

By default, games install to `~/Applications/`. You can change this from the main menu → **Install Location**. Each game gets its own subfolder:

| Port | Folder | AppImage |
|------|--------|----------|
| Ship of Harkinian | `ship-of-harkinian/` | `soh.appimage` |
| 2 Ship 2 Harkinian | `2ship2harkinian/` | `2ship.appimage` |
| Ghostship | `ghostship/` | `ghostship.appimage` |
| Starship | `starship/` | `starship.appimage` |
| Dusklight | `dusklight/` | `dusklight.appimage` |
| OoTMM | `ootmm/` | `ootmm-linux_x64` (disabled) |

When you change the install location, the script:
1. Checks both the new and old locations for existing installs
2. Shows what's found in each location
3. Migrates everything with a single confirmation
4. Shows a summary of what was moved and what was skipped
5. Tracks the previous location so it can find games that weren't moved

## Mods

Mods are installed into a `mods/` subfolder within each game's directory. Available mods:

| Game | Mod | Type | Source |
|------|-----|------|--------|
| SoH | Steam Deck Intro | .zip | GameBanana |
| SoH | Steam Deck UI | .zip | GameBanana |
| SoH | 3DS Textures | .zip | GameBanana |
| SoH | OoT Reloaded (HD) | .7z | evilgames.eu |
| 2S2H | MM Reloaded (HD) | .7z | evilgames.eu |
| Ghostship | SM64 Reloaded (HD) | .7z | GitHub |

**Note:** 3DS Textures and OoT Reloaded conflict — the script warns you before installing both.

## ROMs

This script assumes you have **legally-dumped** ROMs. Follow the instructions on [Wii.Guide](https://wii.guide/dump-games.html) for dumping your discs with a softmodded Wii. You can verify a ROM is supported with:

- OoT (SoH): <https://ship.equipment/>
- MM (2S2H): <https://2ship.equipment/>
- SM64 (Ghostship): US 1.0 ROM
- SF64 (Starship): US 1.0 ROM
- TP (Dusklight): GameCube USA or EUR `.iso` / `.rvz` dump

## OoTMM Known Issue

The OoTMM Randomizer is temporarily disabled due to a **SteamOS webkit2gtk regression** introduced in the July 4, 2026 SteamOS update. The generation worker (WebAssembly) hangs silently when clicking "Generate".

- **Affected versions:** OoTMM v31.0 and v31.1
- **Platform:** Steam Deck (SteamOS, Desktop Mode)
- **Root cause:** webkit2gtk Web Worker / WebAssembly incompatibility after SteamOS update
- **Workaround:** Generate seeds on another machine, or wait for OoTMM/SteamOS to fix the regression

The OoTMM code remains in the script and can be re-enabled by uncommenting two lines in the main dispatch section. A diagnostic script (`ootmm-test.sh`) is included for testing when the issue is resolved.

## Files

| File | Purpose |
|------|---------|
| `decomp-depot.sh` | Main script — the launcher, installer, mod manager |
| `decomp-depot.desktop` | Desktop shortcut file for Steam Deck |
| `qa-check.sh` | QA validation tool — checks syntax, config, URLs, dead code, and prints a manual test checklist |
| `ootmm-test.sh` | OoTMM diagnostic script — tests webkit fixes and resource extraction |
| `CLAUDE.md` | Project instructions for Claude Code / AI assistants |
| `HANDOFF.md` | Development handoff document with current state and notes |

## Development

### Running the QA checker
```bash
bash qa-check.sh
```
Validates: syntax, config consistency, dead code, removed features, menu structure, network URLs, mod sizes, and common issues. Prints a manual test checklist at the end.

### Adding a new game
1. Add config entries to the array section at the top of `decomp-depot.sh`:
   ```bash
   GAME_NAME[newgame]="Display Name (Game)"
   GAME_REPO[newgame]="Org/Repo"
   GAME_ASSET_PREFIX[newgame]="Prefix"  # or "" for direct AppImage
   GAME_APPIMAGE[newgame]="name.appimage"
   GAME_DIR[newgame]="folder-name"
   GAME_OTR[newgame]=""  # or "asset.o2r" if the game uses extracted assets
   GAME_CHANGELOG[newgame]="https://github.com/Org/Repo/releases"
   ```
2. Add to main menu and dispatch section
3. Add to all game enumeration loops (search for `soh 2s2h ghostship starship dusklight`)
4. Run `bash qa-check.sh` to verify

### Adding a new mod
```bash
MODS_AVAILABLE[gamekey]="ExistingMods NewMod"
MOD_URL[NewMod]="https://download-url"
MOD_FILE[NewMod]="filename.7z"
```
The data-driven `download_mod` function handles the rest automatically.

## Future Ports

Planned for addition when public releases are available:
- **Harvest Moon** (HarbourMasters)
- **Wind Waker** (Wind Waker team / HarbourMasters)

## Credits

Inspired by the original Ship of Harkinian updater. Fully rewritten as Decomp Depot to support multiple decompilation ports under a unified launcher.

- Game ports by [HarbourMasters](https://github.com/HarbourMasters) and [TwilitRealm](https://github.com/TwilitRealm)
- Texture packs by [GhostlyDark](https://github.com/GhostlyDark) and [evilgames.eu](https://evilgames.eu)
- Steam Deck mods from [GameBanana](https://gamebanana.com)
