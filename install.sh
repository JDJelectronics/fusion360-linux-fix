#!/usr/bin/env bash
#
# install.sh -- Autodesk Fusion 360 op Linux, in één keer, met de fixes er direct in.
#
# Draait de setup wizard van cryinkfly (ongewijzigd, meegeleverd in vendor/) en past
# daarna de twee fixes toe die deze repo beschrijft:
#
#   1. Desktop en Documents terugkoppelen aan je echte home-mappen.
#      De wizard draait 'winetricks -q sandbox', wat Wine's desktop-integratie sloopt.
#      Zonder deze fix verdwijnen je STL-exports in ~/.autodesk_fusion/downloads/.
#
#   2. De UI-renderer op Software zetten (tegen de opstart-crash).
#      Dit kan pas NA de eerste start van Fusion: het configbestand bestaat dan pas.
#      Het script vertelt je aan het eind wat je moet doen.
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

# --- 1. De wizard -----------------------------------------------------------
"$INSTALLER" "$MODE" "$FUSION_ROOT"

# --- 2. Home-mappen terugkoppelen -------------------------------------------
# Kan direct: de wineprefix bestaat nu.
echo
echo "── Desktop en Documents koppelen aan je echte home-mappen ──"
"$HERE/fix-fusion-home-folders.sh" "$FUSION_ROOT/wineprefixes/default"

# --- 3. UI-renderer ---------------------------------------------------------
# Kan NIET direct: NMachineSpecificOptions.xml wordt pas bij de eerste start van
# Fusion aangemaakt. Daarom hier alleen instructies, geen loze poging.
cat <<EOF

════════════════════════════════════════════════════════
 Installatie klaar. Nog één stap.
════════════════════════════════════════════════════════

De UI-renderer-fix kan pas NA de eerste start van Fusion: het configbestand
dat aangepast moet worden, bestaat nu nog niet.

  1. Start Fusion 360 (menu, of ~/.autodesk_fusion/bin/autodesk_fusion_launcher.sh)
  2. Log in en sluit Fusion daarna helemaal af
  3. Draai:

       $HERE/fix-fusion-ui-renderer.sh

Crasht Fusion al bij die eerste start, dan is dat precies de bug die stap 3
oplost -- sluit hem af (of kill hem) en draai het script alsnog.

EOF
