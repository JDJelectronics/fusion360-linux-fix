# Fusion 360 op Linux — UI-crash fix

Autodesk Fusion 360 draait op mijn machine via de
[cryinkfly Wine-installer](https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux)
(install root: `~/.autodesk_fusion`). Bij het opstarten liep het steeds vast.

## Het probleem

De launch-log liep vol met dezelfde GPU-fout, duizenden keren herhaald:

```
ERROR:shared_context_state.cc ... Failed to make current since context is marked as lost
ERROR:skia_output_surface_impl_on_gpu.cc ... Failed to make current.
ERROR:shared_image_factory.cc ... CreateSharedImage: could not create backing.
ERROR:d3d_image_backing_factory.cc ... Unable to create shared handle for DXGIResource 80004001
... WebSocket close 1006  -> hang/crash
```

Dit zijn allemaal fouten van de **interface-laag (Qt/Chromium)**, niet van het 3D-modelleren.

## De oorzaak

Fusion heeft twee losse grafische instellingen in `NMachineSpecificOptions.xml`:

| Instelling | Regelt | Standaard | Probleem? |
|---|---|---|---|
| `driverOptionId` | het **3D-canvas** | `VirtualDeviceDx11` (→ DXVK) | nee, prima |
| `graphicsApiOptionId` | de **Qt-interface** | `OpenGL` | **ja — dit crasht** |

Zelfs in DXVK-modus zet de cryinkfly-installer de UI standaard op OpenGL, en dát verliest
zijn GPU-context. Het 3D-canvas stond al goed op Dx11/DXVK.

## De oplossing

De UI-renderer omzetten van `OpenGL` naar iets stabielers. Het 3D-canvas blijft
GPU-versneld (Dx11/DXVK), dus tekenwerk wordt er niet trager van.

- **`Software`** — UI door de CPU getekend. Meest crash-bestendig. UI iets minder vloeiend. *(momenteel ingesteld)*
- **`Direct3D11`** — UI via DXVK→Vulkan. Sneller, meestal stabiel.

## Gebruik (na een herinstallatie)

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

## Tweede fix: Desktop en Documents komen niet in je home terecht

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

Koppelt `Desktop` en `Documents` terug aan je echte home-mappen (via `xdg-user-dir`, dus ook
goed als je map `Bureaublad` heet). `Downloads` blijft **bewust ongemoeid**: de installer
gebruikt die map zelf, en hem omleggen kan een update-run breken.

Opruimen gebeurt met `rmdir`, niet `rm -rf` — die weigert op een niet-lege map, dus er kan
nooit per ongeluk werk verdwijnen. Veilig om vaker te draaien.

Daarna kies je in Fusion's exportdialoog gewoon **Desktop** of **Documents**.

## Machine waar dit op draait

- HP ProDesk 400 G5 · Intel UHD 630 (Mesa) · Ubuntu
- Wine-modus: `Wine-fix` (custom build in `~/fusion-wine-build`)
- DXVK geïnstalleerd in de prefix (d3d11/dxgi/d3d9)
