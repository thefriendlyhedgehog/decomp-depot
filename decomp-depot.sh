#!/bin/bash

clear

# Suppress the harmless "Fontconfig warning: ... without calling FcInit()" spam
# that floods the terminal on Steam Deck (emitted by zenity/AppImage subprocesses).
exec 2> >(grep -v "Fontconfig warning" >&2)

echo -e "Decomp Depot - N64 Decomp Port Manager\n"
sleep 1

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
# zenity is required for every menu/dialog, so check it first (with a plain
# terminal message, since we can't show a GUI dialog without it).
if ! command -v zenity > /dev/null 2>&1; then
	echo "ERROR: 'zenity' is required but was not found."
	echo "On Steam Deck, install it with:  sudo pacman -S zenity"
	exit 1
fi

# unzip is required to extract the game release archives.
if ! command -v unzip > /dev/null 2>&1; then
	zenity --error --title "Missing Dependency" \
		--text "'unzip' is required but was not found.\nOn Steam Deck, run:\n  sudo pacman -S unzip" --width 450
	exit 1
fi

# Detect a Python interpreter (only used for the Steam-shortcut feature).
# SteamOS ships python3 but may not alias it as 'python'.
if   command -v python  > /dev/null 2>&1; then PYTHON=python
elif command -v python3 > /dev/null 2>&1; then PYTHON=python3
else                                                PYTHON=""
fi

# Check if GitHub is reachable
if ! curl -Is https://github.com | head -1 | grep 200 > /dev/null
then
	zenity --error --title "Connection Error" --text "GitHub appears to be unreachable, you may not be connected to the Internet." --width 400
	exit 1
fi

title="Decomp Depot"

# ---------------------------------------------------------------------------
# Game definitions
# Each port is keyed by an identifier; the arrays below hold per-game config.
# ---------------------------------------------------------------------------
declare -A GAME_NAME GAME_REPO GAME_ASSET_PREFIX GAME_APPIMAGE GAME_DIR GAME_OTR GAME_CHANGELOG

# Ship of Harkinian - Ocarina of Time
GAME_NAME[soh]="Ship of Harkinian (OoT)"
GAME_REPO[soh]="HarbourMasters/Shipwright"
GAME_ASSET_PREFIX[soh]="SoH"
GAME_APPIMAGE[soh]="soh.appimage"
GAME_DIR[soh]="ship-of-harkinian"
GAME_OTR[soh]="oot.otr oot.o2r oot-mq.o2r"
GAME_CHANGELOG[soh]="https://www.shipofharkinian.com/changelog"

# 2 Ship 2 Harkinian - Majora's Mask
GAME_NAME[2s2h]="2 Ship 2 Harkinian (MM)"
GAME_REPO[2s2h]="HarbourMasters/2ship2harkinian"
GAME_ASSET_PREFIX[2s2h]="2Ship"
GAME_APPIMAGE[2s2h]="2ship.appimage"
GAME_DIR[2s2h]="2ship2harkinian"
GAME_OTR[2s2h]="2ship.o2r"
GAME_CHANGELOG[2s2h]="https://github.com/HarbourMasters/2Ship2Harkinian/releases"

# Ghostship - Super Mario 64
GAME_NAME[ghostship]="Ghostship (SM64)"
GAME_REPO[ghostship]="HarbourMasters/Ghostship"
GAME_ASSET_PREFIX[ghostship]=""  # prefix changes between releases (Mary-Celeste, Ghostship-Dutchman, etc.)
GAME_APPIMAGE[ghostship]="ghostship.appimage"
GAME_DIR[ghostship]="ghostship"
GAME_OTR[ghostship]="sm64.o2r"
GAME_CHANGELOG[ghostship]="https://github.com/HarbourMasters/Ghostship/releases"

# Starship - Star Fox 64
GAME_NAME[starship]="Starship (SF64)"
GAME_REPO[starship]="HarbourMasters/Starship"
GAME_ASSET_PREFIX[starship]=""  # prefix changes between releases (Barnard-Alfa, etc.)
GAME_APPIMAGE[starship]="starship.appimage"
GAME_DIR[starship]="starship"
GAME_OTR[starship]="sf64.o2r"
GAME_CHANGELOG[starship]="https://github.com/HarbourMasters/Starship/releases"

# Dusklight - Twilight Princess (GameCube decomp port)
GAME_NAME[dusklight]="Dusklight (TP)"
GAME_REPO[dusklight]="TwilitRealm/dusklight"
GAME_ASSET_PREFIX[dusklight]=""  # Direct AppImage, no ZIP wrapper
GAME_APPIMAGE[dusklight]="dusklight.appimage"
GAME_DIR[dusklight]="dusklight"
GAME_OTR[dusklight]=""  # Uses raw .rvz/.iso, no extracted assets
GAME_CHANGELOG[dusklight]="https://github.com/TwilitRealm/dusklight/releases"

# ---------------------------------------------------------------------------
# Mod definitions (per-game)
# Each game lists the mods available to it. Detection, menus, and downloads
# all reference these tables so adding a mod is just adding data here.
# ---------------------------------------------------------------------------
declare -A MODS_AVAILABLE
MODS_AVAILABLE[soh]="OS SteamDeckUI 3DS Reloaded"
MODS_AVAILABLE[2s2h]="MMReloaded"
MODS_AVAILABLE[ghostship]="SM64Reloaded"
MODS_AVAILABLE[starship]=""

declare -A MOD_DISPLAY_NAME=(
	[OS]="Steam Deck Intro"
	[SteamDeckUI]="Steam Deck UI"
	[3DS]="3DS Textures"
	[Reloaded]="OoT Reloaded"
	[MMReloaded]="MM Reloaded"
	[SM64Reloaded]="SM64 Reloaded"
)

declare -A MOD_DESC=(
	[OS]="Steam Deck icon for splash screen"
	[SteamDeckUI]="Steam Deck UI overlay"
	[3DS]="3DS textures (conflicts with Reloaded)"
	[Reloaded]="OoT Reloaded hi-res textures (conflicts with 3DS)"
	[MMReloaded]="Majora's Mask Reloaded hi-res textures"
	[SM64Reloaded]="SM64 Reloaded hi-res textures for Ghostship"
)

# Conflict pairs: mod -> space-separated mods it conflicts with
declare -A MOD_CONFLICTS=(
	[3DS]="Reloaded"
	[Reloaded]="3DS"
)

# "Other mods" browse URL per game
declare -A MOD_BROWSE_URL=(
	[soh]="https://gamebanana.com/mods/games/16121?"
	[2s2h]="https://evilgames.eu/texture-packs/"
	[ghostship]="https://github.com/GhostlyDark/SM64-Reloaded/releases"
	[starship]="https://gamebanana.com/mods/games/6481?"
)

# Download URLs and filenames for each mod.
declare -A MOD_URL MOD_FILE
MOD_URL[OS]="https://gamebanana.com/dl/978007"
MOD_FILE[OS]="steamdeckintro.zip"
MOD_URL[SteamDeckUI]="https://gamebanana.com/dl/1028208"
MOD_FILE[SteamDeckUI]="steamdeckui.zip"
MOD_URL[3DS]="https://gamebanana.com/dl/1095310"
MOD_FILE[3DS]="3ds.zip"
MOD_URL[Reloaded]="https://evilgames.eu/files/texture-packs/oot-reloaded-v11.0.0-soh-o2r-hd.7z"
MOD_FILE[Reloaded]="reloaded.7z"
MOD_URL[MMReloaded]="https://evilgames.eu/files/texture-packs/mm-reloaded-v11.0.2-2ship-o2r-hd.7z"
MOD_FILE[MMReloaded]="mm-reloaded.7z"
MOD_URL[SM64Reloaded]="https://github.com/GhostlyDark/SM64-Reloaded/releases/download/v2.6.0/sm64-reloaded-v2.6.0-gs-o2r-hd.7z"
MOD_FILE[SM64Reloaded]="sm64-reloaded.7z"

# ---------------------------------------------------------------------------
# Install-location persistence
# Remembered in a config file so a manually-set location survives restarts.
# ---------------------------------------------------------------------------
CONFIG_FILE="$HOME/.config/decomp-depot.conf"

# ---------------------------------------------------------------------------
# Install-location system
# A single global base directory is used. Each game installs into a
# subdirectory named after its GAME_DIR entry (e.g. ship-of-harkinian).
# Per-game overrides are still supported for the manual-locate fallback.
# ---------------------------------------------------------------------------

