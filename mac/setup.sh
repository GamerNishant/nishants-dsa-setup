#!/bin/bash
# Nishant's DSA Setup for macOS.
# Installs and configures VS Code, GCC (g++), fonts, the terminal prompt and
# CPH Plus. Everything it changes is recorded so restore.sh can undo it.
# Written for the bash 3.2 that ships with macOS.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$(cd "$HERE/../payload" && pwd)"
UNATTENDED="${NISHANT_DSA_UNATTENDED:-0}"
# Set to 1 to leave the Terminal app alone (used by automated tests).
SKIP_TERMINAL_APP="${NISHANT_DSA_SKIP_TERMINAL_APP:-0}"
[ "${1:-}" = "--yes" ] && UNATTENDED=1

ROOT="$HOME/.nishant-dsa"
STATE="$ROOT/state"
BIN="$ROOT/bin"
THEME="$ROOT/nishant.omp.json"
MANIFEST="$STATE/manifest.json"
LOG="$ROOT/setup.log"
CODE_USER="$HOME/Library/Application Support/Code/User"
SETTINGS="$CODE_USER/settings.json"
SNIPPETS="$CODE_USER/snippets/nishant-dsa.code-snippets"
OMP_VERSION="$(sed -n 's/.*"ohMyPoshVersion": *"\([^"]*\)".*/\1/p' "$PAYLOAD/config/versions.json")"
MIN_GCC=9
JSONEDIT() { osascript -l JavaScript "$HERE/jsonedit.js" "$@"; }

mkdir -p "$STATE" "$BIN"
FAILURES=""

log()  { printf '%s  %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG"; }
step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; log "STEP $*"; }
ok()   { printf '    \033[32m[ok]\033[0m   %s\n' "$*"; log "OK $*"; }
skip() { printf '    \033[90m[skip] %s\033[0m\n' "$*"; log "SKIP $*"; }
info() { printf '    %s\n' "$*"; log "INFO $*"; }
warn() { printf '    \033[33m[warn]\033[0m %s\n' "$*"; log "WARN $*"; }
fail() { printf '    \033[31m[fail]\033[0m %s\n' "$*"; log "FAIL $*"; FAILURES="$FAILURES, $1"; }

# ask "question" default(y/n)  -> returns 0 for yes
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

flag_set()  { touch "$STATE/$1"; }
flag_has()  { [ -f "$STATE/$1" ]; }
list_add()  { grep -qxF "$2" "$STATE/$1" 2>/dev/null || printf '%s\n' "$2" >> "$STATE/$1"; }

# ------------------------------------------------------------------ intro
clear 2>/dev/null
printf '\n\033[35m  =============================================\n'
printf "        Nishant's DSA Setup (macOS)\n"
printf '  =============================================\033[0m\n\n'
cat <<'EOF'
  This will set up a complete C++ / DSA environment:
    - Homebrew and Visual Studio Code (if missing)
    - GCC g++ compiler (needed for #include <bits/stdc++.h>)
    - Fonts: MesloLGM Nerd Font, Hack, Fira Code
    - Powerline terminal prompt (oh-my-posh) for zsh
    - VS Code extensions: C/C++, Code Runner, Auto Hide, CPH Plus
    - Editor theme, fonts and C++ snippets (cpts / cpnts)

  Nothing you already have is deleted. Every file is backed up first and
  you can undo everything later with "Restore Previous Setup".

EOF
if [ -f "$MANIFEST" ]; then
    printf '  \033[33mThis setup has been run on this Mac before. Running it again updates\n'
    printf '  everything; your original settings are still saved for restore.\033[0m\n\n'
fi
ask "Start the setup?" y || { echo "  Cancelled. Nothing was changed."; exit 0; }
log "=== setup started (unattended=$UNATTENDED) ==="

# ------------------------------------------------------------------ 1. backup
step "[1/8] Backing up your current settings"
BACKUP="$STATE/backups/$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$BACKUP"
n=0
for f in "$SETTINGS" "$CODE_USER/keybindings.json" "$HOME/.zshrc" "$HOME/.bash_profile"; do
    if [ -f "$f" ]; then
        n=$((n + 1))
        cp "$f" "$BACKUP/$(printf '%02d' $n)-$(basename "$f")"
        echo "$(printf '%02d' $n)-$(basename "$f") <= $f" >> "$BACKUP/index.txt"
    fi
done
[ "$SKIP_TERMINAL_APP" = "1" ] || osascript -e 'tell application "Terminal" to get {name, font name, font size} of default settings' > "$BACKUP/terminal-font.txt" 2>/dev/null
ok "Backup saved to $BACKUP"

# ------------------------------------------------------------------ 2. Homebrew
step "[2/8] Homebrew (package manager)"
find_brew() {
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && { echo "$b"; return; }; done
    command -v brew 2>/dev/null
}
BREW="$(find_brew)"
if [ -n "$BREW" ]; then
    skip "already installed ($BREW)"
else
    info "Installing Homebrew. It will ask for your Mac password (typing is invisible)."
    if [ "$UNATTENDED" = "1" ]; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
    fi
    BREW="$(find_brew)"
    if [ -n "$BREW" ]; then flag_set installed-brew; ok "Homebrew installed"; else fail "Homebrew"; fi
fi
[ -n "$BREW" ] && eval "$("$BREW" shellenv)"

# ------------------------------------------------------------------ 3. VS Code
step "[3/8] Visual Studio Code"
find_code() {
    for app in "/Applications/Visual Studio Code.app" "$HOME/Applications/Visual Studio Code.app"; do
        [ -x "$app/Contents/Resources/app/bin/code" ] && { echo "$app/Contents/Resources/app/bin/code"; return; }
    done
}
CODE="$(find_code)"
if [ -n "$CODE" ]; then
    skip "already installed"
elif [ -n "$BREW" ]; then
    info "Installing VS Code..."
    if "$BREW" install --cask visual-studio-code >> "$LOG" 2>&1; then
        CODE="$(find_code)"; flag_set installed-vscode; ok "VS Code installed"
    else
        fail "VS Code"; info "Install it from https://code.visualstudio.com and run this setup again."
    fi
else
    fail "VS Code"
fi

# ------------------------------------------------------------------ 4. compiler
step "[4/8] C++ compiler (g++)"
test_gpp() {  # prints the version and returns 0 if it compiles bits/stdc++.h
    local gpp="$1" dir
    dir="$(mktemp -d)"
    printf '#include <bits/stdc++.h>\nusing namespace std;\nint main(){vector<int> v{3,1,2};sort(v.begin(),v.end());cout<<v[0]<<v[1]<<v[2];}\n' > "$dir/t.cpp"
    local version major out
    version="$("$gpp" -dumpfullversion -dumpversion 2>/dev/null | head -n1)"
    major="${version%%.*}"
    if "$gpp" "$dir/t.cpp" -o "$dir/t" >/dev/null 2>&1; then out="$("$dir/t")"; fi
    rm -rf "$dir"
    echo "$version"
    [ "${out:-}" = "123" ] && [ "${major:-0}" -ge "$MIN_GCC" ] 2>/dev/null
}
# Plain "g++" on a Mac is Apple clang, which has no bits/stdc++.h, so look for
# GNU g++-NN binaries (newest first).
find_gpp() {
    local dirs="" d
    [ -n "$BREW" ] && dirs="$("$BREW" --prefix)/bin"
    for d in $dirs /opt/homebrew/bin /usr/local/bin; do
        ls "$d"/g++-[0-9]* 2>/dev/null
    done | grep -E '/g\+\+-[0-9]+$' | awk -F- '{print $NF" "$0}' | sort -rn | cut -d' ' -f2- | awk '!seen[$0]++'
}
GPP=""
for cand in $(find_gpp); do
    if v="$(test_gpp "$cand")"; then GPP="$cand"; skip "using g++ $v ($cand)"; break; fi
done
if [ -z "$GPP" ] && [ -n "$BREW" ]; then
    info "Installing GCC with Homebrew (a few minutes)..."
    if "$BREW" install gcc >> "$LOG" 2>&1; then
        flag_set installed-gcc
        for cand in $(find_gpp); do
            if v="$(test_gpp "$cand")"; then GPP="$cand"; ok "g++ $v installed ($cand)"; break; fi
        done
    fi
fi
[ -z "$GPP" ] && fail "g++ compiler"
GCC=""
[ -n "$GPP" ] && GCC="$(dirname "$GPP")/gcc-${GPP##*-}" && [ -x "$GCC" ] || GCC=""

# ------------------------------------------------------------------ 5. fonts
step "[5/8] Fonts"
mkdir -p "$HOME/Library/Fonts"
newfonts=0
for font in "$PAYLOAD"/fonts/*.ttf; do
    name="$(basename "$font")"
    if [ -f "$HOME/Library/Fonts/$name" ] || [ -f "/Library/Fonts/$name" ]; then continue; fi
    cp "$font" "$HOME/Library/Fonts/$name" && list_add fonts.txt "$HOME/Library/Fonts/$name" && newfonts=$((newfonts + 1))
done
[ $newfonts -gt 0 ] && ok "$newfonts font files installed" || skip "all fonts already installed"

# ------------------------------------------------------------------ 6. terminal prompt
step "[6/8] Terminal prompt (oh-my-posh)"
OMP="$BIN/oh-my-posh"
have=""; [ -x "$OMP" ] && have="$("$OMP" version 2>/dev/null)"
if [ "$have" = "${OMP_VERSION#v}" ]; then
    skip "oh-my-posh $have already installed"
else
    arch="amd64"; [ "$(uname -m)" = "arm64" ] && arch="arm64"
    if curl -fsSL -o "$OMP.tmp" "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$OMP_VERSION/posh-darwin-$arch"; then
        mv "$OMP.tmp" "$OMP" && chmod +x "$OMP" && flag_set installed-omp && ok "oh-my-posh ${OMP_VERSION#v} installed"
    else
        rm -f "$OMP.tmp"; fail "oh-my-posh"
    fi
fi
cp "$PAYLOAD/config/nishant.omp.json" "$THEME"

BLOCK="$STATE/block.tmp"
add_prompt() {  # add_prompt <rc file> <shell name>
    {
        echo "# >>> Nishant's DSA Setup >>>"
        echo "if [ -x \"\$HOME/.nishant-dsa/bin/oh-my-posh\" ]; then"
        echo "  eval \"\$(\"\$HOME/.nishant-dsa/bin/oh-my-posh\" init $2 --config \"\$HOME/.nishant-dsa/nishant.omp.json\")\""
        echo "fi"
        echo "# <<< Nishant's DSA Setup <<<"
    } > "$BLOCK"
    case "$(JSONEDIT addblock "$1" "$BLOCK" "$MANIFEST")" in
        added) ok "prompt enabled in $1" ;;
        present) skip "prompt already enabled in $1" ;;
        *) warn "could not update $1" ;;
    esac
}
add_prompt "$HOME/.zshrc" zsh
case "${SHELL:-}" in */bash) add_prompt "$HOME/.bash_profile" bash ;; esac
rm -f "$BLOCK"
if grep -qs 'powerlevel10k' "$HOME/.zshrc"; then
    warn "You use powerlevel10k; it may draw its own prompt instead of this one."
fi

# Terminal.app font (only the default profile, previous value saved for restore)
if [ "$SKIP_TERMINAL_APP" = "1" ]; then
    skip "Terminal app font (skipped)"
else
if [ ! -f "$STATE/terminal-font.prev" ]; then
    osascript -e 'tell application "Terminal" to get (font name of default settings) & "|" & (font size of default settings)' > "$STATE/terminal-font.prev" 2>/dev/null || rm -f "$STATE/terminal-font.prev"
fi
if osascript -e 'tell application "Terminal" to set font name of default settings to "MesloLGMNerdFont-Regular"' \
             -e 'tell application "Terminal" to set font size of default settings to 12' >/dev/null 2>&1; then
    ok "Terminal app font set to MesloLGM Nerd Font"
else
    warn "Could not set the Terminal app font (allow the automation prompt, or set it in Terminal > Settings)"
fi
fi

# ------------------------------------------------------------------ 7. extensions
step "[7/8] VS Code extensions"
if [ -z "$CODE" ]; then
    skip "VS Code is not available"
else
    installed_ext="$("$CODE" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    has_ext() { printf '%s\n' "$installed_ext" | grep -qxF "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"; }
    for ext in $(sed -n '/"conflictingExtensions"/,/]/p' "$PAYLOAD/config/versions.json" | grep -o '"[^"]*\.[^"]*"' | tr -d '"'); do
        if has_ext "$ext"; then
            "$CODE" --uninstall-extension "$ext" >> "$LOG" 2>&1 && list_add extensions-removed.txt "$ext" && ok "removed $ext (replaced by CPH Plus; your CPH settings still work)"
        fi
    done
    for ext in $(sed -n '/"extensions"/,/]/p' "$PAYLOAD/config/versions.json" | grep -o '"[^"]*\.[^"]*"' | tr -d '"'); do
        if has_ext "$ext"; then skip "$ext already installed"; continue; fi
        if "$CODE" --install-extension "$ext" >> "$LOG" 2>&1; then list_add extensions-added.txt "$ext"; ok "installed $ext"; else fail "$ext"; fi
    done
    had_cph=0; has_ext nishant.cph-plus && had_cph=1
    if "$CODE" --install-extension "$PAYLOAD/extensions/cph-plus.vsix" --force >> "$LOG" 2>&1; then
        [ $had_cph = 0 ] && list_add extensions-added.txt nishant.cph-plus
        ok "installed CPH Plus"
    else
        fail "CPH Plus"
    fi
fi

# ------------------------------------------------------------------ 8. settings
step "[8/8] Editor settings and snippets"
case "$(JSONEDIT vscode "$SETTINGS" "$PAYLOAD/config/vscode-settings.json" "$GPP" "$GCC" "$MANIFEST")" in
    ok) ok "VS Code settings updated" ;;
    unreadable) warn "VS Code settings.json has a syntax error, left it untouched"; FAILURES="$FAILURES, VS Code settings" ;;
    *) fail "VS Code settings" ;;
