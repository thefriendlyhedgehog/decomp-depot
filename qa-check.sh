#!/bin/bash
# ============================================================
# Decomp Depot QA Checker
# Run this to validate config, URLs, structure, and dead code
# before testing on the Steam Deck.
# ============================================================

SCRIPT="decomp-depot.sh"
PASS=0
FAIL=0
WARN=0
VERBOSE=false

[ "$1" == "-v" ] && VERBOSE=true

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

echo "=============================================="
echo "  Decomp Depot QA Checker"
echo "=============================================="
echo ""

# ------------------------------------------------
echo "1. SYNTAX CHECK"
echo "----------------------------------------------"
if bash -n "$SCRIPT" 2>/dev/null; then
	ok "Syntax valid"
else
	fail "Syntax errors found:"
	bash -n "$SCRIPT" 2>&1 | head -5
fi

LINES=$(wc -l < "$SCRIPT")
echo ""
ok "Script size: $LINES lines"

# ------------------------------------------------
echo ""
echo "2. CONFIG CONSISTENCY"
echo "----------------------------------------------"

# Game config checks — grep values directly from the script
GAMES="soh 2s2h ghostship starship dusklight"
for g in $GAMES; do
	name=$(grep -oE "GAME_NAME\[$g\]=\"[^\"]+\"" "$SCRIPT" | cut -d'"' -f2)
	repo=$(grep -oE "GAME_REPO\[$g\]=\"[^\"]+\"" "$SCRIPT" | cut -d'"' -f2)
	appimg=$(grep -oE "GAME_APPIMAGE\[$g\]=\"[^\"]+\"" "$SCRIPT" | cut -d'"' -f2)
	dir=$(grep -oE "GAME_DIR\[$g\]=\"[^\"]+\"" "$SCRIPT" | cut -d'"' -f2)
	otr=$(grep -oE "GAME_OTR\[$g\]=\"[^\"]+\"" "$SCRIPT" | cut -d'"' -f2)
	if [ -n "$name" ]; then
		ok "$name ($g) defined"
	else
		fail "$g missing GAME_NAME"
	fi
	[ -z "$repo" ]   && fail "$g missing GAME_REPO"
	[ -z "$appimg" ] && fail "$g missing GAME_APPIMAGE"
	[ -z "$dir" ]    && fail "$g missing GAME_DIR"
	# OTR can be empty for games that use raw ISO (e.g. Dusklight)
	otr_line=$(grep -c "GAME_OTR\[$g\]=" "$SCRIPT")
	[ "$otr_line" -eq 0 ] && warn "$g missing GAME_OTR entry"
done

# Mod config checks
ALL_MODS=$(grep -oE 'MOD_URL\[([a-zA-Z0-9]+)\]' "$SCRIPT" | grep -oE '\[([a-zA-Z0-9]+)\]' | tr -d '[]' | sort -u)
for m in $ALL_MODS; do
	[ -z "$m" ] && continue
	url=$(grep -oE "MOD_URL\[$m\]=\"[^\"]+\"" "$SCRIPT" | cut -d'"' -f2)
	file=$(grep -oE "MOD_FILE\[$m\]=\"[^\"]+\"" "$SCRIPT" | cut -d'"' -f2)
	if [ -z "$url" ]; then
		fail "Mod '$m' missing MOD_URL"
	elif [ -z "$file" ]; then
		fail "Mod '$m' missing MOD_FILE"
	else
		ok "Mod '$m' has URL + filename"
	fi
done

echo ""
echo "3. DEAD CODE CHECK"
echo "----------------------------------------------"
# Extract all function definitions
FUNCS=$(grep -oE '^[a-z_]+\(\)' "$SCRIPT" | tr -d '()')
for f in $FUNCS; do
	# Count calls (exclude the definition line)
	CALLS=$(grep -c "\b${f}\b" "$SCRIPT" 2>/dev/null)
	if [ "$CALLS" -le 1 ]; then
		warn "Function '$f' defined but never called"
	fi
done
[ "$WARN" -eq 0 ] && ok "No dead functions found"

echo ""
echo "4. REMOVED FEATURES CHECK"
echo "----------------------------------------------"
# Play should be gone
if grep -q 'play_game' "$SCRIPT"; then
	fail "play_game still referenced"
else
	ok "play_game fully removed"
fi
# convert_rom_to_z64 should be gone
if grep -q 'convert_rom_to_z64' "$SCRIPT"; then
	fail "convert_rom_to_z64 still referenced"
else
	ok "convert_rom_to_z64 fully removed"
fi
# SteamID echo should be gone
if grep -qE 'echo.*Steam ID is' "$SCRIPT"; then
	fail "SteamID terminal echo still present"
else
	ok "SteamID echo removed"
fi
# Browser fallback on changelog cancel should be gone
if grep -q 'xdg-open.*CHANGELOG\|xdg-open.*changelog' "$SCRIPT"; then
	fail "Changelog browser fallback still present"
