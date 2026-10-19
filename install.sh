#!/usr/bin/env bash
#
# install.sh -- Autodesk Fusion 360 op Linux, in één keer, met de fixes er direct in.
#
# Draait de setup wizard van cryinkfly (ongewijzigd, meegeleverd in vendor/) en past
# de fixes toe die deze repo beschrijft:
#
#   0. (alleen --install-fix) De Wine-build vooraf uitpakken en de update-vraag eruit
#      halen. Die vraag ("outdated version? [Y/n]") schiet op Enter de wizard af.
#
#   1. Fusion's interface (QtWebEngine) zonder GPU laten tekenen, tegen de hang
#      ("Not Responding") na het inloggen. Geldt al voor de eerste start vanuit de
#      wizard, en wordt daarna vast in de launcher gezet.
#
#   2. Desktop, Documents en Downloads terugkoppelen aan je echte home-mappen.
#      De wizard draait 'winetricks -q sandbox', wat Wine's desktop-integratie sloopt.
#      Zonder deze fix verdwijnen je STL-exports in ~/.autodesk_fusion/downloads/.
#
#   3. (niet bij --proton) Het 3D-canvas via DXVK in plaats van Wine's OpenGL.
#      De wizard kiest voor Intel altijd OpenGL, en dat is merkbaar trager.
#
# Gebruik:
#   ./install.sh                 # Wine-fix modus (aanbevolen, zoals getest)
#   ./install.sh --install       # standaard systeem-Wine
#   ./install.sh --proton=9.0    # via Proton
#
# Alles gaat naar ~/.autodesk_fusion. Niets buiten je home wordt aangeraakt.

set -euo pipefail

MODE="${1:---install-fix}"
FUSION_ROOT="$HOME/.autodesk_fusion"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$HERE/vendor/autodesk_fusion_installer_2.1.5-Alpha.sh"

case "$MODE" in
  --install|--install-fix|--proton=*) ;;
  *)
    echo "Onbekende modus '$MODE'. Kies: --install-fix | --install | --proton=<versie>" >&2
    exit 1
    ;;
esac

if [ ! -f "$INSTALLER" ]; then
    echo "De meegeleverde installer ontbreekt: $INSTALLER" >&2
    echo "Heb je de repo compleet gekloond?" >&2
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    echo "Draai dit NIET als root. De wizard vraagt zelf om sudo waar nodig." >&2
    exit 1
fi

echo "════════════════════════════════════════════════════════"
echo " Autodesk Fusion 360 installeren"
echo "   modus:        $MODE"
echo "   installatie:  $FUSION_ROOT"
echo "   wizard:       cryinkfly v2.1.5-Alpha (ongewijzigd, MIT)"
echo "════════════════════════════════════════════════════════"
echo
echo "Dit duurt lang (grote downloads) en vraagt onderweg om je sudo-wachtwoord."
read -rp "Doorgaan? [j/N] " ok
case "$ok" in [jJyY]*) ;; *) echo "Afgebroken."; exit 0 ;; esac

# --- 0. Wine-build zonder update-vraag ---------------------------------------
# De wizard pakt de build uit en roept meteen 'wineboot --init' aan, dus er zit geen
# moment tussen om te fixen. Daarom pakken we hem hier vooraf uit; de wizard slaat
# downloaden en uitpakken over zodra bin/wine bestaat. Zelfde URL als de wizard.
WINE_BUILD_DIR="$HOME/fusion-wine-build"
if [ "$MODE" = "--install-fix" ]; then
    if [ ! -x "$WINE_BUILD_DIR/bin/wine" ]; then
        WINE_BUILD_URL="$(grep -o 'https://[^"]*/fusion-wine-build\.tar\.gz' "$INSTALLER" | head -n 1)"
        WINE_BUILD_TAR="$FUSION_ROOT/downloads/fusion-wine-build.tar.gz"
        echo "── Fusion Wine-build downloaden ──"
        mkdir -p "$FUSION_ROOT/downloads"
        [ -f "$WINE_BUILD_TAR" ] || curl -fL "$WINE_BUILD_URL" -o "$WINE_BUILD_TAR"
        tar -xf "$WINE_BUILD_TAR" -C "$HOME"
    fi
    "$HERE/fix-wine-build-prompt.sh" "$WINE_BUILD_DIR"
fi

# --- 1. De wizard -----------------------------------------------------------
# De wizard start Fusion aan het eind zelf op; met deze variabele hangt die eerste
# start ook niet. Stap 3 zet hem daarna vast in de launcher.
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --disable-gpu-compositing"
"$INSTALLER" "$MODE" "$FUSION_ROOT"

# --- 2. Home-mappen terugkoppelen -------------------------------------------
# Kan direct: de wineprefix bestaat nu.
echo
echo "── Desktop, Documents en Downloads koppelen aan je echte home-mappen ──"
"$HERE/fix-fusion-home-folders.sh" "$FUSION_ROOT/wineprefixes/default"

# --- 3. Interface zonder GPU, vast in de launcher -----------------------------
echo
echo "── Fusion-interface zonder GPU (tegen 'Not Responding') ──"
"$HERE/fix-fusion-webengine-gpu.sh" "$FUSION_ROOT"

# --- 4. 3D-canvas via DXVK ---------------------------------------------------
# Kan pas nu: de wizard heeft Fusion aan het eind zelf gestart en is pas klaar als
# Fusion weer dicht is. Bij Proton zit de prefix elders; daar slaan we dit over.
if [[ "$MODE" != --proton* ]]; then
    echo
    echo "── 3D-canvas via DXVK (sneller dan OpenGL) ──"
    "$HERE/fix-fusion-dxvk.sh" "$FUSION_ROOT"
fi

cat <<EOF

════════════════════════════════════════════════════════
 Installatie klaar.
════════════════════════════════════════════════════════

Start Fusion via het menu (Autodesk Fusion) of:

    $FUSION_ROOT/bin/autodesk_fusion_launcher.sh

Gebruik voortaan altijd de launcher: daar staat de fix tegen de hang na het
inloggen in. Het andere menu-item dat Wine zelf aanmaakt, start Fusion zonder.

EOF