# Read the global base directory. Defaults to ~/Applications.
get_base_dir() {
	local path
	path=$(grep "^base_dir=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
	if [ -n "$path" ] && [ -d "$path" ]; then
		echo "$path"
		return 0
	fi
	echo "$HOME/Applications"
	return 1
}

# Save the global base directory.
set_base_dir() {
	local dir=$1
	mkdir -p "$(dirname "$CONFIG_FILE")"
	touch "$CONFIG_FILE"
	# Remember the old base_dir before overwriting (for migration detection).
	local old_base
	old_base=$(grep "^base_dir=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
	# Remove existing base_dir and prev_base_dir, then add the new ones.
	grep -v "^base_dir=\|^prev_base_dir=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null
	echo "base_dir=$dir" >> "$CONFIG_FILE.tmp"
	[ -n "$old_base" ] && [ "$old_base" != "$dir" ] && echo "prev_base_dir=$old_base" >> "$CONFIG_FILE.tmp"
	mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

# Read the previous base directory (before the last change). Used by
# find_game_dir to detect installs at the old location during migration.
get_prev_base_dir() {
	grep "^prev_base_dir=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2-
}

# Read a per-game saved location (from manual-locate fallback).
# Echoes the path (return 0) if saved AND exists, otherwise returns 1.
get_saved_location() {
	local game_key=$1
	local path
	path=$(grep "^$game_key=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
	if [ -n "$path" ] && [ -d "$path" ]; then
		echo "$path"
		return 0
	fi
	return 1
}

# Save a per-game override location.
save_location() {
	local game_key=$1
	local dir=$2
	mkdir -p "$(dirname "$CONFIG_FILE")"
	touch "$CONFIG_FILE"
	grep -v "^$game_key=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null
	echo "$game_key=$dir" >> "$CONFIG_FILE.tmp"
	mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# get SteamID - for adding games as non-Steam shortcuts
# ---------------------------------------------------------------------------
if [ "$USER" != "deck" ]; then
	STEAMID=$(find ~/.steam/debian-installation/userdata/ -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed -n '2p')
else
	STEAMID=$(find ~/.local/share/Steam/userdata/ -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed -n '1p')
fi
STEAMID=$(basename "$STEAMID")

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------
message() {
	zenity --info --title "$title" --text "$1" --width 400 --height 75
}

question() {
	zenity --question --title "$title" --text "$1" --width 400 --height 75
}

progress_bar() {
	zenity --title "$title" --text "$1" --progress --pulsate --auto-close --auto-kill --width=300 --height=100

	if [ "$?" != 0 ]; then
		echo -e "\nUser canceled.\n"
	fi
}

# Convert a byte count to a human-readable string (KB/MB/GB).
format_size() {
	local bytes=$1
	if [ -z "$bytes" ] || [ "$bytes" -le 0 ]; then
		echo ""
	elif [ "$bytes" -ge 1073741824 ]; then
		awk "BEGIN {printf \"%.1fGB\", $bytes/1073741824}"
	elif [ "$bytes" -ge 1048576 ]; then
		awk "BEGIN {printf \"%.1fMB\", $bytes/1048576}"
	elif [ "$bytes" -ge 1024 ]; then
		awk "BEGIN {printf \"%dKB\", $bytes/1024}"
	else
		echo "${bytes}B"
	fi
}

# Fetch file size of a URL via HTTP HEAD. Echoes byte count (or empty).
get_url_size() {
	local url=$1
	local size
	# Follow redirects (-L), headers only (-I), grab last content-length.
	size=$(curl -sIL "$url" 2>/dev/null \
		| grep -i "content-length" | tail -1 | tr -d '\r' | awk '{print $2}')
	[ -n "$size" ] && [ "$size" -gt 0 ] && echo "$size"
}

# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------
github_latest_tag() {
	curl -s "https://api.github.com/repos/$1/releases/latest" \
		| grep '"tag_name"' | head -1 | cut -d '"' -f 4
}

github_latest_asset_url() {
	curl -s "https://api.github.com/repos/$1/releases/latest" \
		| grep "browser_download_url" | grep "$2" | cut -d '"' -f 4
}

# Extract a .z64 ROM from a ZIP archive to a temp directory.
# Echoes the temp dir path on success (empty on failure).
# Caller is responsible for cleaning up the temp dir.
extract_z64_from_zip() {
	local tmp
	tmp=$(mktemp -d)
	unzip -o "$1" '*.z64' -d "$tmp" >/dev/null 2>&1
	if ! ls "$tmp"/*.z64 1>/dev/null 2>&1; then
		rm -rf "$tmp"
		echo ""
		return 1
	fi
	echo "$tmp"
}

# Move or merge a directory into a target location.
# Shows progress bar, cleans up stale zips. Silent (no message dialog).
# Args: display_name source_dir target_dir
# Returns 0 on success (moved/merged), 1 on user decline.
migrate_dir() {
	local name=$1 src=$2 target=$3

	# If the target exists and is non-empty, merge instead.
	if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
		if ! question "$name found at:\n$src\n\nThe destination already has files:\n$target\n\nMerge (copy over, keeping existing)?"; then
			return 1
		fi
		(
		echo -e "Merging $name...\n"
		cp -rn "$src"/* "$target"/ 2>/dev/null
		) | progress_bar "Merging $name..."
	else
		if ! question "$name found at:\n$src\n\nMove it to:\n$target?"; then
			return 1
		fi
		(
		echo -e "Moving $name...\n"
		# Never rm -rf a folder that might have user data.
		rmdir "$target" 2>/dev/null || true
		mv "$src" "$target"
		) | progress_bar "Moving $name..."
	fi

	# Clean up stale download zips.
	local z
	for z in "$target"/*.zip; do
		[ -f "$z" ] && rm -f "$z"
	done
	return 0
}

# ---------------------------------------------------------------------------
# Install detection
# ---------------------------------------------------------------------------

# Search common locations for an existing AppImage install.
# Checks the saved config location first, then scans common folders.
# Echoes the directory if found (return 0), otherwise returns 1.
find_game_dir() {
	local game_key=$1
	local appimage="${GAME_APPIMAGE[$game_key]}"
	local base prev_base d

	base=$(get_base_dir)
	prev_base=$(get_prev_base_dir)

	# 1. Per-game saved override (from manual locate).
	d=$(get_saved_location "$game_key")
	[ -n "$d" ] && [ -f "$d/$appimage" ] && { echo "$d"; return 0; }

	# 2. Base directory + game subfolder.
	[ -f "$base/${GAME_DIR[$game_key]}/$appimage" ] && { echo "$base/${GAME_DIR[$game_key]}"; return 0; }

	# 3. Previous base directory + game subfolder (after install location change).
	if [ -n "$prev_base" ]; then
		[ -f "$prev_base/${GAME_DIR[$game_key]}/$appimage" ] && { echo "$prev_base/${GAME_DIR[$game_key]}"; return 0; }
	fi

	# 4. Auto-detect — globs expand for subdirectory search.
	for d in \
		"$HOME/Applications/${GAME_DIR[$game_key]}" \
		"$base" \
		"$base"/* \
		"$prev_base" \
		"$prev_base"/* \
		"$HOME/Downloads" \
		"$HOME/Downloads"/* \
		"$HOME/Games" \
		"$HOME/Games"/* ; do
		[ -n "$d" ] && [ -f "$d/$appimage" ] && { echo "$d"; return 0; }
	done
	return 1
}

# Resolve the directory for a game install: auto-detect an existing AppImage,
# and if none is found, offer to locate it manually via a file picker.
# On success, echoes the directory path and returns 0.
# On failure (not found / user cancelled), returns 1.
get_game_dir() {
	local game_key=$1
	local appimage="${GAME_APPIMAGE[$game_key]}"
	local gname="${GAME_NAME[$game_key]}"
	local dir picked

	dir=$(find_game_dir "$game_key")
	if [ $? -eq 0 ]; then
		echo "$dir"
		return 0
	fi

	# Not auto-detected — offer manual locate.
	if question "$gname was not found in the usual locations.\nWould you like to browse for the $appimage?"; then
		picked=$(zenity --file-selection --file-filter='AppImage | *.appimage' --title="Locate the $gname AppImage")
		if [ $? -eq 0 ] && [ -f "$picked" ]; then
			dir=$(dirname "$picked")
			save_location "$game_key" "$dir"
			echo "$dir"
			return 0
		fi
	fi
	return 1
}

# The authoritative install target: saved location, then detected, then the
# canonical default. Always echoes a path (never fails). Used by download_game.
resolve_install_dir() {
	local game_key=$1
	local base dir

	base=$(get_base_dir)

	# 1. Per-game saved override (from manual locate).
	dir=$(get_saved_location "$game_key") && { echo "$dir"; return; }

	# 2. Auto-detected existing install.
	dir=$(find_game_dir "$game_key") && { echo "$dir"; return; }

	# 3. Base directory + game subfolder (fresh download).
	echo "$base/${GAME_DIR[$game_key]}"
}

# Open the game's install folder in the system file manager.
open_game_folder() {
	local game_key=$1
	local gname="${GAME_NAME[$game_key]}"
	local base dir

	base=$(get_base_dir)
	dir=$(get_saved_location "$game_key")
	[ -z "$dir" ] && dir=$(find_game_dir "$game_key")
	[ -z "$dir" ] && dir="$base/${GAME_DIR[$game_key]}"

	if [ -d "$dir" ]; then
		xdg-open "$dir"
	else
		message "The folder does not exist yet:\n$dir\n\nDownload $gname first."
	fi
}

# Find a game that's installed somewhere OTHER than its target location
# under the current base_dir. Uses the same find_game_dir detection that
# Download relies on, so it can never miss a game those features find.
# Also checks the PREVIOUS base_dir (saved in config) so games are found
# when switching install locations.
find_migrate_source() {
	local game_key=$1
	local base target found_dir

	base=$(get_base_dir)
	target="$base/${GAME_DIR[$game_key]}"

	# Use the proven detection function.
	found_dir=$(find_game_dir "$game_key") || return 1

	# Already at the target location — no migration needed.
	[ "$found_dir" == "$target" ] && return 1

	echo "$found_dir"
	return 0
}

# Find an OoTMM install outside the current base_dir.
# OoTMM has no AppImage so find_game_dir can't detect it.
find_ootmm_migrate_source() {
	local base target prev
	base=$(get_base_dir)
	prev=$(get_prev_base_dir)
	target="$base/ootmm"

	# Search as broadly as find_game_dir — current/prev base dirs
	# and common install locations with glob expansion.
	local d
	for d in \
		"$prev/ootmm" \
		"$base/ootmm" \
		"$prev" \
		"$prev"/* \
		"$base" \
		"$base"/* \
		"$HOME/Applications" \
		"$HOME/Applications"/* \
		"$HOME/Downloads" \
		"$HOME/Downloads"/* \
		"$HOME/Games" \
		"$HOME/Games"/* ; do
		[ -z "$d" ] && continue
		[ "$d" == "$target" ] && continue
		if [ -f "$d/ootmm-linux_x64" ]; then
			echo "$d"
			return 0
		fi
	done
	return 1
}

# Move a game install to its proper location under the base dir.
migrate_game() {
	local game_key=$1
	local gname="${GAME_NAME[$game_key]}"
	local dir target

	dir=$(find_migrate_source "$game_key")
	[ -z "$dir" ] && return 1

	target="$(get_base_dir)/${GAME_DIR[$game_key]}"
	migrate_dir "$gname" "$dir" "$target"
}

# Move an OoTMM install to its proper location under the base dir.
migrate_ootmm() {
	local old_dir=$1
	local target
	target="$(get_base_dir)/ootmm"

	[ ! -d "$old_dir" ] && return 1
	migrate_dir "OoTMM" "$old_dir" "$target"
}

set_install_location() {
	local base picked

	base=$(get_base_dir)

	picked=$(zenity --file-selection --directory \
		--title="Select your games install folder\n(currently: $base)")
	if [ $? -ne 0 ] || [ ! -d "$picked" ]; then
		return
	fi

	set_base_dir "$picked"
	base="$picked"

	# Check for games already at the new location.
	local found_here=""
	for gk in soh 2s2h ghostship starship dusklight; do
		if [ -f "$base/${GAME_DIR[$gk]}/${GAME_APPIMAGE[$gk]}" ]; then
			found_here="${found_here}${GAME_NAME[$gk]}, "
		fi
	done
	if [ -f "$base/ootmm/ootmm-linux_x64" ]; then
		found_here="${found_here}OoTMM, "
	fi

	# Check for installs still at the old location that can be migrated.
	local migrate_list=""
	local gk
	for gk in soh 2s2h ghostship starship dusklight; do
		local old_dir
		old_dir=$(find_migrate_source "$gk")
		if [ -n "$old_dir" ]; then
			migrate_list="${migrate_list}${GAME_NAME[$gk]}: $old_dir\n"
		fi
	done
	local ootmm_old
	ootmm_old=$(find_ootmm_migrate_source)
	if [ -n "$ootmm_old" ]; then
		migrate_list="${migrate_list}OoTMM: $ootmm_old\n"
	fi

	# Nothing to migrate — just report what's here (or nothing).
	if [ -z "$migrate_list" ]; then
		if [ -n "$found_here" ]; then
			message "Install location set to:\n$base\n\nGames found here: ${found_here%, }"
		else
			message "Install location set to:\n$base\n\nNo existing installs found.\nNew downloads will create subfolders here."
		fi
		return
	fi

	# Build the prompt based on whether new location also has installs.
	local prompt="Install location set to:\n$base\n\n"
	[ -n "$found_here" ] && prompt="${prompt}Already found here: ${found_here%, }\n\n"
	prompt="${prompt}The following installs were found elsewhere:\n\n${migrate_list}\nWould you like to move them here?"

	if ! question "$prompt"; then
		message "Install location set to:\n$base\n\nYou can move remaining installs later by selecting this option again."
		return
	fi

	# Migrate all items, collecting results for a single summary.
	local moved="" skipped=""
	for gk in soh 2s2h ghostship starship dusklight; do
		local gname="${GAME_NAME[$gk]}"
		if migrate_game "$gk" 2>/dev/null; then
			moved="${moved}• $gname moved\n"
		else
			# Check if there was actually something to migrate.
			local src
			src=$(find_migrate_source "$gk")
			[ -n "$src" ] && skipped="${skipped}• $gname skipped\n"
		fi
	done
	if [ -n "$ootmm_old" ]; then
		if migrate_ootmm "$ootmm_old" 2>/dev/null; then
			moved="${moved}• OoTMM moved\n"
		else
			skipped="${skipped}• OoTMM skipped\n"
		fi
	fi

	# Single summary popup.
	local summary="Migration complete!\n\n"
	[ -n "$moved" ] && summary="${summary}Moved:\n${moved}\n"
	[ -n "$skipped" ] && summary="${summary}Skipped:\n${skipped}"
	message "$summary"
}

# ---------------------------------------------------------------------------
# Game operations (work for any port defined above)
# ---------------------------------------------------------------------------

# Download or update a game's Linux AppImage release.
# Asset names include a codename that changes per release (e.g. "SoH-Ackbar-Delta-Linux.zip"),
# so we match on the project prefix + "Linux" rather than a fixed filename.
download_game() {
	game_key=$1
	repo="${GAME_REPO[$game_key]}"
	prefix="${GAME_ASSET_PREFIX[$game_key]}"
	appimage="${GAME_APPIMAGE[$game_key]}"
	gname="${GAME_NAME[$game_key]}"

	# Use the saved/explicitly-set location if any, otherwise detect an existing
	# install, otherwise the canonical default for a fresh download.
	dir=$(resolve_install_dir "$game_key")

	# Fetch the latest release info once (used for both the version label and
	# the download URL).
	api_json=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
	current_tag=$(github_latest_tag "$repo")
	# Resolve the download URL. HarbourMasters games ship as ZIP files with
	# a prefix (SoH, 2Ship). Dusklight ships as a direct AppImage.
	if [ -n "$prefix" ]; then
		url=$(echo "$api_json" | grep "browser_download_url" | grep "$prefix" | grep "Linux" | cut -d '"' -f 4)
	else
		# Direct AppImage download — filter for linux-x86_64 AppImage.
		url=$(echo "$api_json" | grep "browser_download_url" | grep "linux-x86_64.AppImage" | cut -d '"' -f 4)
	fi

	if [ -z "$url" ]; then
		message "Could not find a Linux release for $gname.\nPlease check your connection and try again."
		return
	fi

	# If an existing AppImage is found here, warn before overwriting.
	if [ -f "$dir/$appimage" ]; then
		if [ -n "$current_tag" ]; then
			confirm_text="An existing $gname was found:\n$dir\n\nThis will be overwritten/updated to version $current_tag.\nYour save data and settings will be preserved.\n\nContinue?"
		else
			confirm_text="An existing $gname was found:\n$dir\n\nThis will be overwritten/updated.\nYour save data and settings will be preserved.\n\nContinue?"
		fi
		if ! question "$confirm_text"; then
			echo -e "User selected No.\n"
			return
		fi
	fi

	mkdir -p "$dir"
	cd "$dir" || return

	(
	echo -e "Downloading $gname...\n"
	if [[ "$url" == *.AppImage ]]; then
		# Direct AppImage download (Dusklight).
		curl -L "$url" -o "$appimage"
		chmod +x "$appimage"
	else
		# ZIP download (HarbourMasters games).
		curl -L "$url" -o game.zip
		echo -e "Extracting...\n"
		unzip -o game.zip
		rm -f game.zip
		chmod +x "$appimage"
	fi
	) | progress_bar "Downloading/updating $gname, please wait..."

	# After a successful download, offer to add a Steam shortcut.
	if [ -f "$dir/$appimage" ]; then
		if question "$gname download/update complete!\n\nWould you like to add it as a non-Steam shortcut?"; then
			add_steam_shortcut "$game_key"
		else
			message "$gname download/update complete!"
		fi
	else
		message "$gname download may have failed.\nThe AppImage was not found in the install directory."
	fi
}

# View the changelog / releases page for a game.
changelog_game() {
	game_key=$1
	local repo="${GAME_REPO[$game_key]}"
	local gname="${GAME_NAME[$game_key]}"

	# Fetch the last few releases from the GitHub API and display inline.
	local releases_json
	releases_json=$(curl -s "https://api.github.com/repos/$repo/releases?per_page=5" 2>/dev/null)

	if [ -z "$releases_json" ] || echo "$releases_json" | grep -q '"message": "Not Found"'; then
		message "Could not fetch release notes for $gname.\nCheck your connection and try again."
		return
	fi

	# Build a readable text summary from the JSON.
	local output
	output=$(echo "$releases_json" | "$PYTHON" -c "
import sys, json, re

releases = json.load(sys.stdin)
lines = []
for r in releases[:5]:
    tag = r.get('tag_name', 'unknown')
    name = r.get('name', '')
    date = r.get('published_at', '')[:10]
    body = r.get('body', '') or ''

    # Strip HTML tags (download buttons, images, etc.)
    body = re.sub(r'<[^>]+>', '', body)
    # Strip markdown image syntax
    body = re.sub(r'!\[.*?\]\(.*?\)', '', body)
    # Strip markdown links, keep text
    body = re.sub(r'\[([^\]]*)\]\(.*?\)', r'\1', body)
    # Remove '# Download' header section (just download buttons in text form)
    body = re.sub(r'^#\s*Download\s*$', '', body, flags=re.MULTILINE)
    # Remove lines that are just whitespace
    body = '\n'.join(line for line in body.split('\n') if line.strip())
    # Collapse whitespace
    body = re.sub(r'\n{3,}', '\n\n', body).strip()

    lines.append(f'═══════════════════════════════════════')
    lines.append(f'  {name}  (v{tag})')
    lines.append(f'  Released: {date}')
    lines.append(f'═══════════════════════════════════════')
    lines.append('')
    if body and len(body) > 20:
        lines.append(body[:2000])
    else:
        lines.append('(No detailed release notes for this version.)')
    lines.append('')

print('\n'.join(lines))
" 2>/dev/null)

	if [ -z "$output" ]; then
		message "Could not parse release notes for $gname."
		return
	fi

	# Display in a scrollable text dialog.
	echo "$output" | zenity --width 700 --height 600 --text-info \
		--title "$title - $gname Changelog" \
		--font="Monospace 11" --ok-label="Close" --cancel-label="Close" 2>/dev/null
}

# Add or update a game as a non-Steam shortcut.
# If a shortcut with the same name already exists, its path is updated to the
# current install location. Otherwise a new shortcut is created.
add_steam_shortcut() {
	game_key=$1
	appimage="${GAME_APPIMAGE[$game_key]}"
	gname="${GAME_NAME[$game_key]}"

	# Detect an existing install, or offer to locate it manually.
	dir=$(get_game_dir "$game_key") || return

	if [ -z "$STEAMID" ] || [ "$STEAMID" == "." ]; then
		message "Could not detect your Steam ID.\nMake sure Steam has been run at least once, then try again."
		return
	fi

	if [ -z "$PYTHON" ]; then
		message "Python is required to manage Steam shortcuts but was not found.\nOn Steam Deck, run:\n  sudo pacman -S python"
		return
	fi

	# Resolve the shortcuts.vdf path.
	if [ "$USER" != "deck" ]; then
		vdf="$HOME/.steam/debian-installation/userdata/$STEAMID/config/shortcuts.vdf"
	else
		vdf="$HOME/.local/share/Steam/userdata/$STEAMID/config/shortcuts.vdf"
	fi

	# Back up shortcuts.vdf before touching it (one-time safety backup).
	local backup="$vdf.decomp-depot-backup"
	if [ -f "$vdf" ] && [ ! -f "$backup" ]; then
		cp "$vdf" "$backup"
	fi

	# Check if Steam is running — it can overwrite our changes on exit.
	if pgrep -x steam > /dev/null 2>&1 || pgrep -x steamos-session > /dev/null 2>&1; then
		if ! question "Steam appears to be running.\nSteam may overwrite shortcut changes when it closes.\n\nFor best results, close Steam first.\n\nContinue anyway?"; then
			return
		fi
	fi

	# Self-contained VDF shortcut manager (no external downloads needed).
	# Parses the binary shortcuts.vdf, updates an existing entry by name, or
	# appends a new one if not found.
	cat > /tmp/steam_shortcut_mgr.py << 'PYEOF'
import struct, sys, os

def read_cstr(data, pos):
    end = data.index(b'\x00', pos)
    return data[pos:end].decode('utf-8', errors='surrogateescape'), end + 1

def parse_shortcuts(data):
    """Parse binary shortcuts.vdf into a list of dicts."""
    shortcuts = []
    if len(data) < 2:
        return shortcuts
    pos = 0
    # Header: \x00 "shortcuts" \x00
    if data[pos] == 0x00:
        pos += 1
        _, pos = read_cstr(data, pos)
    while pos < len(data) - 1:
        bt = data[pos]
        if bt == 0x00:  # new shortcut entry
            pos += 1
            _, pos = read_cstr(data, pos)  # index string
            sc = {}
            while pos < len(data):
                t = data[pos]; pos += 1
                if t == 0x08:  # end of this entry
                    break
                elif t == 0x01:  # string value
                    k, pos = read_cstr(data, pos)
                    v, pos = read_cstr(data, pos)
                    sc[k] = v
                elif t == 0x00:  # int32 value
                    k, pos = read_cstr(data, pos)
                    v = struct.unpack('<i', data[pos:pos+4])[0]; pos += 4
                    sc[k] = v
                elif t == 0x02:  # nested dict (tags)
                    k, pos = read_cstr(data, pos)
                    tags = []
                    while pos < len(data):
                        tt = data[pos]; pos += 1
                        if tt == 0x08:
                            break
                        elif tt == 0x01:
                            _, pos = read_cstr(data, pos)  # tag index
                            tv, pos = read_cstr(data, pos)
                            tags.append(tv)
                    sc[k] = tags
                else:
                    break
            shortcuts.append(sc)
        elif bt == 0x08:  # end of all shortcuts
            break
        else:
            pos += 1
    return shortcuts

def write_cstr(buf, s):
    buf.extend(str(s).encode('utf-8', errors='surrogateescape'))
    buf.append(0)

def write_shortcuts(shortcuts):
    buf = bytearray()
    buf.append(0x00)
    buf.extend(b'shortcuts')
    buf.append(0x00)
    for i, sc in enumerate(shortcuts):
        buf.append(0x00)
        write_cstr(buf, str(i))
        for k, v in sc.items():
            if isinstance(v, bool):
                buf.append(0x00)
                write_cstr(buf, k)
                buf.extend(struct.pack('<i', int(v)))
            elif isinstance(v, int):
                buf.append(0x00)
                write_cstr(buf, k)
                buf.extend(struct.pack('<i', v))
            elif isinstance(v, list):  # tags
                buf.append(0x02)
                write_cstr(buf, k)
                for ti, tv in enumerate(v):
                    buf.append(0x01)
                    write_cstr(buf, str(ti))
                    write_cstr(buf, tv)
                buf.append(0x08)
            else:  # string (or anything else → stringify)
                buf.append(0x01)
                write_cstr(buf, k)
                write_cstr(buf, v if isinstance(v, str) else str(v))
        buf.append(0x08)
    buf.append(0x08)
    return bytes(buf)

def main():
    vdf_path, app_name, exe_path, start_dir = sys.argv[1:5]

    try:
        shortcuts = []
        if os.path.exists(vdf_path):
            with open(vdf_path, 'rb') as f:
                shortcuts = parse_shortcuts(f.read())

        # Search for an existing shortcut by appName.
        found = False
        for sc in shortcuts:
            if sc.get('appName', '') == app_name:
                sc['exe'] = exe_path
                sc['StartDir'] = start_dir
                found = True
                break

        if not found:
            shortcuts.append({
                'appName': app_name,
                'exe': exe_path,
                'StartDir': start_dir,
                'icon': '',
                'ShortcutPath': '',
                'LaunchOptions': '',
                'IsHidden': 0,
                'AllowDesktopConfig': 1,
                'AllowOverlay': 1,
                'openvr': 0,
                'Devkit': 0,
                'DevkitGameID': '',
                'LastPlayTime': 0,
                'tags': []
            })

        vdf_dir = os.path.dirname(vdf_path)
        if vdf_dir:
            os.makedirs(vdf_dir, exist_ok=True)
        with open(vdf_path, 'wb') as f:
            f.write(write_shortcuts(shortcuts))

        print('UPDATED' if found else 'ADDED')
    except Exception as e:
        print(f'ERROR: {e}', file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
PYEOF

	(
	echo -e "Updating Steam shortcuts...\n"
	"$PYTHON" /tmp/steam_shortcut_mgr.py "$vdf" "$gname" "$dir/$appimage" "$dir" > /tmp/steam_result.txt 2>&1
	) | progress_bar "Updating Steam shortcut..."
	result=$(cat /tmp/steam_result.txt 2>/dev/null)
	rm -f /tmp/steam_shortcut_mgr.py /tmp/steam_result.txt

	if [ "$result" == "UPDATED" ]; then
		message "$gname shortcut was updated to:\n$dir/$appimage\n\nRestart Steam to see the changes."
	elif [ "$result" == "ADDED" ]; then
		message "$gname added as a non-Steam shortcut!\nRestart Steam to see the changes."
	else
		message "Something went wrong while managing the Steam shortcut:\n$result\n\nA backup of your original shortcuts.vdf was preserved."
	fi
}

# Uninstall a game (preserves ROM, save data, mods and configuration).
uninstall_game() {
	game_key=$1
	appimage="${GAME_APPIMAGE[$game_key]}"
	otr="${GAME_OTR[$game_key]}"
	gname="${GAME_NAME[$game_key]}"

	# Detect an existing install, or offer to locate it manually.
	dir=$(get_game_dir "$game_key") || return

	if ! question "Are you sure you want to uninstall $gname?\n(your save/configuration data will be preserved)"; then
		echo -e "User selected No.\n"
		return
	fi

	cd "$dir" || return
	(
	echo -e "Uninstalling $gname...\n"
	rm -rf logs
	rm -f imgui.ini readme.txt "$appimage"
	for f in $otr; do rm -f "$f"; done
	) | progress_bar "Uninstalling $gname..."
	message "$gname uninstalled.\nYour ROM, save data, mods, and configuration data have been preserved."
}

# ---------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------
main_menu() {
	zenity --width 700 --height 500 --list --radiolist --title "$title" \
	--column "Select" \
	--column "Option" \
	--column="Description" \
	FALSE "Ship of Harkinian"  "Ocarina of Time PC port" \
	FALSE "2 Ship 2 Harkinian" "Majora's Mask PC port" \
	FALSE "Ghostship"          "Super Mario 64 PC port" \
	FALSE "Starship"            "Star Fox 64 PC port" \
	FALSE "Dusklight"           "Twilight Princess PC port" \
	FALSE "Steam Shortcuts"     "Add or update non-Steam shortcuts" \
	FALSE "Install Location"    "Set where games are installed (currently: $(get_base_dir))" \
	FALSE Dumping              "ROM dumping guide" \
	TRUE Exit                  "Exit this script"
}

# A per-game submenu. Both games get the same set of options now that
# the mod system is game-aware.
game_menu() {
	local game_key=$1
	local gname="${GAME_NAME[$game_key]}"
	local appimage="${GAME_APPIMAGE[$game_key]}"

	local args=()
	args+=(FALSE Download "Download or update $gname")

	# Only show OpenFolder and Uninstall if the game is installed.
	if dir=$(find_game_dir "$game_key" 2>/dev/null); then
		: # found
	fi

	args+=(FALSE Changelog "View release notes")

	# Only show Mods if the game has mod packs defined.
	if [ -n "${MODS_AVAILABLE[$game_key]}" ]; then
		args+=(FALSE Mods "Manage $gname mods")
	fi

	if [ -n "$dir" ]; then
		args+=(FALSE OpenFolder "Open install folder in file manager")
		args+=(FALSE Uninstall "Uninstall (preserves save data)")
	fi

	args+=(TRUE Back "Return to the main menu")

	zenity --width 650 --height 400 --list --radiolist \
		--title "$title - $gname" \
		--column "Select" \
		--column "Option" \
		--column="Description" \
		"${args[@]}"
}

# ---------------------------------------------------------------------------
# Mod management: detection, enable/disable, remove
# Mods are disabled by appending ".disabled" to the file — the game ignores
# files it doesn't recognize, so this is a clean on/off toggle without deleting.
# ---------------------------------------------------------------------------

# Echo the active (enabled) mod files for a given mod key.
mod_active_files() {
	local mod_key=$1 f base
	case "$mod_key" in
		OS)
			[ -f "mods/steamdeck.otr" ] && echo "mods/steamdeck.otr" ;;
		SteamDeckUI)
			for f in mods/steamdeckui*.otr; do
				[ -f "$f" ] && echo "$f"
			done ;;
		3DS)
			for f in mods/*.otr; do
				[ -f "$f" ] || continue
				base=$(basename "$f")
				case "$base" in
					steamdeck.otr|steamdeckui*|apple.otr|linux.otr|switch.otr|wiiu.otr|windows.otr) ;;
					*) echo "$f" ;;
				esac
			done ;;
		Reloaded|MMReloaded|SM64Reloaded)
			for f in mods/*.o2r; do
				[ -f "$f" ] && echo "$f"
			done ;;
	esac
}

# Echo the disabled mod files for a given mod key.
mod_disabled_files() {
	local mod_key=$1 f base
	case "$mod_key" in
		OS)
			[ -f "mods/steamdeck.otr.disabled" ] && echo "mods/steamdeck.otr.disabled" ;;
		SteamDeckUI)
			for f in mods/steamdeckui*.otr.disabled; do
				[ -f "$f" ] && echo "$f"
			done ;;
		3DS)
			for f in mods/*.otr.disabled; do
				[ -f "$f" ] || continue
				base=$(basename "$f")
				case "${base%.disabled}" in
					steamdeck.otr|steamdeckui*|apple.otr|linux.otr|switch.otr|wiiu.otr|windows.otr) ;;
					*) echo "$f" ;;
				esac
			done ;;
		Reloaded|MMReloaded|SM64Reloaded)
			for f in mods/*.o2r.disabled; do
				[ -f "$f" ] && echo "$f"
			done ;;
	esac
}

mod_is_installed() { [ -n "$(mod_active_files "$1")" ]; }
mod_is_disabled()  { [ -n "$(mod_disabled_files "$1")" ]; }

# Three-state status label for the menu.
mod_status_label() {
	local mod_key=$1
	if mod_is_installed "$mod_key"; then
		echo "[Installed]"
	elif mod_is_disabled "$mod_key"; then
		echo "[Disabled]"
	else
		echo "[Not installed]"
	fi
}

# Disable a mod: rename each active file to .disabled
mod_disable() {
	local mod_key=$1 f
	(
	for f in $(mod_active_files "$mod_key"); do
		mv "$f" "$f.disabled"
	done
	) | progress_bar "Disabling mod..."
}

# Enable a mod: rename each .disabled file back to active
mod_enable() {
	local mod_key=$1 f
	(
	for f in $(mod_disabled_files "$mod_key"); do
		mv "$f" "${f%.disabled}"
	done
	) | progress_bar "Enabling mod..."
}

# Remove a specific mod entirely (active + disabled files)
mod_remove_mod() {
	local mod_key=$1 f
	(
	for f in $(mod_active_files "$mod_key") $(mod_disabled_files "$mod_key"); do
		rm -f "$f"
	done
	) | progress_bar "Removing mod..."
}

# Sub-dialog shown when clicking a mod that is already installed/disabled.
# Returns the chosen action string, or empty on cancel.
mod_action_menu() {
	local mod_key=$1
	local mname=$2
	local status=$3
	local toggle="Disable"
	[ "$status" == "Disabled" ] && toggle="Enable"

	zenity --width 500 --height 400 --list --radiolist \
	--title "$title - $mname" \
	--column "Select" \
	--column="Action" \
	--column="Description" \
	FALSE "Update / Re-download" "Overwrite with a fresh copy" \
	FALSE "$toggle"               "Toggle this mod on or off" \
	FALSE "Remove"               "Delete this mod entirely" \
	TRUE Cancel                  "Go back to the mods menu"
}

mod_menu() {
	local game_key=$1
	local gname="${GAME_NAME[$game_key]}"
	local args=()
	local m name status desc size_human

	for m in ${MODS_AVAILABLE[$game_key]}; do
		status=$(mod_status_label "$m")
		name="${MOD_DISPLAY_NAME[$m]}"
		desc="${MOD_DESC[$m]}"
		# Fetch the download size for display.
		size_human=$(format_size "$(get_url_size "${MOD_URL[$m]}")")
		[ -n "$size_human" ] && desc="($size_human) $desc"
		args+=(FALSE "$name" "$status  $desc")
	done

	args+=(FALSE "Other"  "Browse for more mods (web browser)")
	args+=(FALSE "Remove" "Uninstall ALL mods")
	args+=(TRUE "Back"    "Return to the $gname menu")

	zenity --width 650 --height 500 --list --radiolist \
		--title "$title - $gname Mods" \
		--column "Select" \
		--column "Option" \
		--column="Status / Description" \
		"${args[@]}"
}

# Download and install a mod archive.
# Detects .7z files and uses 7za; everything else uses unzip.
download_mod() {
	local url=$1 filename=$2 modname=$3
	curl -L "$url" -o "$filename"
	if [[ "$filename" == *.7z ]]; then
		if ! command -v 7za > /dev/null 2>&1; then
			message "7-Zip ('7za') is required to install $modname but was not found.\nOn Steam Deck, run:\n  sudo pacman -S p7zip"
			rm -f "$filename"
			return
		fi
		7za x "$filename" -o"$PWD/mods"
	else
		unzip -o "$filename" -d mods/
	fi
	rm -f "$filename"
	message "$modname installed! Make sure \"Use Alternate Assets\" is checked on in Enhancements -> Graphics -> Mods."
}

# ---------------------------------------------------------------------------
# SoH-specific: mods submenu loop.
# ---------------------------------------------------------------------------
mods_loop() {
	local game_key=$1
	# Detect an existing install, or offer to locate it manually.
	dir=$(get_game_dir "$game_key") || return
	cd "$dir" || return
	mkdir -p mods

	local gname="${GAME_NAME[$game_key]}"

	while true; do
		local action
		action=$(mod_menu "$game_key")
		local rc=$?
		if [ $rc -eq 1 ] || [ "$action" == "Back" ]; then
			break

		elif [ "$action" == "Other" ]; then
			xdg-open "${MOD_BROWSE_URL[$game_key]}"

		elif [ "$action" == "Remove" ]; then
			if question "Are you sure you want to remove ALL mods?"; then
				(
				rm -rf mods/*
				) | progress_bar "Removing all mods..."
				message "All mods removed!"
			fi

		# --- Per-mod handling ---
		else
			local mod_key=""
			local m
			for m in ${MODS_AVAILABLE[$game_key]}; do
				if [ "$action" == "${MOD_DISPLAY_NAME[$m]}" ]; then
					mod_key="$m"
					break
				fi
			done

			# If no match found, skip.
			[ -z "$mod_key" ] && continue

			local mname="${MOD_DISPLAY_NAME[$mod_key]}"
			local status

			# Determine current state.
			if mod_is_installed "$mod_key"; then
				status="Installed"
			elif mod_is_disabled "$mod_key"; then
				status="Disabled"
			else
				status="NotInstalled"
			fi

			if [ "$status" == "NotInstalled" ]; then
				if ! mod_check_conflict "$mod_key"; then
					continue
				fi
				mod_do_download "$mod_key"
			else
				# Already installed or disabled — show action menu.
				local choice
				choice=$(mod_action_menu "$mod_key" "$mname" "$status")
				local crc=$?
				if [ $crc -eq 1 ] || [ -z "$choice" ] || [ "$choice" == "Cancel" ]; then
					continue
				elif [ "$choice" == "Update / Re-download" ]; then
					if ! mod_check_conflict "$mod_key"; then
						continue
					fi
					mod_do_download "$mod_key"
				elif [ "$choice" == "Disable" ]; then
					mod_disable "$mod_key"
					message "$mname has been disabled.\nThe game will ignore it until you re-enable it."
				elif [ "$choice" == "Enable" ]; then
					mod_enable "$mod_key"
					message "$mname has been enabled!"
				elif [ "$choice" == "Remove" ]; then
					if question "Remove $mname?"; then
						mod_remove_mod "$mod_key"
						message "$mname removed."
					fi
				fi
			fi
		fi
	done
}

# Check for conflicts before installing 3DS or Reloaded.
# Returns 0 (ok to proceed) or 1 (abort).
mod_check_conflict() {
	local mod_key=$1
	local conflicts="${MOD_CONFLICTS[$mod_key]}"
	local c
	for c in $conflicts; do
		if mod_is_installed "$c" || mod_is_disabled "$c"; then
			if ! question "This will conflict with ${MOD_DISPLAY_NAME[$c]}. Continue?"; then
				return 1
			fi
		fi
	done
	return 0
}

# Perform the actual mod download/installation.
mod_do_download() {
	local mod_key=$1
	local url="${MOD_URL[$mod_key]}"
	local modname="${MOD_DISPLAY_NAME[$mod_key]}"

	# Check file size via HTTP HEAD before downloading.
	local size_bytes size_human=""
	size_bytes=$(get_url_size "$url")
	size_human=$(format_size "$size_bytes")

	# Always prompt to confirm the download, showing the size.
	local prompt="Download and install $modname?"
	[ -n "$size_human" ] && prompt="Download and install $modname ($size_human)?"

	# Add extra warning for large downloads (>50MB).
	if [ -n "$size_bytes" ] && [ "$size_bytes" -ge 52428800 ]; then
		prompt="${prompt}\n\nThis is a large file and may take several minutes to download and extract.\nThe progress bar will pulse during download and extraction.\nThis is normal — please be patient."
		echo -e "\nDownloading $modname ($size_human) — this may take several minutes. Please be patient...\n"
	fi

	if ! question "$prompt"; then
		return
	fi

	yes |
	(
	download_mod "$url" "${MOD_FILE[$mod_key]}" "$modname"

	# OS mod ships extra platform files we don't need on Steam Deck.
	if [ "$mod_key" == "OS" ]; then
		rm -f mods/apple.otr mods/linux.otr mods/switch.otr mods/wiiu.otr mods/windows.otr
	fi
	) | progress_bar "Downloading and installing, please wait..."
}

# ---------------------------------------------------------------------------\
# Steam Shortcuts: global management from the main menu.
# ---------------------------------------------------------------------------\
steam_shortcuts_loop() {
	local args=()
	local g gname dir appimage

	for g in soh 2s2h ghostship starship dusklight; do
		gname="${GAME_NAME[$g]}"
		appimage="${GAME_APPIMAGE[$g]}"
		dir=$(find_game_dir "$g" 2>/dev/null)
		if [ -n "$dir" ] && [ -f "$dir/$appimage" ]; then
			args+=(FALSE "$gname" "Installed")
		else
			args+=(FALSE "$gname" "Not installed")
		fi
	done

	args+=(TRUE Back "Return to the main menu")

	while true; do
		local choice
		choice=$(zenity --width 650 --height 400 --list --radiolist \
			--title "$title - Steam Shortcuts" \
			--column "Select" \
			--column "Game" \
			--column="Status" \
			"${args[@]}" 2>/dev/null)
		local rc=$?
		if [ $rc -eq 1 ] || [ "$choice" == "Back" ] || [ -z "$choice" ]; then
			break
		fi
		# Reverse-lookup the game_key from the display name.
		local game_key=""
		for g in soh 2s2h ghostship starship dusklight; do
			if [ "$choice" == "${GAME_NAME[$g]}" ]; then
				game_key="$g"
				break
			fi
		done
		[ -z "$game_key" ] && continue
		add_steam_shortcut "$game_key"
	done
}

# ---------------------------------------------------------------------------
# ROM dumping guide — shown inline (no external browser needed).
# ---------------------------------------------------------------------------
rom_dumping_guide() {
	local guide="$title - ROM Dumping Guide

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IMPORTANT: You must legally own the original game and
dump the ROM yourself. We do not condone piracy.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

METHOD 1: Wii (Homebrew) — RECOMMENDED
This works for OoT, MM, and SM64 Virtual Console.

1. Install the Homebrew Channel on a modded Wii
2. Download 'CleanRip' from the Homebrew Browser
3. Insert your game disc (Wii/GC) or VC title
4. Run CleanRip and select 'New Device' (USB/SD)
5. Dump to .iso, then extract the N64 ROM

For Virtual Console titles, use 'ShowMiiWads' +
'wadunpacker' to extract the embedded N64 ROM.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

METHOD 2: Dolphin Emulator (GameCube disc)

1. Open Dolphin Emulator
2. Insert your GameCube disc (or use its ISO)
3. Right-click the game → Properties → Filesystem
4. Navigate to the 'files' folder
5. Extract the .z64 ROM file

For Collector's Edition: the OoT ROM is inside
a .tgc archive in the filesystem.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

METHOD 3: N64 Cartridge (USB dumper)

1. Buy an N64 cartridge reader (e.g. Joey Jr,
   Super UFO Pro 8, or Retrode 2)
2. Insert your game cartridge
3. Dump as .z64 (big-endian) format

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ROM FORMAT NOTES

• .z64 (big-endian) — PREFERRED, works with all games
• .n64 (little-endian) — this script auto-converts
• .v64 (byteswapped) — this script auto-converts

Ghostship (SM64) accepts: US or JP versions
Ship of Harkinian (OoT) accepts: US 1.0 / 1.1 / 1.2, GC
2 Ship 2 Harkinian (MM) accepts: US 1.0, GC
Starship (SF64) accepts: US 1.0 / 1.1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VERIFICATION

Verify your ROM is correct before use:
• OoT: https://ship.equipment
• MM:  https://2ship.equipment
• Or check the SHA-1 hash at:
  https://www.romhacking.net/hash/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	echo "$guide" | zenity --width 750 --height 700 --text-info \
		--title "$title - ROM Dumping Guide" --font="monospace 11" --ok-label="Close" --cancel-label="Close" 2>/dev/null
}
# ---------------------------------------------------------------------------
game_menu_loop() {
	local game_key=$1
	while true; do
		local action
		action=$(game_menu "$game_key")
		if [ $? -eq 1 ] || [ "$action" == "Back" ]; then
			break

		elif [ "$action" == "Download" ]; then
			download_game "$game_key"

		elif [ "$action" == "Changelog" ]; then
			changelog_game "$game_key"

		elif [ "$action" == "Uninstall" ]; then
			uninstall_game "$game_key"

		elif [ "$action" == "Mods" ]; then
			mods_loop "$game_key"

		elif [ "$action" == "OpenFolder" ]; then
			open_game_folder "$game_key"
		fi
	done
}

# ---------------------------------------------------------------------------
# Setup directories
# ---------------------------------------------------------------------------
mkdir -p "$HOME/Applications"
BASE_DIR=$(get_base_dir)
mkdir -p "$BASE_DIR"
mkdir -p "$BASE_DIR/ootmm/roms"
mkdir -p "$BASE_DIR/ootmm/out"

# ---------------------------------------------------------------------------
# OoTMM: Ocarina of Time + Majora's Mask Combo Randomizer
# This is a generator tool (not a game) that combines both ROMs into a single
# randomized N64 ROM. The output is played in an emulator.
# ---------------------------------------------------------------------------
OOTMM_REPO="OoTMM/OoTMM"
# Pin to v31.0 — v31.1 has a broken Linux build (Neutralino resource loading regression).
OOTMM_PINNED_TAG="v31.0"

# Always derive OOTMM_DIR from the current base_dir so it stays in sync
# after the user changes the install location.
get_ootmm_dir() { echo "$(get_base_dir)/ootmm"; }

# Find the N64 ROM directory used by emulators (EmuDeck, RetroArch, etc.).
# Returns the path via stdout, or empty if not found.
ootmm_find_rom_dir() {
	local candidates=(
		"$HOME/Emulation/roms/n64"
		"$HOME/Emulation/roms/N64"
		"$HOME/Games/roms/n64"
		"$HOME/Games/roms/N64"
		"$HOME/.var/app/org.libretro.RetroArch/roms/n64"
		"/run/media/mmcblk0p1/Emulation/roms/n64"
		"/run/media/mmcblk0p1/Emulation/roms/N64"
		"/run/media/mmcblk0p1/roms/n64"
		"/run/media/mmcblk0p1/roms/N64"
	)
	local c
	for c in "${candidates[@]}"; do
		if [ -d "$c" ]; then
			echo "$c"
			return 0
		fi
	done
	return 1
}

# Copy the most recent generated ROM to the emulator's N64 folder.
# Also checks the GUI output locations since the Tauri download button is broken.
ootmm_export_rom() {
	local found_rom=""
	local temp_extract=""

	# Check standard CLI output (loose .z64 files).
	if ls "$(get_ootmm_dir)"/out/*.z64 1>/dev/null 2>&1; then
		found_rom=$(ls -t "$(get_ootmm_dir)"/out/*.z64 2>/dev/null | head -1)
	fi

	# Check GUI output — the Tauri app saves a ZIP to ~/Downloads.
	# Also check for loose .z64 in common locations.
	if [ -z "$found_rom" ]; then
		for search_dir in \
			"$HOME/Downloads" \
			"$HOME/.local/share/ootmm" \
			"$HOME/.local/share/com.ootmm" \
			"$(get_ootmm_dir)" \
			"$(get_ootmm_dir)/out"; do
			# First check for loose .z64 files (skip source ROMs).
			if ls "$search_dir"/*.z64 1>/dev/null 2>&1; then
				local f
				for f in "$search_dir"/*.z64; do
					local bn
					bn=$(basename "$f")
					case "$bn" in
						oot.z64|mm.z64) ;;
						*)
							if [ -z "$found_rom" ] || [ "$f" -nt "$found_rom" ]; then
								found_rom="$f"
							fi
							;;
					esac
				done
			fi

			# Then check for ZIP archives containing a .z64 ROM.
			if [ -z "$found_rom" ] && ls "$search_dir"/*.zip 1>/dev/null 2>&1; then
				for z in "$search_dir"/*.zip; do
					if unzip -l "$z" 2>/dev/null | grep -q '\.z64'; then
						temp_extract=$(extract_z64_from_zip "$z")
						if [ -n "$temp_extract" ]; then
							found_rom=$(ls -t "$temp_extract"/*.z64 2>/dev/null | head -1)
							break
						fi
					fi
				done
			fi
			[ -n "$found_rom" ] && break
		done
	fi

	# Last resort: let user browse.
	if [ -z "$found_rom" ]; then
		if question "No generated ROM was found automatically.\nWould you like to browse for it?\n\nYou can select a .z64 file or a .zip containing one."; then
			found_rom=$(zenity --file-selection --file-filter="ROM or ZIP | *.z64 *.n64 *.zip" \
				--title="Select the generated OoTMM ROM" 2>/dev/null) || return
			# If user selected a ZIP, extract it.
			case "$found_rom" in
				*.zip)
					temp_extract=$(extract_z64_from_zip "$found_rom")
					if [ -n "$temp_extract" ]; then
						found_rom=$(ls -t "$temp_extract"/*.z64 2>/dev/null | head -1)
					else
						message "The selected ZIP does not contain a .z64 file."
						return
					fi
					;;
			esac
		else
			message "No generated ROM found.\n\nThe OoTMM GUI typically saves a ZIP to ~/Downloads.\nTry the 'Export' option from the menu to locate and move it."
			return
		fi
	fi

	local romname
	romname=$(basename "$found_rom")

	# Find the emulator ROM directory.
	local romdir
	romdir=$(ootmm_find_rom_dir)

	if [ -z "$romdir" ]; then
		message "No standard N64 ROM folder was found.\nPlease select your emulator's N64 ROM folder."
		romdir=$(zenity --file-selection --directory \
			--title="Select your N64 ROM folder" 2>/dev/null) || { [ -n "$temp_extract" ] && rm -rf "$temp_extract"; return; }
	fi

	# Copy the ROM.
	local dest="$romdir/$romname"
	(
	echo -e "Copying $romname to $romdir...\n"
	cp "$found_rom" "$dest"
	) | progress_bar "Exporting ROM to emulator folder..."

	# Clean up temp extraction.
	[ -n "$temp_extract" ] && rm -rf "$temp_extract"

	if [ -f "$dest" ]; then
		message "$romname has been copied to:\n$romdir\n\nIt should now appear in your emulator's game list."
	else
		message "Failed to copy the ROM. Check permissions for:\n$romdir"
	fi
}

# Check for OoTMM updates. Prompts the user if a newer version is available.
# Ensure OoTMM is installed and up to date. Downloads/updates silently.
ootmm_ensure_latest() {
	# If not installed at all, download without asking.
	if ! ootmm_is_installed; then
		ootmm_download
		ootmm_is_installed || return 1
		return 0
	fi

	# Check for updates.
	local local_ver remote_ver
	local_ver=$(cat "$(get_ootmm_dir)/.version" 2>/dev/null || echo "unknown")
	remote_ver="${OOTMM_PINNED_TAG:-$(github_latest_tag "$OOTMM_REPO")}"

	# If we can't determine either version, skip the check.
	if [ "$local_ver" == "unknown" ] || [ -z "$remote_ver" ]; then
		return 0
	fi

	# If versions match, all good.
	if [ "$local_ver" == "$remote_ver" ]; then
		return 0
	fi

	# A newer version is available — auto-update.
	echo "Updating OoTMM from $local_ver to $remote_ver..."
	ootmm_download
}

ootmm_is_installed() {
	[ -f "$(get_ootmm_dir)/ootmm-linux_x64" ] && [ -f "$(get_ootmm_dir)/resources.neu" ]
}

# Check if libwebkit2gtk is available (required by OoTMM's Tauri runtime).
# Returns 0 if found, 1 if missing.
ootmm_check_webkit() {
	# Try loading via ldconfig
	if ldconfig -p 2>/dev/null | grep -q "libwebkit2gtk-4"; then
		return 0
	fi
	# Check common library paths
	for lib in \
		/usr/lib/libwebkit2gtk-4.0.so.37 \
		/usr/lib/libwebkit2gtk-4.1.so.0 \
		/usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37 \
		/usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0; do
		[ -f "$lib" ] && return 0
	done
	return 1
}

# Offer to install libwebkit2gtk on Steam Deck / Arch-based systems.
ootmm_install_webkit() {
	if ootmm_check_webkit; then
		return 0
	fi

	# Detect if we're on SteamOS (Steam Deck)
	local is_steamos=false
	if [ -f /etc/os-release ] && grep -qi "SteamOS" /etc/os-release 2>/dev/null; then
		is_steamos=true
	fi

	if [ "$is_steamos" == true ]; then
		if ! question "OoTMM requires libwebkit2gtk, which is not installed.\n\nOn Steam Deck this requires temporarily disabling the read-only filesystem.\nThe steps are:\n  1. Disable read-only root\n  2. Install webkit2gtk-4.1 via pacman\n  3. Re-enable read-only root\n\nNote: This change survives until a SteamOS system update.\n\nInstall libwebkit2gtk now?"; then
			message "OoTMM cannot run without libwebkit2gtk.\n\nTo install manually:\n  sudo steamos-readonly disable\n  sudo pacman-key --init\n  sudo pacman-key --populate holo archlinux\n  sudo pacman -Sy archlinux-keyring\n  sudo pacman -S webkit2gtk-4.1\n  sudo steamos-readonly enable"
			return 1
		fi

		(
		echo -e "Installing libwebkit2gtk...\n"
		echo -e "Step 1: Disabling read-only root...\n"
		sudo steamos-readonly disable
		echo -e "Step 2: Initializing pacman keyring...\n"
		sudo pacman-key --init
		sudo pacman-key --populate holo archlinux
		echo -e "Step 3: Updating Arch keyring (fixes trust issues)...\n"
		sudo pacman -Sy --noconfirm archlinux-keyring
		echo -e "Step 4: Installing webkit2gtk-4.1...\n"
		sudo pacman -S --noconfirm webkit2gtk-4.1
		echo -e "Step 5: Re-enabling read-only root...\n"
		sudo steamos-readonly enable
		) | progress_bar "Installing libwebkit2gtk..."

		if ootmm_check_webkit; then
			message "libwebkit2gtk installed successfully!\nOoTMM should now work."
			return 0
		else
			message "Installation may have failed.\nTry running these commands manually:\n\n  sudo steamos-readonly disable\n  sudo pacman-key --init\n  sudo pacman-key --populate holo archlinux\n  sudo pacman -Sy archlinux-keyring\n  sudo pacman -S webkit2gtk-4.1\n  sudo steamos-readonly enable"
			return 1
		fi

	elif command -v pacman > /dev/null 2>&1; then
		# Generic Arch Linux
		if ! question "OoTMM requires libwebkit2gtk, which is not installed.\n\nInstall webkit2gtk-4.1 now?"; then
			return 1
		fi
		sudo pacman -S --noconfirm webkit2gtk-4.1
		ootmm_check_webkit && return 0 || return 1

	elif command -v apt > /dev/null 2>&1; then
		# Debian/Ubuntu
		if ! question "OoTMM requires libwebkit2gtk, which is not installed.\n\nInstall it now?"; then
			return 1
		fi
		sudo apt update && sudo apt install -y libwebkit2gtk-4.1-0
		ootmm_check_webkit && return 0 || return 1

	else
		message "OoTMM requires libwebkit2gtk-4.0 or 4.1.\n\nPlease install it using your distro's package manager, then try again."
		return 1
	fi
}

ootmm_download() {
	local tag
	tag="${OOTMM_PINNED_TAG:-$(github_latest_tag "$OOTMM_REPO")}"

	if ootmm_is_installed; then
		if ! question "OoTMM generator is already installed (v${tag:-unknown}).\nDownload the latest version?"; then
			return
		fi
	fi

	local url
	if [ -n "$OOTMM_PINNED_TAG" ]; then
		url=$(curl -s "https://api.github.com/repos/$OOTMM_REPO/releases/tags/$OOTMM_PINNED_TAG" \
			| grep "browser_download_url" | grep "linux_x64" | cut -d '"' -f 4)
	else
		url=$(github_latest_asset_url "$OOTMM_REPO" "linux_x64")
	fi

	if [ -z "$url" ]; then
		message "Could not find the OoTMM Linux release.\nPlease check your connection and try again."
		return
	fi

	(
	echo -e "Downloading OoTMM generator...\n"
	curl -L "$url" -o /tmp/ootmm-linux.zip
	echo -e "Extracting...\n"
	rm -f "$(get_ootmm_dir)/ootmm-linux_x64" "$(get_ootmm_dir)/resources.neu"
	unzip -o /tmp/ootmm-linux.zip -d "$(get_ootmm_dir)"
	rm -f /tmp/ootmm-linux.zip
	chmod +x "$(get_ootmm_dir)/ootmm-linux_x64"
	mkdir -p "$(get_ootmm_dir)/roms" "$(get_ootmm_dir)/out"

	# Extract web assets from resources.neu to a physical resources/ directory.
	# Neutralino's runtime can't reliably read the .neu bundle on SteamOS,
	# causing NE_RS_UNBLDRE errors. Physical files work around this.
	"$PYTHON" - "$PWD/$(get_ootmm_dir)/resources.neu" << 'PYEOF'
import json, os, sys

neu_path = sys.argv[1]
with open(neu_path, 'rb') as f:
    data = f.read()

# Parse the manifest JSON at the start of the file.
brace_count = 0
json_end = 0
for i, b in enumerate(data):
    if b == 123: brace_count += 1  # {
    elif b == 125:                # }
        brace_count -= 1
        if brace_count == 0:
            json_end = i + 1
            break

manifest = json.loads(data[:json_end])
file_data = data[json_end:]
out_base = os.path.dirname(neu_path)

def extract(node, prefix):
    for name, info in node.get('files', {}).items():
        if 'files' in info:
            extract(info, os.path.join(prefix, name))
        elif 'offset' in info and 'size' in info:
            offset = int(info['offset'])
            size = int(info['size'])
            filepath = os.path.join(prefix, name)
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, 'wb') as f:
                f.write(file_data[offset:offset+size])

extract(manifest, out_base)
PYEOF

	# Save the version tag for update checks.
	echo "$tag" > "$(get_ootmm_dir)/.version"
	) | progress_bar "Downloading OoTMM, please wait..."

	# Verify extraction succeeded.
	if [ ! -f "$(get_ootmm_dir)/resources.neu" ] || \
	   [ ! -f "$(get_ootmm_dir)/ootmm-linux_x64" ]; then
		message "Download failed — files are missing after extraction.\nCheck your internet connection and try again."
		return 1
	fi
	local neu_size
	neu_size=$(stat -c%s "$(get_ootmm_dir)/resources.neu" 2>/dev/null || stat -f%z "$(get_ootmm_dir)/resources.neu" 2>/dev/null)
	if [ -z "$neu_size" ] || [ "$neu_size" -lt 1000000 ]; then
		message "Download may be corrupt (resources.neu is only ${neu_size:-0} bytes).\nPlease try again."
		rm -f "$(get_ootmm_dir)/resources.neu" "$(get_ootmm_dir)/ootmm-linux_x64"
		return 1
	fi

	if ootmm_check_webkit; then
		message "OoTMM generator installed!"
	else
		if question "OoTMM generator installed!\n\nHowever, OoTMM also requires libwebkit2gtk to run.\nWould you like to install it now?"; then
			ootmm_install_webkit
		else
			message "OoTMM generator installed!\n\nNote: You'll need libwebkit2gtk before you can generate seeds.\nThe script will offer to install it when you try."
		fi
	fi
}

ootmm_changelog() {
	local output
	output=$(curl -s "https://raw.githubusercontent.com/OoTMM/OoTMM/master/CHANGELOG.md" 2>/dev/null | head -150)

	if [ -z "$output" ]; then
		message "Could not fetch the OoTMM changelog."
		return
	fi

	echo "$output" | zenity --width 700 --height 600 --text-info \
		--title "$title - OoTMM Changelog" \
		--font="Monospace 11" --ok-label="Close" --cancel-label="Close" 2>/dev/null
}

# Launch the OoTMM GUI directly (its built-in Tauri webview app).
# This gives the user the full visual settings configurator, ROM picker,
# seed generation, and output management — all in one place.
ootmm_launch_gui() {
	# Ensure installed and up to date (auto-downloads/updates silently).
	ootmm_ensure_latest || return

	# Check for libwebkit2gtk dependency.
	if ! ootmm_check_webkit; then
		ootmm_install_webkit || return
	fi

	cd "$(get_ootmm_dir)" || return

	# Check that ROMs are present — the GUI won't generate without them.
	local rom_count
	rom_count=$(ls roms/*.z64 2>/dev/null | wc -l)
	if [ "$rom_count" -lt 2 ]; then
		if ! question "OoTMM needs both OoT and MM ROMs in:\n$(pwd)/roms/\n\nFound: $rom_count ROM(s)\n\nLaunch anyway?"; then
			message "Copy your .z64 ROMs to:\n$(pwd)/roms/\n\nThen try again."
			return
		fi
	fi

	# Record which ROMs/archives exist before launching (to detect new ones).
	local before_z64 before_zip
	before_z64=$(ls "$(get_ootmm_dir)"/out/*.z64 2>/dev/null | wc -l)
	before_zip=$(ls "$HOME"/Downloads/*ootmm* "$HOME"/Downloads/*OoTMM* 2>/dev/null | wc -l)

	echo "Launching OoTMM GUI..."
	# SteamOS webkit2gtk needs these env vars to render correctly.
	# Without them: flickering, frozen UI during generation, GDK monitor errors.
	GDK_BACKEND=x11 \
	WEBKIT_DISABLE_COMPOSITING_MODE=1 \
	WEBKIT_DISABLE_DMABUF_RENDERER=1 \
	"./ootmm-linux_x64" &
	local gui_pid=$!

	# Show a non-blocking info dialog with tips while the GUI runs.
	zenity --info --title "OoTMM Tips" --no-wrap \
		--text "OoTMM GUI is launching.\n\nIf seed generation appears stuck:\n• Try 'Default' settings\n• The solver may be retrying\n• Check the out/ folder for generated ROMs\n\nUse our Export option after generating." \
		--ok-label="Got it" 2>/dev/null &

	# Wait for the GUI to close.
	wait "$gui_pid" 2>/dev/null

	# After the GUI closes, check if a new ROM was generated.
	# The GUI's built-in "download seed" button is broken on Steam Deck,
	# so we handle the export ourselves.
	local after_z64 after_zip
	after_z64=$(ls "$(get_ootmm_dir)"/out/*.z64 2>/dev/null | wc -l)
	after_zip=$(ls "$HOME"/Downloads/*ootmm* "$HOME"/Downloads/*OoTMM* 2>/dev/null | wc -l)

	# Detect new files in any location.
	local found_new=false
	if [ "$after_z64" -gt "$before_z64" ]; then
		found_new=true
	elif [ "$after_zip" -gt "$before_zip" ]; then
		found_new=true
	fi

	if [ "$found_new" == true ]; then
		if question "A new ROM was detected!\n\nWould you like to copy it to your emulator's N64 ROM folder?"; then
			ootmm_export_rom
		fi
	fi
}

# Remove the OoTMM generator, preserving user ROMs and generated output.
ootmm_uninstall() {
	local dir
	dir=$(get_ootmm_dir)

	if ! ootmm_is_installed; then
		message "OoTMM is not installed."
		return
	fi

	if ! question "Uninstall the OoTMM generator?\n(your ROMs and generated output will be preserved)"; then
		return
	fi

	(
	echo -e "Uninstalling OoTMM...\n"
	rm -f "$dir/ootmm-linux_x64" "$dir/resources.neu" "$dir/.version"
	) | progress_bar "Uninstalling OoTMM..."
	message "OoTMM generator removed.\nYour ROMs and generated ROMs have been preserved."
}

ootmm_menu_loop() {
	# Build menu options dynamically — Uninstall only shows if installed.
	local args=(
		TRUE "Launch GUI"  "Generate a randomized ROM via the OoTMM GUI"
		FALSE "Export"     "Copy generated ROM to emulator's N64 folder"
		FALSE "Changelog"  "View OoTMM changelog"
		FALSE "OpenFolder" "Open the OoTMM folder"
	)
	if ootmm_is_installed; then
		args+=(FALSE "Uninstall" "Remove the OoTMM generator")
	fi
	args+=(FALSE "Back" "Return to the main menu")

	while true; do
		local action
		action=$(zenity --width 650 --height 450 --list --radiolist \
			--title "$title - OoTMM Randomizer" \
			--column "Select" \
			--column "Option" \
			--column="Description" \
			"${args[@]}" 2>/dev/null)
		local rc=$?
		if [ $rc -eq 1 ] || [ "$action" == "Back" ]; then
			break
		elif [ "$action" == "Launch GUI" ]; then
			ootmm_launch_gui
		elif [ "$action" == "Export" ]; then
			ootmm_export_rom
		elif [ "$action" == "Changelog" ]; then
			ootmm_changelog
		elif [ "$action" == "OpenFolder" ]; then
			xdg-open "$(get_ootmm_dir)"
		elif [ "$action" == "Uninstall" ]; then
			ootmm_uninstall
		fi
	done
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while true; do
	Choice=$(main_menu)
	if [ $? -eq 1 ] || [ "$Choice" == "Exit" ]; then
		echo Goodbye!
		exit

	elif [ "$Choice" == "Ship of Harkinian" ]; then
		game_menu_loop soh

	elif [ "$Choice" == "2 Ship 2 Harkinian" ]; then
		game_menu_loop 2s2h

	elif [ "$Choice" == "Ghostship" ]; then
		game_menu_loop ghostship

	elif [ "$Choice" == "Starship" ]; then
		game_menu_loop starship

	elif [ "$Choice" == "Dusklight" ]; then
		game_menu_loop dusklight

	# OoTMM disabled — broken by SteamOS webkit2gtk regression (July 2026).
	# Re-enable once OoTMM or SteamOS fixes Web Worker/WASM support.
	# elif [ "$Choice" == "OoTMM Randomizer" ]; then
	#	ootmm_menu_loop

	elif [ "$Choice" == "Steam Shortcuts" ]; then
		steam_shortcuts_loop

	elif [ "$Choice" == "Install Location" ]; then
		set_install_location

	elif [ "$Choice" == "Dumping" ]; then
		rom_dumping_guide
	fi
done