esac
if [ ! -f "$SNIPPETS" ]; then
    mkdir -p "$(dirname "$SNIPPETS")"
    cp "$PAYLOAD/config/nishant-dsa.code-snippets" "$SNIPPETS" && list_add created-files.txt "$SNIPPETS"
    ok "C++ snippets added (type cpts or cpnts in a .cpp file)"
elif grep -qxF "$SNIPPETS" "$STATE/created-files.txt" 2>/dev/null; then
    cp "$PAYLOAD/config/nishant-dsa.code-snippets" "$SNIPPETS"; skip "C++ snippets already added (updated)"
else
    skip "a snippets file with the same name already exists; left it alone"
fi

# ------------------------------------------------------------------ done
echo
if [ -n "$GPP" ] && v="$(test_gpp "$GPP")"; then ok "Test program compiled and ran with g++ $v"; fi
echo
if [ -z "$FAILURES" ]; then
    printf '  \033[32mAll done!\033[0m\n'
else
    printf '  \033[33mFinished with problems in: %s\033[0m\n' "${FAILURES#, }"
    echo "  Check your internet connection and run the setup again; finished steps are skipped."
fi
cat <<EOF

  Next steps:
    1. Quit VS Code and Terminal completely (Cmd+Q), then open VS Code again.
    2. Open a folder, create a .cpp file, type cpts and press Tab.
    3. Use the CPH panel (Ctrl+Option+B runs test cases).

  To undo everything, run "Restore Previous Setup".
  Log file: $LOG
EOF
log "=== setup finished, failures: ${FAILURES#, } ==="
[ -z "$FAILURES" ]
