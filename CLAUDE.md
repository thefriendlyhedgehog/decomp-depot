# decomp-depot — Claude Code Instructions

## Project
Bash-based launcher/updater for Zelda decomp projects (Ship of Harkinian, 2 Ship 2 Harkinian, Ghostship, Starship, OoTMM Randomizer) on Steam Deck and Linux.

## Working Style
- Match existing bash patterns in `decomp-depot.sh`; don't reformat unrelated code.
- Scope edits to the request — don't revert unrelated diffs.
- `rg` first; read code before editing.
- Verify shell syntax (`bash -n`) after edits.
- End with: what changed, what was verified, any blocker.

## Command Safety
- No destructive ops (`rm -rf`, `git reset --hard`, forced reverts) unless explicitly asked.
- Never commit/push/PR unless explicitly asked.
- Read-only first for audits.

## Tech Stack
- `decomp-depot.sh` (~2,048 lines) — main script, uses `whiptail` for TUI
- `decomp-depot.desktop` — Linux desktop entry
- Games download from GitHub releases APIs
- OoTMM uses Java GUI + Python headless generation
- Mod files: `.otr` (assets), `.o2r` (Reloaded mods)

## Key Functions
- `main_menu()` — top-level game selection
- `game_menu_loop()` — per-game menu (Download/Update/Play/Mods/etc.)
- `mod_menu()` / `mod_is_installed()` — dynamic mod detection and management
- `ootmm_*` functions — OoTMM randomizer workflow
- `steam_shortcuts_loop()` — Steam shortcut creation
