#!/usr/bin/env bash
#
# fix-fusion-ui-renderer.sh
#
# Fixes the Autodesk Fusion 360 (on Linux, via the cryinkfly Wine installer)
# UI-crash where the Qt/Chromium interface loses its GPU context on startup.
# Symptoms in the launch log: thousands of lines of
#   "Failed to make current since context is marked as lost"
#   "CreateSharedImage failed" / DXGI shared handle 80004001
#   WebSocket close 1006  -> Fusion hangs/crashes.
#
# Root cause: Fusion has TWO graphics settings in NMachineSpecificOptions.xml:
#   * driverOptionId      -> the 3D modeling canvas (already VirtualDeviceDx11/DXVK, fine)
#   * graphicsApiOptionId -> the Qt user interface  (default OpenGL, this is what crashes)
# This script only changes the UI one (graphicsApiOptionId). The 3D canvas is untouched.
#
# Usage:
#   ./fix-fusion-ui-renderer.sh            # sets UI renderer to Software (most crash-proof)
#   ./fix-fusion-ui-renderer.sh Direct3D11 # via DXVK, faster UI, usually stable
#   ./fix-fusion-ui-renderer.sh OpenGL     # back to the crashing default (revert)
#   ./fix-fusion-ui-renderer.sh Software /custom/path/to/.autodesk_fusion
#
# A timestamped backup of every changed file is written next to it as *.bak-<renderer>.
#
set -euo pipefail

RENDERER="${1:-Software}"
FUSION_ROOT="${2:-$HOME/.autodesk_fusion}"

case "$RENDERER" in
  Software|Direct3D11|OpenGL|Vulkan) ;;
  *) echo "Ongeldige renderer '$RENDERER'. Kies: Software | Direct3D11 | OpenGL | Vulkan" >&2; exit 1 ;;
esac

PREFIX="$FUSION_ROOT/wineprefixes/default"
if [ ! -d "$PREFIX" ]; then
  echo "Kon de wineprefix niet vinden: $PREFIX" >&2
  echo "Geef eventueel het pad naar je .autodesk_fusion map mee als 2e argument." >&2
  exit 1
fi

# Fusion moet dicht zijn, anders overschrijft het je wijziging bij afsluiten.
if pgrep -fi "Fusion360.exe" >/dev/null 2>&1; then
  echo "Fusion 360 draait nog. Sluit het eerst af en start dit script opnieuw." >&2
  exit 1
fi

echo "Renderer instellen op: $RENDERER"
echo "Wineprefix:            $PREFIX"

RENDERER="$RENDERER" PREFIX="$PREFIX" python3 - <<'PY'
import os, re, shutil

renderer = os.environ["RENDERER"]
prefix   = os.environ["PREFIX"]

# Fusion bewaart deze config onder verschillende AppData-locaties; we passen ze allemaal aan.
base_candidates = []
for user_dir in os.listdir(os.path.join(prefix, "drive_c", "users")):
    base_candidates.append(os.path.join(prefix, "drive_c", "users", user_dir, "AppData"))

files = []
for base in base_candidates:
    if not os.path.isdir(base):
        continue
    for root, _, fs in os.walk(base):
        if "NMachineSpecificOptions.xml" in fs:
            files.append(os.path.join(root, "NMachineSpecificOptions.xml"))

# Vervang alleen de UI-renderer (graphicsApiOptionId), niet de 3D-driver (driverOptionId).
pat = re.compile(r'(graphicsApiOptionId[^>]*?Value=")(?:Software|Direct3D11|OpenGL|Vulkan)(")')

changed = 0
for f in sorted(set(files)):
    raw = open(f, "rb").read()
    enc = "utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
    text = raw.decode(enc, errors="replace")
    if "graphicsApiOptionId" not in text:
        continue
    new, n = pat.subn(r"\1" + renderer + r"\2", text)
    if n and new != text:
        shutil.copy2(f, f + ".bak-" + renderer)
        open(f, "wb").write(new.encode(enc))
        changed += 1

print(f"\nBestanden gevonden: {len(set(files))} | gewijzigd: {changed}\n")
print("Huidige stand:")
for f in sorted(set(files)):
    raw = open(f, "rb").read()
    enc = "utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
    text = raw.decode(enc, errors="replace")
    d = re.search(r'driverOptionId[^>]*?Value="([^"]*)"', text)
    g = re.search(r'graphicsApiOptionId[^>]*?Value="([^"]*)"', text)
    print(f"  3D={ (d.group(1) if d else '?'):<18} UI={ g.group(1) if g else '?'}")
PY

echo
echo "Klaar. Start Fusion 360 en controleer of de UI-crash weg is."
