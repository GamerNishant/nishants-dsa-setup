#!/bin/bash
# Restores the setup that existed before Nishant's DSA Setup ran (macOS).
# Only undoes what setup.sh recorded. Settings the student changed after setup
# are kept. Backups are never deleted. Homebrew itself is never removed.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
UNATTENDED="${NISHANT_DSA_UNATTENDED:-0}"
[ "${1:-}" = "--yes" ] && UNATTENDED=1

ROOT="$HOME/.nishant-dsa"
STATE="$ROOT/state"
MANIFEST="$STATE/manifest.json"
LOG="$ROOT/setup.log"
JSONEDIT() { osascript -l JavaScript "$HERE/jsonedit.js" "$@"; }

log()  { printf '%s  %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG"; }
step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m[ok]\033[0m   %s\n' "$*"; log "OK $*"; }
skip() { printf '    \033[90m[skip] %s\033[0m\n' "$*"; }
warn() { printf '    \033[33m[warn]\033[0m %s\n' "$*"; log "WARN $*"; }
ask() {
    if [ "$UNATTENDED" = "1" ]; then [ "$2" = "y" ]; return; fi
    local hint="[y/N]"; [ "$2" = "y" ] && hint="[Y/n]"
    local answer
    while true; do
        printf '    %s %s ' "$1" "$hint"
        read -r answer < /dev/tty || answer=""
        answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
        [ -z "$answer" ] && answer="$2"
        case "$answer" in y|yes) return 0 ;; n|no) return 1 ;; esac
    done
}
print_result() {  # turns jsonedit "ok/skip/warn ..." lines into coloured output
    while IFS= read -r line; do
        case "$line" in
            ok\ *) ok "${line#ok }" ;;
            warn\ *) warn "${line#warn }" ;;
            skip\ *) skip "${line#skip }" ;;
            "") ;;
            *) printf '    %s\n' "$line" ;;
        esac
    done
}

printf '\n\033[35m  =============================================\n'
printf "     Nishant's DSA Setup - Restore previous setup\n"
printf '  =============================================\033[0m\n\n'

if [ ! -d "$STATE" ] || [ -z "$(ls -A "$STATE" 2>/dev/null | grep -v '^backups$')" ]; then
    echo "  Nothing to restore: the setup has not changed anything on this Mac."
    exit 0
fi
cat <<'EOF'
  This puts back the settings you had before running the setup:
    - VS Code settings, shell prompt and Terminal font
    - removes the extensions, fonts and prompt the setup added
    - reinstalls any extension the setup replaced
  Settings you changed yourself after the setup are kept.

EOF
ask "Restore your previous setup?" y || { echo "  Cancelled. Nothing was changed."; exit 0; }
log "=== restore started ==="

# Safety copy of the current state first.
BEFORE="$STATE/backups/before-restore-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$BEFORE"
for f in "$HOME/Library/Application Support/Code/User/settings.json" "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$f" ] && cp "$f" "$BEFORE/"
done

step "Settings"
[ -f "$MANIFEST" ] && JSONEDIT restore "$MANIFEST" | print_result
if [ -f "$STATE/created-files.txt" ]; then
    while IFS= read -r f; do [ -f "$f" ] && rm -f "$f" && ok "removed $f"; done < "$STATE/created-files.txt"
fi

step "Shell prompt"
[ -f "$MANIFEST" ] && JSONEDIT rmblocks "$MANIFEST" | print_result
if [ -f "$STATE/terminal-font.prev" ]; then
    prev="$(cat "$STATE/terminal-font.prev")"
    name="${prev%|*}"; size="${prev##*|}"
    if osascript -e "tell application \"Terminal\" to set font name of default settings to \"$name\"" \
                 -e "tell application \"Terminal\" to set font size of default settings to $size" >/dev/null 2>&1; then
        ok "Terminal app font set back to $name $size"
    fi
fi
rm -rf "$ROOT/bin" "$ROOT/nishant.omp.json"

step "VS Code extensions"
CODE=""
for app in "/Applications/Visual Studio Code.app" "$HOME/Applications/Visual Studio Code.app"; do
    [ -x "$app/Contents/Resources/app/bin/code" ] && CODE="$app/Contents/Resources/app/bin/code" && break
done
if [ -n "$CODE" ]; then
    if [ -f "$STATE/extensions-added.txt" ]; then
        while IFS= read -r ext; do
            [ -z "$ext" ] && continue
            "$CODE" --uninstall-extension "$ext" >> "$LOG" 2>&1 && ok "removed $ext" || skip "$ext was already removed"
        done < "$STATE/extensions-added.txt"
    fi
    if [ -f "$STATE/extensions-removed.txt" ]; then
        while IFS= read -r ext; do
            [ -z "$ext" ] && continue
            "$CODE" --install-extension "$ext" >> "$LOG" 2>&1 && ok "reinstalled $ext" || warn "could not reinstall $ext"
        done < "$STATE/extensions-removed.txt"
    fi
else
    skip "VS Code not found"
fi

step "Fonts"
if [ -f "$STATE/fonts.txt" ]; then
    count=0
    while IFS= read -r f; do [ -f "$f" ] && rm -f "$f" && count=$((count + 1)); done < "$STATE/fonts.txt"
    ok "$count font files removed"
else
    skip "no fonts to remove"
fi

step "Tools"
BREW=""
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
if [ -f "$STATE/installed-gcc" ] && [ -n "$BREW" ]; then
    if ask "Remove the GCC compiler the setup installed (brew gcc)?" y; then
        "$BREW" uninstall gcc >> "$LOG" 2>&1 && ok "removed GCC" || warn "could not remove GCC (another package may need it)"
    else
        skip "kept GCC"
    fi
fi
if [ -f "$STATE/installed-vscode" ] && [ -n "$BREW" ]; then
    if ask "VS Code was installed by the setup. Uninstall VS Code too?" n; then
        "$BREW" uninstall --cask visual-studio-code >> "$LOG" 2>&1 && ok "VS Code uninstalled"
    else
        skip "kept VS Code"
    fi
fi
if [ -f "$STATE/installed-brew" ]; then
    skip "Homebrew was installed by the setup and is kept (other apps may use it)"
fi

# Archive the state so a future setup starts fresh; backups stay.
DONE="$STATE/restored-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$DONE"
for f in "$STATE"/*; do
    case "$(basename "$f")" in backups|restored-*) ;; *) mv "$f" "$DONE/" ;; esac
done
log "=== restore finished ==="
cat <<EOF

  Your previous setup has been restored.
  All backups are kept in $STATE/backups
  Quit and reopen VS Code and Terminal to see the change.

EOF
