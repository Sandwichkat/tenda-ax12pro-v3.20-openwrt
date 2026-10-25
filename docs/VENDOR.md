# Vendor blobs and per-device calibration

This repo is **source-only**.  It does not contain the Triductor/Tenda vendor
binaries, the Wi-Fi firmware, or any prebuilt image.  You supply those
locally, from one of two places:

1. the public BPI-SINOVOIP BSP repo, or
2. your own device / your own rootfs dump.

`scripts/vendor_blobs.py` copies them into a local `vendor/` directory
(gitignored) and writes `manifest.sha256`.  `docs/vendor_manifest.sha256` is a
reference manifest for the BSP file set (hashes only — no vendor code).

## Why

The BSP is the public
`https://github.com/BPI-SINOVOIP/THG6500-TAX2-OPENWRT-BSP_TGP3` repo (commit
`c793463e`).  Its top-level `COPYING` is OpenWrt GPL-2.0, but the Triductor
package (`package/triductor/tr5220`) is **binary-only**: prebuilt `ko/*.ko`,
`bin/*`, `config/*`, `FIRMWARE.bin`, with no `PKG_LICENSE` and no source.  The
`tri_*.ko` modules are prebuilt in `target/linux/tr6560/base-files/`.  Most
declare `license=GPL`, some have no license string, the userspace apps and
firmware have no license text.  GitHub reports the repo's license as
**NOASSERTION / Other**.  This repository doesn't include those files; the
build uses the BSP's copies or your own extraction.

The per-device RF calibration (`wifi_cali_data.kv`, `wifi_cali_data_2g.kv`,
`hi5622v100.cal`) is **not in the BSP at all** — it comes from the factory
partition of a specific device and is device-specific.  Keep it with your
local build.  An image without it has no calibration for your radio until
you add your own.

## Collect from the BSP repo

```bash
git clone https://github.com/BPI-SINOVOIP/THG6500-TAX2-OPENWRT-BSP_TGP3.git bsp
git -C bsp checkout c793463e
python3 scripts/vendor_blobs.py collect-bsp bsp vendor
python3 scripts/vendor_blobs.py verify docs/vendor_manifest.sha256 vendor
```

This copies the prebuilt vendor modules, `FIRMWARE.bin`, config/calibration
input tables, userspace apps and the vendor `mac80211.sh` into `vendor/`,
mirroring the rootfs paths.  `Total.wdk` is excluded (the build trims it).
`wifi_kick.ko` is not in the BSP source; a rootfs/device collection adds it.

## Collect from your device or dump

Live device over SSH (your own key):

```bash
python3 scripts/vendor_blobs.py collect-device root@192.168.1.1 vendor
```

From an already-extracted rootfs (e.g. your own stock/BSP rootfs dump):

```bash
python3 scripts/vendor_blobs.py collect-rootfs /path/to/rootfs vendor
```

The extractor places calibration in `vendor/cal/` and writes
`vendor/cal/MANIFEST.sha256`.  `vendor/` and `cal/` are gitignored.

Calibration only:

```bash
python3 scripts/vendor_blobs.py collect-cal /path/to/rootfs vendor
```

## Building

The release build script clones/uses the BSP at the pinned commit, applies
the project patches and source additions, builds it, and layers the
extracted vendor files.  If you use the public BSP's own vendor files, the
only file it cannot supply correctly is the activation-patched
`tri_sdk_l2.ko`; the build applies the local patch itself.  A rootfs/device
collection is still useful for `wifi_kick.ko` (not in the BSP source) and
for the calibration.

```bash
# optional: collect the missing vendor pieces from your own rootfs/device
python3 scripts/vendor_blobs.py collect-rootfs /path/to/your/rootfs vendor
# or: python3 scripts/vendor_blobs.py collect-device root@192.168.1.1 vendor

# build; vendor/ is optional, cal/ is strongly recommended
VENDOR=vendor CAL_DIR=vendor/cal scripts/build_release.sh
```

`build_rootfs.sh` removes any calibration found in the build tree and only
bakes what is in `CAL_DIR`.  Without `CAL_DIR` it warns and produces an image
without per-device calibration.  The resulting image contains the vendor
files and your calibration; it is a local image.

The project also builds its own Ethernet helpers (`ethdbg.ko`, `trihlp`)
from `files/project/eth/`.  `cs_cli` is copied from the BSP tree's own
`target/linux/tr6560/base-files/bin/cs_cli`; none of these are stored here.

## Verification

`docs/vendor_manifest.sha256` covers the BSP vendor set (42 files).  A rootfs
or device collection additionally has `wifi_kick.ko` and may have the
project's patched `tri_sdk_l2.ko`; those won't match the pristine BSP hash.
The project's activation patch is a local modification; the patched module
stays in your local build.

## Licensing

This repository is source-only.  The vendor components come from the public
BSP and keep whatever terms apply to them.  The project's own scripts and
patches are GPL-2.0-compatible; see `LICENSE`.  The banner art is credited
to `@CioStarVT`.  Built images are local artifacts.
