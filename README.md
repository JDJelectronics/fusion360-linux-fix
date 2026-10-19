# Fusion 360 op Linux — installer met fixes

Autodesk Fusion 360 draait via de
[cryinkfly Wine-installer](https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux)
(install root: `~/.autodesk_fusion`). Twee dingen gingen daarbij mis; deze repo lost ze op
en kan Fusion in één keer voor je installeren.

## Installeren (in één keer, mét de fixes)

```bash
git clone https://github.com/JDJelectronics/fusion360-linux-fix.git
cd fusion360-linux-fix
./install.sh
```

Dat draait de setup wizard van cryinkfly (**ongewijzigd**, meegeleverd in `vendor/`, v2.1.5-Alpha,
MIT) en past er alle fixes omheen toe:

1. haalt vooraf de update-vraag uit de Wine-build (anders schiet Enter de wizard af);
2. laat Fusion's interface zonder GPU tekenen (tegen "Not Responding" na het inloggen);
3. koppelt Desktop, Documents en Downloads aan je echte home-mappen.

Daarna is er geen losse stap meer nodig. Start Fusion altijd via de launcher
(menu-item **Autodesk Fusion** of `~/.autodesk_fusion/bin/autodesk_fusion_launcher.sh`).

> **Ubuntu 26.04.** De wizard meldt *"Your Linux distribution and version are not supported"*.
> In `--install-fix`-modus is dat onschuldig: hij gebruikt dan zijn eigen Wine-build, niet die
> van het systeem, en gaat gewoon door.

Andere Wine-modus? `./install.sh --install` of `./install.sh --proton=9.0`.
Standaard is `--install-fix` (de custom Wine-build), want daar is dit op getest.

> **Waarom de installer meegeleverd is en niet gedownload.** De `main`-branch van cryinkfly staat
> op v2.0.7-Alpha, ouder dan de v2.1.5-Alpha waarop dit getest is. Een vaste, meegeleverde kopie
> geeft een reproduceerbare installatie in plaats van "wat er die dag toevallig op main stond".
> Het bestand is niet aangepast; alle fixes worden er ná de installatie overheen gedraaid.

## Fix 1: de installer wordt halverwege afgeschoten

De Wine-build die `--install-fix` downloadt (`~/fusion-wine-build`) heeft een `bin/wineboot`
die bij `wineboot --init` vraagt:

```
You are using an outdated version. Use the up-to-date version? [Y/n]
```

Standaard is **Y**. Enter opent een webpagina en doet `kill $PPID` — dat is de wizard zelf.
Je ziet dan alleen `Terminated` en een half geïnstalleerde prefix.

```bash
./fix-wine-build-prompt.sh
```

vervangt die wrapper door een doorgeefluik naar `wineboot-bin` (hetzelfde als `n` antwoorden);
het origineel blijft staan als `wineboot.orig-met-updatevraag`. Omdat de wizard de build uitpakt
en meteen `wineboot --init` draait, pakt `install.sh` de build **vooraf** uit en fixt hem dan.
De wizard slaat downloaden en uitpakken over zodra `bin/wine` er al staat.

## Fix 2: "Not Responding" na het inloggen (QtWebEngine)

Op Fusion **2702** is dit de fix die werkt. Fusion tekent zijn interface met QtWebEngine
(ingebouwde Chromium); onder Wine verliest die zijn GPU-context en loopt de log vol met
dezelfde fouten als hieronder. De UI-instelling in de config helpt op deze versie niet (zie
de sectie daarna).

```bash
./fix-fusion-webengine-gpu.sh            # zet de vlaggen in de launcher
./fix-fusion-webengine-gpu.sh --revert   # haalt ze weer weg
```

Dat zet in `autodesk_fusion_launcher.sh`:

```bash
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --disable-gpu-compositing"
```

Alleen de interface wordt door de CPU getekend; het 3D-canvas houdt zijn eigen GPU-driver.
In `HKCU\Environment` zetten werkt **niet** — Fusion pikt het daar niet op, het moet in de
omgeving van de launcher. Herinstalleer je via de wizard, draai het script dan opnieuw.

Getest: vóór de fix tientallen `context is marked as lost` per minuut en een hangend venster
direct na het inloggen; erna nul fouten.

## Oudere fix: UI-renderer in de config (Fusion vóór 2702)

> **Geldt niet meer voor Fusion 2702.** Daar heeft `graphicsApiOptionId` de waarden `Automatic`,
> `OpenGL`, `D3D11` en `Metal` (geen `Software` meer), en staat hij in `CompatibilityGroup`.
> Op een verse installatie staat hij er helemaal niet in, dus `fix-fusion-ui-renderer.sh`
> meldt `gewijzigd: 0`. Handmatig `D3D11` zetten verhielp de hang niet. Gebruik fix 2.

Bij het opstarten liep Fusion steeds vast.

### Het probleem

De launch-log liep vol met dezelfde GPU-fout, duizenden keren herhaald:

```
ERROR:shared_context_state.cc ... Failed to make current since context is marked as lost
ERROR:skia_output_surface_impl_on_gpu.cc ... Failed to make current.
ERROR:shared_image_factory.cc ... CreateSharedImage: could not create backing.
ERROR:d3d_image_backing_factory.cc ... Unable to create shared handle for DXGIResource 80004001
... WebSocket close 1006  -> hang/crash
```