else
	ok "Changelog browser fallback removed"
fi
# OoTMM should be hidden from main menu
if grep -q '"OoTMM Randomizer"' <(sed -n '/^main_menu/,/^}/p' "$SCRIPT"); then
	fail "OoTMM still visible in main menu"
else
	ok "OoTMM hidden from main menu"
fi

echo ""
echo "5. MENU STRUCTURE"
echo "----------------------------------------------"
# Verify main menu options
MAIN_OPTS=$(sed -n '/^main_menu/,/^}/p' "$SCRIPT" | grep -oE '"[^"]+" +"' | tr -d '"' | sed 's/ *$//')
for opt in "Ship of Harkinian" "2 Ship 2 Harkinian" "Ghostship" "Starship" "Dusklight" "Steam Shortcuts" "Install Location"; do
	if echo "$MAIN_OPTS" | grep -q "$opt"; then
		ok "Main menu has '$opt'"
	else
		fail "Main menu missing '$opt'"
	fi
done
# Dumping and Exit are unquoted in the script
if sed -n '/^main_menu/,/^}/p' "$SCRIPT" | grep -q 'Dumping'; then
	ok "Main menu has 'Dumping'"
else
	fail "Main menu missing 'Dumping'"
fi
if sed -n '/^main_menu/,/^}/p' "$SCRIPT" | grep -q 'TRUE Exit'; then
	ok "Main menu has 'Exit'"
else
	fail "Main menu missing 'Exit'"
fi

# Game menu should NOT have Play
GAME_MENU=$(sed -n '/^game_menu /,/^}/p' "$SCRIPT")
if echo "$GAME_MENU" | grep -q '"Play"'; then
	fail "Game menu still has Play option"
else
	ok "Game menu has no Play option"
fi

echo ""
echo "6. NETWORK CHECKS (this takes a moment)"
echo "----------------------------------------------"

# Check game repo releases
check_repo() {
	local name=$1 repo=$2
	local count
	count=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | grep -c '"tag_name"')
	if [ "$count" -gt 0 ]; then
		local tag
		tag=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d '"' -f4)
		ok "$name: latest release = $tag"
	else
		fail "$name ($repo): no release found"
	fi
}
check_repo "SoH"      "HarbourMasters/Shipwright"
check_repo "2S2H"     "HarbourMasters/2ship2harkinian"
check_repo "Ghostship" "HarbourMasters/Ghostship"
check_repo "Starship"  "HarbourMasters/Starship"
check_repo "Dusklight" "TwilitRealm/dusklight"

echo ""

# Check mod URLs (HEAD only)
check_url() {
	local name=$1 url=$2
	local code
	code=$(curl -sIL -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | tail -1)
	case "$code" in
		200|302|301) ok "$name: HTTP $code";;
		000) warn "$name: no response (timeout/blocked)";;
		*)   fail "$name: HTTP $code";;
	esac
}
check_url "SteamDeckIntro"  "https://gamebanana.com/dl/978007"
check_url "SteamDeckUI"     "https://gamebanana.com/dl/1028208"
check_url "3DS Textures"    "https://gamebanana.com/dl/1095310"
check_url "OoT Reloaded"    "https://evilgames.eu/files/texture-packs/oot-reloaded-v11.0.0-soh-o2r-hd.7z"
check_url "MM Reloaded"     "https://evilgames.eu/files/texture-packs/mm-reloaded-v11.0.2-2ship-o2r-hd.7z"
check_url "SM64 Reloaded"   "https://github.com/GhostlyDark/SM64-Reloaded/releases/download/v2.6.0/sm64-reloaded-v2.6.0-gs-o2r-hd.7z"

echo ""
echo "7. MOD SIZES"
echo "----------------------------------------------"
check_size() {
	local name=$1 url=$2
	local size
	size=$(curl -sIL "$url" 2>/dev/null | grep -i "content-length" | tail -1 | tr -d '\r' | awk '{print $2}')
	if [ -n "$size" ] && [ "$size" -gt 0 ]; then
		local human
		if [ "$size" -ge 1073741824 ]; then
			human=$(awk "BEGIN {printf \"%.1fGB\", $size/1073741824}")
		elif [ "$size" -ge 1048576 ]; then
			human=$(awk "BEGIN {printf \"%.1fMB\", $size/1048576}")
		elif [ "$size" -ge 1024 ]; then
			human=$(awk "BEGIN {printf \"%dKB\", $size/1024}")
		else
			human="${size}B"
		fi
		echo "  📦 $name: $human"
	else
		warn "$name: size unknown"
	fi
}
check_size "SteamDeckIntro"  "https://gamebanana.com/dl/978007"
check_size "SteamDeckUI"     "https://gamebanana.com/dl/1028208"
check_size "3DS Textures"    "https://gamebanana.com/dl/1095310"
check_size "OoT Reloaded"    "https://evilgames.eu/files/texture-packs/oot-reloaded-v11.0.0-soh-o2r-hd.7z"
check_size "MM Reloaded"     "https://evilgames.eu/files/texture-packs/mm-reloaded-v11.0.2-2ship-o2r-hd.7z"
check_size "SM64 Reloaded"   "https://github.com/GhostlyDark/SM64-Reloaded/releases/download/v2.6.0/sm64-reloaded-v2.6.0-gs-o2r-hd.7z"

