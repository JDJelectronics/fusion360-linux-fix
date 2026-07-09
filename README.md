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
- vindt automatisch alle `NMachineSpecificOptions.xml` in de wineprefix;
- past **alleen** de UI-renderer aan (het 3D-canvas blijft ongemoeid);
- maakt van elk gewijzigd bestand eerst een backup (`*.bak-<renderer>`);
- weigert te draaien zolang Fusion nog open is.

Andere install-locatie? Geef het pad mee als 2e argument:
`./fix-fusion-ui-renderer.sh Software /pad/naar/.autodesk_fusion`

## Machine waar dit op draait

- HP ProDesk 400 G5 · Intel UHD 630 (Mesa) · Ubuntu
- Wine-modus: `Wine-fix` (custom build in `~/fusion-wine-build`)
- DXVK geïnstalleerd in de prefix (d3d11/dxgi/d3d9)
