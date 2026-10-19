#!/usr/bin/env bash
#
# fix-fusion-dxvk.sh
#
# Makes Fusion's 3D canvas fast on Intel GPUs by switching it from Wine's
# OpenGL path to DXVK (Direct3D 11 -> Vulkan).
#
# Problem: the wizard picks the "OpenGL fallback" for every Intel GPU. It then
# skips DXVK entirely and writes driverOptionId=VirtualDeviceGLCore into
# NMachineSpecificOptions.xml. The canvas ends up on Wine's OpenGL path, which is
# noticeably slower. Any Intel GPU with a Mesa Vulkan driver (intel_icd) can run
# DXVK just fine.
#
# Fix: do what the wizard does for NVIDIA/AMD:
#   * winetricks -q dxvk
#   * the wizard's DXVK.reg overrides (d3d11/dxgi/d3d10core native, d3d9 builtin)
#   * driverOptionId -> VirtualDeviceDx11 in every NMachineSpecificOptions.xml
# Backups: user.reg and the d3d DLLs in <root>/backup-voor-dxvk/, every config
# as *.bak-voor-dxvk.
#
# Usage (Fusion must be closed):
#   ./fix-fusion-dxvk.sh                 # switch to DXVK
#   ./fix-fusion-dxvk.sh --revert        # back to OpenGL (VirtualDeviceGLCore)
#   ./fix-fusion-dxvk.sh [--revert] /pad/naar/.autodesk_fusion
#
# Tested: Intel Iris Plus 655, Mesa, Ubuntu 26.04, Fusion 2702, DXVK 3.1.1.
# Safe to run more than once.

set -euo pipefail

ACTION="apply"
if [ "${1:-}" = "--revert" ]; then
    ACTION="revert"
    shift
fi
FUSION_ROOT="${1:-$HOME/.autodesk_fusion}"
PREFIX="$FUSION_ROOT/wineprefixes/default"
WINETRICKS="$FUSION_ROOT/bin/winetricks"
BACKUP_DIR="$FUSION_ROOT/backup-voor-dxvk"

# Zelfde Wine als de launcher: de Wine-fix build als die er is, anders systeem-Wine.
if [ -x "$HOME/fusion-wine-build/bin/wine" ]; then
    WINE="$HOME/fusion-wine-build/bin/wine"
    WINESERVER="$HOME/fusion-wine-build/bin/wineserver"
else
    WINE="wine"
    WINESERVER="wineserver"
fi
export WINEPREFIX="$PREFIX" WINE WINESERVER WINEDEBUG=-all

if [ ! -d "$PREFIX/drive_c" ]; then
    echo "Kon de wineprefix niet vinden: $PREFIX" >&2
    exit 1
fi

# Fusion moet dicht zijn, anders overschrijft het de config bij afsluiten.
if pgrep -fi "Fusion360.exe" >/dev/null 2>&1; then
    echo "Fusion 360 draait nog. Sluit het eerst af en start dit script opnieuw." >&2
    exit 1
fi

set_driver() {
    DRIVER="$1" PREFIX="$PREFIX" python3 - <<'PY'
import os, re, shutil

driver = os.environ["DRIVER"]
users_root = os.path.join(os.environ["PREFIX"], "drive_c", "users")
pat = re.compile(r'(driverOptionId[^>]*?Value=")[^"]*(")')

for user_dir in os.listdir(users_root):
    for root, _, fs in os.walk(os.path.join(users_root, user_dir)):
        # Filelock/ bevat een kopie die Fusion zelf beheert; niet aankomen.
        if "NMachineSpecificOptions.xml" not in fs or "Filelock" in root:
            continue
        f = os.path.join(root, "NMachineSpecificOptions.xml")
        raw = open(f, "rb").read()
        enc = "utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
        text = raw.decode(enc)
        new, n = pat.subn(r"\g<1>" + driver + r"\g<2>", text)
        if n and new != text:
            if not os.path.exists(f + ".bak-voor-dxvk"):
                shutil.copy2(f, f + ".bak-voor-dxvk")
            open(f, "wb").write(new.encode(enc))
            print(f"fix  3D-driver -> {driver}: {f}")
        elif n:
            print(f"ok   3D-driver staat al op {driver}: {f}")
PY
}

if [ "$ACTION" = "revert" ]; then
    for dll in d3d11 dxgi d3d10core d3d9; do
        "$WINE" reg delete 'HKCU\Software\Wine\DllOverrides' /v "*$dll" /f >/dev/null 2>&1 || true
    done
    "$WINESERVER" -w
    set_driver VirtualDeviceGLCore
    echo
    echo "Terug op OpenGL. De DXVK-DLL's blijven in system32 staan, maar worden zonder"
    echo "override niet meer geladen. Originelen: $BACKUP_DIR"
    exit 0
fi

if [ ! -x "$WINETRICKS" ]; then
    echo "winetricks niet gevonden: $WINETRICKS (draai eerst de wizard)" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
[ -e "$BACKUP_DIR/user.reg" ] || cp -p "$PREFIX/user.reg" "$BACKUP_DIR/"
for dll in d3d11 dxgi d3d10core d3d9; do
    src="$PREFIX/drive_c/windows/system32/$dll.dll"
    [ -e "$BACKUP_DIR/$dll.dll" ] || [ ! -e "$src" ] || cp -p "$src" "$BACKUP_DIR/"
done

echo "── DXVK installeren in de prefix ──"
"$WINETRICKS" -q dxvk

# Overrides van de wizard (DXVK.reg): d3d9 blijft builtin, de rest native (DXVK).
for dll in d3d11 dxgi d3d10core; do
    "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v "*$dll" /t REG_SZ /d native /f >/dev/null
done
"$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v '*d3d9' /t REG_SZ /d builtin /f >/dev/null
"$WINESERVER" -w

set_driver VirtualDeviceDx11

echo
echo "Klaar. Start Fusion: het 3D-canvas loopt nu via DXVK (Vulkan)."
echo "Terug naar OpenGL: $0 --revert"