echo ""
echo "8. COMMON ISSUES"
echo "----------------------------------------------"
# Check for raw python3 (should use $PYTHON)
RAW_PY=$(grep -nE '[^"$_]python3 ' "$SCRIPT" | grep -v '^#' | grep -v 'PYTHON=\|check_python\|which python\|alias')
if [ -n "$RAW_PY" ]; then
	warn "Raw 'python3' calls found:"
	echo "$RAW_PY" | head -3
else
	ok "All python calls use \$PYTHON"
fi

# Check for dangerous rm -rf
DANGEROUS=$(grep -n 'rm -rf.*\$HOME\|rm -rf.*\$\{.*DIR\}' "$SCRIPT" | grep -v '/tmp\|resources\|ootmm-linux')
if [ -n "$DANGEROUS" ]; then
	fail "Dangerous rm -rf found:"
	echo "$DANGEROUS"
else
	ok "No dangerous rm -rf on user paths"
fi

# Check for hardcoded paths that won't work on Steam Deck
HARDCODED=$(grep -n '/home/kevin\|/Users/' "$SCRIPT")
if [ -n "$HARDCODED" ]; then
	fail "Hardcoded user paths found:"
	echo "$HARDCODED"
else
	ok "No hardcoded user paths"
fi

# Check zenity text-info has Close labels
TEXT_INFO_COUNT=$(grep -c 'text-info' "$SCRIPT")
CLOSE_COUNT=$(grep -c 'ok-label.*Close' "$SCRIPT")
if [ "$TEXT_INFO_COUNT" -eq "$CLOSE_COUNT" ]; then
	ok "All text-info dialogs have Close labels ($CLOSE_COUNT/$TEXT_INFO_COUNT)"
else
	warn "text-info dialogs ($TEXT_INFO_COUNT) vs Close labels ($CLOSE_COUNT) mismatch"
fi

# ------------------------------------------------
echo ""
echo "=============================================="
echo "  SUMMARY"
echo "=============================================="
echo "  ✅ Pass:  $PASS"
echo "  ❌ Fail:  $FAIL"
echo "  ⚠️  Warn:  $WARN"
echo ""
if [ "$FAIL" -gt 0 ]; then
	echo "  ❌ FIX FAILURES BEFORE TESTING"
elif [ "$WARN" -gt 0 ]; then
	echo "  ⚠️  Review warnings, then proceed to manual testing"
else
	echo "  ✅ ALL CHECKS PASSED — proceed to manual testing"
fi
echo ""
echo "=============================================="
echo "  MANUAL TEST CHECKLIST"
echo "=============================================="
cat << 'CHECKLIST'
Copy decomp-depot.sh to Steam Deck and test each:

[ ] 1. DOWNLOAD: Download SoH → no auto-launch, prompts for Steam shortcut
[ ] 2. DOWNLOAD: Download each game (soh, 2s2h, ghostship, starship, dusklight)
[ ] 2a. DUSKLIGHT: Direct AppImage download (no zip/extract), no OTR needed
[ ] 2b. DUSKLIGHT: Steam shortcut uses "Dusklight (TP)" display name
[ ] 3. MIGRATION: Set Install Location → single summary popup
[ ] 4. MIGRATION: Move back → games detected, migrated again
[ ] 5. STEAM SHORTCUTS: Each game shows display name (not internal key)
[ ] 6. STEAM SHORTCUTS: Shortcut appears in Steam after restart
[ ] 7. MODS: Download a small mod → size shown in prompt
[ ] 8. MODS: Download a large mod → patience warning + terminal message
[ ] 9. MODS: Enable/Disable toggle works
[ ] 10. MODS: Remove ALL mods works
[ ] 11. MODS: 3DS + Reloaded conflict warning appears
[ ] 12. CHANGELOG: Inline display works for each game
[ ] 13. CHANGELOG: Both buttons say "Close"
[ ] 14. UNINSTALL: Game removed, ROM/saves/mods preserved
[ ] 15. DUMPING: Guide displays, scrollable
[ ] 16. MENU: OoTMM not visible
[ ] 17. MENU: No Play option in game menus

FUTURE PORTS TO ADD (when released):
  - Harvest Moon (HarbourMasters)
  - Wind Waker (Wind Waker team / HarbourMasters)
CHECKLIST
