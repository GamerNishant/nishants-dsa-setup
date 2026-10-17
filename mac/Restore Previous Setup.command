#!/bin/bash
# Double-click to undo Nishant's DSA Setup and get your previous setup back.
cd "$(dirname "$0")" && /bin/bash "./files/mac/restore.sh"
echo; read -r -p "  Press Enter to close this window." _
