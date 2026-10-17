#!/bin/bash
# One-line installer for macOS:
#   curl -fsSL https://github.com/GamerNishant/nishants-dsa-setup/releases/latest/download/install-mac.sh | bash
# To restore your previous setup instead, add:  -s -- --restore
set -e
URL="https://github.com/GamerNishant/nishants-dsa-setup/releases/latest/download/NishantsDSASetup-mac.zip"
DEST="$HOME/.nishant-dsa/app"
TMP="$(mktemp -d)"
echo "Downloading Nishant's DSA Setup..."
curl -fsSL -o "$TMP/setup.zip" "$URL"
rm -rf "$DEST" && mkdir -p "$DEST"
ditto -x -k "$TMP/setup.zip" "$DEST"
rm -rf "$TMP"
if [ "${1:-}" = "--restore" ]; then
    exec /bin/bash "$DEST/files/mac/restore.sh" < /dev/tty
else
    exec /bin/bash "$DEST/files/mac/setup.sh" < /dev/tty
fi
