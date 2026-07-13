#!/usr/bin/env bash
#
# Repairs an EXISTING Autodesk Fusion Wine prefix that was created by the
# cryinkfly setup wizard.
#
# Problem: the wizard runs `winetricks sandbox`, which strips Wine's desktop
# integration. Desktop and Documents end up as empty directories inside the
# prefix with no connection to your real home folders. Downloads, meanwhile, is
# pointed at the wizard's own payload directory -- which is why STL exports
# land next to a 1.5 GB FusionClientInstaller.exe.
#
# This script re-links Desktop, Documents AND Downloads to your real home folders.
#
# Downloads matters most: Fusion's export dialog opens there by default, so
# without this you have to navigate away from it on every single export.
# Repointing it is safe -- the wizard only needs that link *during* the install,
# to run its own .exe payloads (autodesk_fusion_installer.sh:1671). Once Fusion
# is installed, nothing reads it again.
#
# Caveat: re-running the wizard (e.g. to update Fusion) recreates its own
# Downloads link and undoes this. Just run this script again afterwards.
# Run this script AFTER the wizard, never during.
#
# Safe to run more than once.

set -euo pipefail

PREFIX="${1:-$HOME/.autodesk_fusion/wineprefixes/default}"
WIN_USER_DIR="$PREFIX/drive_c/users/$USER"

if [ ! -d "$WIN_USER_DIR" ]; then
    echo "No Wine user directory at: $WIN_USER_DIR"
    echo "Pass the prefix path as an argument, e.g.:"
    echo "  $0 ~/.autodesk_fusion/wineprefixes/default"
    exit 1
fi

REAL_DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
REAL_DOCUMENTS="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")"
REAL_DOWNLOADS="$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads")"

for pair in "Desktop:$REAL_DESKTOP" "Documents:$REAL_DOCUMENTS" "Downloads:$REAL_DOWNLOADS"; do
    name="${pair%%:*}"
    target="${pair#*:}"
    link="$WIN_USER_DIR/$name"

    if [ ! -d "$target" ]; then
        echo "skip $name: $target does not exist"
        continue
    fi

    if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$(readlink -f "$target")" ]; then
        echo "ok   $name -> $target (already linked)"
        continue
    fi

    [ -L "$link" ] && rm -f "$link"

    # rmdir refuses on a non-empty directory. If you had files in the prefix's
    # Desktop, we stop rather than delete them.
    if [ -d "$link" ] && ! rmdir "$link" 2>/dev/null; then
        echo "SKIP $name: $link is not empty. Move its contents out, then re-run."
        continue
    fi

    ln -s "$target" "$link"
    echo "fix  $name -> $target"
done

echo
echo "Done. Fusion's export dialog opens in Downloads by default, which now points"
echo "at your real ~/Downloads -- so exports land where you can find them without"
echo "changing anything. Desktop and Documents work too."
