#!/usr/bin/env bash
#
# fix-wine-build-prompt.sh
#
# Removes the "outdated version" prompt from the prebuilt Fusion Wine build
# (~/fusion-wine-build, used by the wizard's --install-fix mode).
#
# Problem: bin/wineboot in that build is a wrapper that, on `wineboot --init`, asks
#   "You are using an outdated version. Use the up-to-date version? [Y/n]"
# The default is Y. Pressing Enter opens a web page and runs `kill $PPID` -- which
# kills the setup wizard halfway through the install. The wizard calls
# `wineboot --init` for every fresh prefix, so this hits every install.
#
# Fix: replace the wrapper with a plain pass-through to wineboot-bin. That is
# exactly what answering "n" does, minus the chance to get it wrong.
# The original wrapper is kept next to it as wineboot.orig-met-updatevraag.
#
# Usage:
#   ./fix-wine-build-prompt.sh                    # ~/fusion-wine-build
#   ./fix-wine-build-prompt.sh /pad/naar/build    # other location
#
# Safe to run more than once.

set -euo pipefail

BUILD_DIR="${1:-$HOME/fusion-wine-build}"
WRAPPER="$BUILD_DIR/bin/wineboot"
BACKUP="$WRAPPER.orig-met-updatevraag"

if [ ! -x "$BUILD_DIR/bin/wineboot-bin" ]; then
    echo "Geen Fusion Wine-build gevonden in: $BUILD_DIR" >&2
    echo "(bin/wineboot-bin ontbreekt)" >&2
    exit 1
fi

if ! grep -q 'outdated version' "$WRAPPER" 2>/dev/null; then
    echo "ok   $WRAPPER heeft geen update-vraag (al gefixt)"
    exit 0
fi

[ -e "$BACKUP" ] || cp -p "$WRAPPER" "$BACKUP"

cat > "$WRAPPER" <<'EOF'
#!/bin/bash
# Update-vraag verwijderd door fix-wine-build-prompt.sh: Enter (= Y) schoot de
# installer af. Origineel: wineboot.orig-met-updatevraag
exec "$(dirname "$0")/wineboot-bin" "$@"
EOF
chmod +x "$WRAPPER"

echo "fix  update-vraag uit $WRAPPER gehaald (origineel: $BACKUP)"
