#!/usr/bin/env bash
#
# fix-fusion-webengine-gpu.sh
#
# Fixes the "Not Responding" hang right after logging in to Fusion.
#
# Symptom in the launch log, dozens of times per second:
#   ERROR:shared_context_state.cc ... Failed to make current since context is marked as lost
#   ERROR:d3d_image_backing_factory.cc ... Unable to create shared handle for DXGIResource 80004001
#
# Root cause: Fusion draws its interface with QtWebEngine (embedded Chromium).
# Under Wine, Chromium's GPU path loses its context and the UI stops responding.
# On Fusion 2702 the graphicsApiOptionId setting (fix-fusion-ui-renderer.sh) does
# not help -- it no longer has a Software value, and D3D11 still hangs.
#
# Fix: start QtWebEngine without GPU via QTWEBENGINE_CHROMIUM_FLAGS. Only the
# interface is drawn by the CPU; the 3D canvas keeps its own GPU driver.
# Setting it in HKCU\Environment does NOT work (Fusion ignores it), so it has to
# be in the environment of the launcher. This script adds one export line there.
#
# Usage:
#   ./fix-fusion-webengine-gpu.sh            # add the flags to the launcher
#   ./fix-fusion-webengine-gpu.sh --revert   # remove them again
#   ./fix-fusion-webengine-gpu.sh [--revert] /pad/naar/.autodesk_fusion
#
# Caveat: re-running the wizard may download a fresh launcher and undo this.
# Just run this script again afterwards. Safe to run more than once.

set -euo pipefail

ACTION="apply"
if [ "${1:-}" = "--revert" ]; then
    ACTION="revert"
    shift
fi
FUSION_ROOT="${1:-$HOME/.autodesk_fusion}"
LAUNCHER="$FUSION_ROOT/bin/autodesk_fusion_launcher.sh"
FLAGS="--disable-gpu --disable-gpu-compositing"
MARKER="# fix-fusion-webengine-gpu.sh"

if [ ! -f "$LAUNCHER" ]; then
    echo "Launcher niet gevonden: $LAUNCHER" >&2
    echo "Geef eventueel het pad naar je .autodesk_fusion map mee." >&2
    exit 1
fi

if [ "$ACTION" = "revert" ]; then
    if grep -q "$MARKER" "$LAUNCHER"; then
        sed -i "/$MARKER/,+1d" "$LAUNCHER"
        echo "fix  QtWebEngine-vlaggen uit $LAUNCHER gehaald"
    else
        echo "ok   $LAUNCHER bevat de vlaggen niet"
    fi
    exit 0
fi

if grep -q "$MARKER" "$LAUNCHER"; then
    echo "ok   $LAUNCHER zet de vlaggen al"
    exit 0
fi

# Direct na de shebang, zodat alles wat de launcher start de variabele erft.
sed -i "1a $MARKER: Fusion-interface (QtWebEngine) zonder GPU, tegen de hang na inloggen.\nexport QTWEBENGINE_CHROMIUM_FLAGS=\"$FLAGS\"" "$LAUNCHER"
bash -n "$LAUNCHER"
echo "fix  $LAUNCHER start QtWebEngine nu met: $FLAGS"