Dit zijn allemaal fouten van de **interface-laag (Qt/Chromium)**, niet van het 3D-modelleren.

### De oorzaak

Fusion heeft twee losse grafische instellingen in `NMachineSpecificOptions.xml`:

| Instelling | Regelt | Standaard | Probleem? |
|---|---|---|---|
| `driverOptionId` | het **3D-canvas** | `VirtualDeviceDx11` (→ DXVK) | nee, prima |
| `graphicsApiOptionId` | de **Qt-interface** | `OpenGL` | **ja — dit crasht** |

Zelfs in DXVK-modus zet de cryinkfly-installer de UI standaard op OpenGL, en dát verliest
zijn GPU-context. Het 3D-canvas stond al goed op Dx11/DXVK.

### De oplossing

De UI-renderer omzetten van `OpenGL` naar iets stabielers. Het 3D-canvas blijft
GPU-versneld (Dx11/DXVK), dus tekenwerk wordt er niet trager van.

- **`Software`** — UI door de CPU getekend. Meest crash-bestendig. UI iets minder vloeiend. *(momenteel ingesteld)*
- **`Direct3D11`** — UI via DXVK→Vulkan. Sneller, meestal stabiel.

### Gebruik

```bash
# Fusion eerst helemaal afsluiten, daarna:
./fix-fusion-ui-renderer.sh              # -> Software (aanbevolen, meest zeker)
./fix-fusion-ui-renderer.sh Direct3D11   # snellere UI proberen
./fix-fusion-ui-renderer.sh OpenGL       # terug naar de standaard (revert)
```

Het script:
- doorzoekt de **hele** gebruikersmap in de wineprefix naar `NMachineSpecificOptions.xml`;
- past **alleen** de UI-renderer aan (het 3D-canvas blijft ongemoeid);
- maakt van elk gewijzigd bestand eerst een backup (`*.bak-<renderer>`);
- weigert te draaien zolang Fusion nog open is.

Andere install-locatie? Geef het pad mee als 2e argument:
`./fix-fusion-ui-renderer.sh Software /pad/naar/.autodesk_fusion`

> **Eerdere versie miste een bestand.** Tot juli 2026 keek het script alleen in `AppData/`.
> Fusion bewaart óók een config onder `Application Data/` — normaal een symlink naar
> `AppData/Roaming`, maar `winetricks sandbox` sloopt die symlink, waarna Fusion er een
> echte map van maakt. Dat bestand bleef daardoor op de crashende `OpenGL`-waarde staan.
> Draai het script opnieuw als je van een oudere versie komt.

## Fix 3: Desktop, Documents en Downloads komen niet in je home terecht

Zelfde oorzaak, ander gevolg. `winetricks -q sandbox` verbreekt Wine's desktop-integratie:
`Desktop` en `Documents` worden lege mappen *binnen* het prefix, los van je echte home.
De installer herstelt daarna alleen `Downloads` — en wijst die naar zijn **eigen** installermap:

```bash
ln -s "$SELECTED_DIRECTORY/downloads" "$WIN_DOWNLOADS_DIRECTORY"
```

Exporteer je een STL, dan opent de dialoog in Downloads en belandt je bestand in
`~/.autodesk_fusion/downloads/` — tussen de `FusionClientInstaller.exe` van 1,5 GB. In je
bestandsbeheerder zie je het nooit terug.

```bash
./fix-fusion-home-folders.sh
```

Koppelt `Desktop`, `Documents` **en `Downloads`** terug aan je echte home-mappen (via
`xdg-user-dir`, dus ook goed als je map `Bureaublad` heet).

`Downloads` is de belangrijkste van de drie: Fusion's exportdialoog opent daar standaard.
Koppel je alleen Desktop en Documents, dan moet je bij **elke** export handmatig wegnavigeren
— en dat vergeet je. Omleggen is veilig: de installer heeft die koppeling alleen *tijdens*
het installeren nodig om zijn eigen `.exe`-bestanden te draaien
([regel 1671](https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux)). Daarna leest niets
hem meer.

> Draai dit script **ná** de installatie, nooit ertijdens. Herinstalleer of update je Fusion,
> dan zet de wizard zijn eigen Downloads-koppeling terug — draai het script daarna gewoon
> opnieuw.

Opruimen gebeurt met `rmdir`, niet `rm -rf` — die weigert op een niet-lege map, dus er kan
nooit per ongeluk werk verdwijnen. Veilig om vaker te draaien.

## Machines waar dit op draait

- HP ProDesk 400 G5 · Intel UHD 630 (Mesa) · Ubuntu
- Wine-modus: `Wine-fix` (custom build in `~/fusion-wine-build`)
- DXVK geïnstalleerd in de prefix (d3d11/dxgi/d3d9)

En (oktober 2026, Fusion 2702):

- Intel Iris Plus 655 (Mesa) · Ubuntu 26.04 · Wine-fix 11.10
- De installer kiest hier `VirtualDeviceGLCore` (OpenGL) voor het 3D-canvas

## Herkomst en licentie

De installer in `vendor/` is werk van **Steve Zabka (cryinkfly)**, MIT-licentie,
copyright (c) 2020-2026 — ongewijzigd meegeleverd, met licentie in `vendor/LICENSE`.
Upstream: https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux

De fix-scripts en `install.sh` in deze repo zijn eigen werk.
