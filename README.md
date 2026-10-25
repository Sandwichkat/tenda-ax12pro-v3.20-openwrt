# Tenda AX12 Pro V3.2 — OpenWrt source release

This is a source-only release for the Tenda AX12 Pro V3.2 (Triductor
TR6560).  It builds a custom OpenWrt 22.03 image on Linux 5.10.138 with:

- working Gigabit Ethernet and dual-band Wi-Fi 6;
- WISP (Wi-Fi client), access-point and multi-mode router support;
- HTTPS LuCI, CAKE traffic shaping with automatic rate control, and
  LAN-only IPv6;
- both login banners, the hourly activation-reboot fix, and the
  Ethernet/Wi-Fi coexistence fixes.

The repository contains the project's patches, scripts and sanitized rootfs
files.  The vendor binaries, Wi-Fi firmware and per-device calibration are
supplied locally at build time from the public BSP or your own device; no
prebuilt image is included.  See [Source and licensing](#source-and-licensing).

> This build produces a **rootfs only**.  The router needs the compatible
> 5.10.138 kernel/FIP already installed.  Check `uname -r` before flashing;
> stock Tenda firmware uses a different kernel.

---

## What you need

- A Tenda AX12 Pro V3.2 already running the project's compatible 5.10.138
  kernel/FIP.
- A Linux build host (Fedora, Debian/Ubuntu, etc.) with:
  - the standard OpenWrt 22.03 build dependencies
    ([list](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem));
  - `git`, `python3`, `make`, `gcc`/`g++`, `rsync`, `unzip`, `gawk`,
    `gettext`, `bison`, `flex`, `bc`, `cmake`, `ninja`, `patch`, `wget`,
    `cpio`, `tar`, `xz`, `zstd`, `perl`;
  - about 25–30 GB of free disk and 8 GB of RAM (more is better).
- A serial console (115200 8N1) and a TFTP server for flashing.
- Ideally, your own device's vendor files and radio calibration (see
  [step 3](#3-collect-vendor-files-and-calibration-recommended)).

A first build takes roughly 20–60 minutes depending on the machine; later
builds are incremental.

---

## 1. Get the source

Copy this release directory to the build host, or clone the repository:

```sh
git clone https://github.com/Sandwichkat/tenda-ax12pro-v3.20-openwrt.git
cd tenda-ax12pro-v3.20-openwrt
```

The directory should contain `README.md`, `patches/`, `files/`,
`rootfs-overlay/`, `configs/`, `scripts/`, and `docs/`.

The base BSP is
[`BPI-SINOVOIP/THG6500-TAX2-OPENWRT-BSP_TGP3`](https://github.com/BPI-SINOVOIP/THG6500-TAX2-OPENWRT-BSP_TGP3)
at commit `c793463e`.  The build script clones it for you into `bsp/`, or
you can point it at an existing clone with `--bsp-source`.

---

## 2. Install build dependencies

Install the packages for your distribution.  For Debian/Ubuntu, the usual
OpenWrt set is approximately:

```sh
sudo apt install build-essential git python3 rsync unzip gawk gettext \
  libncurses-dev zlib1g-dev libssl-dev libelf-dev bison flex bc cmake ninja-build \
  subversion mercurial time wget cpio file perl
```

Fedora names differ (`gcc-c++`, `ncurses-devel`, `openssl-devel`, etc.).
If the BSP's host tools fail to build, the usual cause is a missing package;
the full list is on the OpenWrt build-system page linked above.

The project already carries the host-tool fixes needed for modern GCC/CMake
and Ninja; you do not need to patch anything by hand.

---

## 3. Collect vendor files and calibration (recommended)

The public BSP already ships most vendor modules, apps and Wi-Fi firmware.
The build can use those directly.  However, two things are better taken
from **your own** device or rootfs dump:

- `wifi_kick.ko`, which is not in the BSP source;
- the radio calibration files (`wifi_cali_data.kv`,
  `wifi_cali_data_2g.kv`, `hi5622v100.cal`), which are unique to your
  radio.

### From a device over SSH

If you have root SSH access to your router:

```sh
python3 scripts/vendor_blobs.py collect-device root@192.168.1.1 vendor
```

This copies vendor modules/apps/firmware into `vendor/` and places the
calibration in `vendor/cal/`.

### From a rootfs dump

If you already have an extracted rootfs:

```sh
python3 scripts/vendor_blobs.py collect-rootfs /path/to/rootfs vendor
```

### Calibration only

If you already know where your calibration files are:

```sh
python3 scripts/vendor_blobs.py collect-cal /path/to/etc/wifi .
# writes ./cal/wifi_cali_data*.kv and ./cal/hi5622v100.cal
```

The three files usually live in `/etc/wifi` on a running system, or in the
factory data of a stock rootfs.  They are specific to your radio.

`vendor/` and `cal/` are local build inputs and are already gitignored.  The
calibration is specific to your radio; keep it with your local build.

Without this step, the build still works, but the image has no calibration
for your radio; the build prints a warning.

You can verify a collection with:

```sh
python3 scripts/vendor_blobs.py verify vendor/manifest.sha256 vendor
```

---

## 4. Build

From the release directory, run the build script.  The simplest form lets
the script clone the BSP into `bsp/`:

```sh
VENDOR=vendor CAL_DIR=vendor/cal ./scripts/build_release.sh
```

If you already have a BSP checkout and want to reuse its `dl/` download
cache:

```sh
VENDOR=vendor CAL_DIR=vendor/cal \
  ./scripts/build_release.sh --bsp-source /path/to/THG6500-TAX2-OPENWRT-BSP_TGP3
```

If you do not have a `vendor/` collection, omit `VENDOR`; the build uses
the vendor files from the BSP checkout:

```sh
CAL_DIR=/path/to/your/cal ./scripts/build_release.sh
```

Useful options/environment variables:

| Option | Meaning |
|---|---|
| `--bsp-source DIR` | clone a local BSP checkout into `bsp/` (recommended) |
| `--bsp DIR` | use this BSP tree in place (the script modifies it) |
| `--vendor DIR` | vendor-file directory (default `vendor/`) |
| `--cal DIR` | calibration directory (default `cal/`) |
| `--out DIR` | output directory (default `out/`) |
| `JOBS=N` | parallel build jobs (default: all CPUs) |
| `BSP_SOURCE=DIR` | same as `--bsp-source`; also supplies its `dl/` cache |
| `BSP_URL=...` | override the BSP clone URL |
| `BSP_COMMIT=...` | override the pinned commit (not recommended) |

What the script does, in order:

1. clones the BSP at `c793463e` if needed;
2. applies `patches/0001-bsp-source.patch`;
3. copies the board DTS, Ethernet scripts, kernel notifier fix and host
   build patches from `files/bsp/`;
4. installs `configs/tenda_ax12_pro.config` and enables CAKE;
5. builds the BSP (`make defconfig && make -j$JOBS`);
6. layers your `vendor/` files and the sanitized `rootfs-overlay/`;
7. applies the local activation fix to `tri_sdk_l2.ko`;
8. builds the project Ethernet helpers (`ethdbg.ko`, `trihlp`);
9. installs `sch_cake.ko` if the kernel package did not;
10. builds the squashfs and the 32 KiB-padded flash image.

The full build log is `logs/build.log`.  If the script stops, the last 100
lines of that log are printed.

### Build without flashing anything

The build is host-only; it doesn't contact the router or write to the SPI
flash.

---

## 5. Check the result

```sh
ls -l out/rootfs_release*
sha256sum out/rootfs_release_flash.bin
cat out/rootfs_release.squashfs.sha256
```

Expected files:

| File | Purpose |
|---|---|
| `out/rootfs_release.squashfs` | the raw squashfs |
| `out/rootfs_release.squashfs.sha256` | squashfs checksum |
| `out/rootfs_release_flash.bin` | the padded image written to flash |
| `out/filelist.txt` | contents of the squashfs |

The script prints the rootfs size, the partition limit (`0x760000`), and the
remaining slack.  If the image is larger than the limit, the build fails;
remove packages from `configs/tenda_ax12_pro.config` or trim `rootfs-overlay/`.

Record the actual padded image size now; you need it for the flash command:

```sh
SIZE=$(stat -c %s out/rootfs_release_flash.bin)
printf 'image size: %s bytes = 0x%x\n' "$SIZE" "$SIZE"
```

---

## 6. Flash the rootfs

This writes the rootfs partition directly.  Read the partition map and use
the actual image size; a wrong offset or size can prevent boot.  The U-Boot
console is the recovery path.

### 6.1 Confirm the kernel prerequisite

On the router:

```sh
uname -r
```

It should report `5.10.138`.  If it reports the stock Tenda kernel
(`5.10.201` or similar), this rootfs is not a match; the full BSP kernel/FIP
is needed first.

### 6.2 Back up

On the router, save a configuration backup:

```sh
sysupgrade -b /tmp/backup.tar.gz
```

Copy it off the router, then also keep a known-good rootfs image and your
serial/TFTP recovery setup available.

### 6.3 Partition map

The update writes only the rootfs range:

| Region | Offset | Length | Contents |
|---|---:|---:|---|
| Kernel/FIP | `0x110000` | `0x280000` | project kernel — leave alone |
| **Rootfs** | **`0x390000`** | **`0x760000`** | this image |
| Rootfs overlay | `0xAF0000` | `0x4A8000` | your JFFS2 config — preserved |
| Config | `0xF98000` | `0x068000` | factory config — leave alone |

The rootfs erase ends exactly where the overlay starts, so your personal
configuration survives.  A factory reset later clears the overlay.

### 6.4 Prepare TFTP

1. Copy `out/rootfs_release_flash.bin` into your TFTP server's root
   directory.
2. Connect the router's U-Boot Ethernet port to the build host.
3. Give the build host a static address on the router's network; the
   examples below use `192.168.1.10` for the host and `192.168.1.1` for the
   router.
4. Open the serial console at **115200 8N1** and interrupt U-Boot during
   boot to get the `U-Boot>` prompt.

### 6.5 Write the image

In U-Boot, using the actual hex size from step 5 (the example below is the
development image's `0x708000`):

```text
setenv ipaddr 192.168.1.1
setenv serverip 192.168.1.10
tftpboot 0x83200000 rootfs_release_flash.bin

sfc unlock
sfc erase 0x390000 0x760000
sfc write 0x83200000 0x390000 0x708000
sfc read  0x84000000 0x390000 0x708000
cmp.b 0x83200000 0x84000000 0x708000
bootfip
```

Replace every `0x708000` with **your** image size (the hex value printed in
step 5).  The `sfc erase` length stays `0x760000` (the whole rootfs
partition).  Check that the read-back and `cmp.b` match before rebooting.

The project leaves the flash unlocked; `sfc lock` is not part of this
update.  Keep the erase inside the rootfs range; `0xAF0000` is your overlay.

### 6.6 If something goes wrong

Avoid interrupting an erase/write.  If `tftpboot`, `sfc write` or `cmp.b`
fails:

1. stay in U-Boot;
2. re-check the host IP, TFTP path, firewall, and image size;
3. re-run `sfc erase` and `sfc write`;
4. if the board no longer boots, use the serial console and U-Boot to
   restore a known-good rootfs image.

The U-Boot console is the recovery path; the bootloader itself is not
modified by this update.

---

## 7. First boot

1. Power on and wait about 45–90 seconds.  The red LED should settle and
   the APs should appear.
2. Connect a computer to a LAN port (lan1–lan3; lan4 is the WAN jack in
   router mode).  The LAN DHCP server is disabled on this image, so set a
   static address if needed:
   - computer: `192.168.1.10/24`
   - router: `192.168.1.1`
3. Open **https://192.168.1.1/** .  HTTP redirects to HTTPS.  The
   certificate is self-signed and generated on first boot, so your browser
   will warn once.
4. Log in as `root` with **no password**, then immediately set a root
   password.
5. The default AP is:
   - SSID: `TetOS`
   - password: `changeme`
   Change it before putting the router on an untrusted network.
6. The WISP uplink is intentionally empty.  Configure your upstream Wi-Fi
   in **LuCI → Network → Operation Mode** (or the WISP page).  The same
   page has the AP SSID/password and TX-power controls.
7. The image uses a **LAN-only IPv6 ULA** generated on first boot.  There
   is no IPv6 default route because the tested upstream is IPv4-only.
8. Both banners are baked in:
   - `/etc/banner` is the small pre-auth SSH banner (1,504 bytes);
   - `/etc/banner.art` is printed after login on SSH and the serial
     console.

### First-boot checklist

- [ ] Set the root password.
- [ ] Change the AP PSK from `changeme`.
- [ ] Configure WISP only with your own upstream credentials.
- [ ] Keep LuCI and SSH off the WAN side.
- [ ] Add your SSH public key to `/etc/dropbear/authorized_keys` if you
      want key login (this dropbear does not read `~/.ssh/authorized_keys`).
- [ ] Check the firewall and the vendor Wi-Fi services if you run this on
      an untrusted network.

---

## 8. Verify the features

```sh
# Ethernet / LAN
ip -4 addr show br-lan
ip link show eth0

# Wi-Fi
iw dev
iw dev wlan1 info
iw dev wlan2 info

# CAKE shaper
tc qdisc show dev wlan0
tc qdisc show dev ifb0
cat /tmp/cake_autorate.state

# IPv6: ULA present, no default route
ip -6 addr show br-lan
ip -6 route | grep default || true

# HTTPS -- run this from your computer, not the router
curl -kI https://192.168.1.1/

# Banners (on the router)
sha256sum /etc/banner /etc/banner.art
```

Activation-patch check: copy the module to the build host and check it there
(the router image does not need Python):

```sh
scp root@192.168.1.1:/lib/modules/5.10.138/tri_sdk_l2.ko /tmp/
python3 scripts/patch_tri_sdk_l2.py --check /tmp/tri_sdk_l2.ko
# prints: ... state=patched
```

The WISP association keeps the vendor Wi-Fi chip's watchdog alive through
beacon activity.  If you leave the WISP uplink empty, the APs still run, but
the chip is happiest with an associated client/upstream; configure WISP or
connect a client to the AP.

---

## 9. Updates, reset and recovery

- **Normal update:** repeat the raw rootfs flash in step 6.  The JFFS2
  overlay (your settings) is preserved because the erase stops at
  `0xAF0000`.
- **Configuration backup:** `sysupgrade -b /tmp/backup.tar.gz` still works.
- **Factory reset:** run `jffs2reset` (or use the project's reset-button
  flow) to clear the overlay and return to the generic defaults: hostname
  `OpenWrt`, AP `TetOS`/`changeme`, empty WISP, no root password, fresh
  SSH host keys, fresh ULA.
- **Mode rollback:** the project's reset-button handling rolls back a
  pending mode change; see the mode page in LuCI.
- **LuCI firmware upload is disabled** on purpose (`platform.sh` is renamed
  to `.rawflash-only`).  Flashing is done through U-Boot/TFTP.
- **Recovery:** the U-Boot console and a known-good rootfs image are your
  fallback.  The flash stays unlocked.

---

## Troubleshooting

### The build fails

- Read `logs/build.log`; the script prints the last 100 lines.
- Re-run with fewer jobs if the host runs out of RAM:
  `JOBS=4 ./scripts/build_release.sh ...`.
- Make sure the BSP commit is available and the host has the OpenWrt build
  dependencies.
- If `sch_cake.ko` is missing, check that the build enabled
  `CONFIG_PACKAGE_kmod-sched-cake=y` and `CONFIG_NET_SCH_CAKE=m`; the release
  script normally installs the module from the kernel build automatically.
- If the rootfs exceeds `0x760000`, remove packages or trim the overlay.

### The activation patch is not applied

`tri_sdk_l2.ko` must have the success-branch fix, or the router reboots at
about one hour of uptime.  Check it with:

```sh
python3 scripts/patch_tri_sdk_l2.py --check \
  /path/to/rootfs/lib/modules/5.10.138/tri_sdk_l2.ko
```

The script prints `state=patched`.  If it prints `state=unknown`, the vendor
module is a different build; use the patched module from your own device's
rootfs or inspect the module before flashing.  The patched module is a
local derivative of a vendor binary; the repository contains only the patch
script.

### No Ethernet after boot

- Check `dmesg`, `ip link`, and `/tmp/eth_ready`.
- The Ethernet bring-up requires the project kernel patch
  (`net/core/dev.c` notifier fix), the vendor `tri_*` modules, and the
  `ethdbg.ko`/`trihlp` helpers.
- Verify the kernel is the project's 5.10.138 build; a stock kernel will not
  have the patch or the matching module ABI.

### No Wi-Fi / weak AP signal

- Wait 45–90 seconds; the Wi-Fi bring-up is deliberately late in boot.
- Check `logread`, `/tmp/wifi_pre.log`, `/tmp/sdt.log`, `/tmp/nlc.log`, and
  `/tmp/acs.log`.
- Verify the calibration files were baked (the build prints `calibration:
  copied from ...`).
- If the AP signal is weak, check the TX power:
  `iw dev wlan1 info` and `iw dev wlan1 set txpower fixed 3000`.  The LuCI
  Wireless page has a TX-power control.
- The vendor driver needs MAC activity to feed the chip watchdog; with an
  empty WISP uplink, connect an AP client or configure WISP.

### No DHCP on a wired client

The LAN DHCP server is disabled in this image.  Set a static address for
management, or use the AP's DHCP path.  The project's `wisp-dhcp` handles
the AP/WISP side.

### WISP will not associate

- Check the SSID/password in LuCI → Network → Operation Mode.
- Check `/tmp/wpa.log`, `/tmp/link.txt`, and `wpa_cli -i wlan0 status`.
- Make sure the upstream is 2.4/5 GHz compatible and in range.
- The chip's watchdog is fed by MAC activity; an idle interface is not a
  valid test.

### SSH banner / login issues

- The pre-auth banner is limited to 2,050 bytes by dropbear; this image uses
  1,504 bytes there and a 67,421-byte after-login art.
- If SSH drops during login, check that `/etc/banner` is the small file and
  that `/etc/banner.art` exists.
- Host keys are generated on first boot; they are not baked into the image.

### LuCI HTTPS warning

The certificate is self-signed and generated locally on first boot.  Accept
it once, or replace `/etc/uhttpd.crt` and `/etc/uhttpd.key` with your own
certificate (key mode `0600`, then restart uhttpd).

### No IPv6 internet

Expected.  The tested upstream is IPv4-only.  The image provides a ULA and
RA on the LAN but deliberately installs no IPv6 default route.

### The router rebooted after about an hour

The activation patch was not present.  Rebuild with this release or copy the
patched module from your own device.  Check `dmesg` for `no activation!
reboot!`.

---

## How the build works

1. `apply_patches.sh` applies the tracked BSP diff, adds the untracked board
   sources (DTS, Ethernet bring-up, custom LED, kernel notifier patch, host
   build patches), copies the board `.config`, and enables CAKE.
2. The BSP build produces the kernel, packages and root tree.
3. `build_release.sh` layers the local vendor files, then the sanitized
   project root files.
4. The activation fix is applied locally to `tri_sdk_l2.ko`.
5. `build_eth_utils.sh` builds `ethdbg.ko` and `trihlp` from project source
   and copies the BSP's `cs_cli`.
6. `build_rootfs.sh` strips any stray calibration, removes any build-time
   SSH/uhttpd keys, copies only `CAL_DIR`, removes the unused `Total.wdk`,
   applies `files/project/trim-rootfs.list` (the proven minimal file set),
   checks the baked fixes and release hygiene, and builds the squashfs plus
   padded flash image.

---

## Repository layout

| Path | Contents |
|---|---|
| `patches/` | tracked BSP changes (`git apply`-able) |
| `files/bsp/` | untracked BSP source: board DTS, Ethernet scripts, kernel notifier patch, host-tool patches |
| `files/project/eth/` | project Ethernet helper sources (`ethdbg.c`, `trihlp.c`) |
| `files/project/trim-rootfs.list` | package files removed from the full BSP root to reproduce the proven minimal image |
| `rootfs-overlay/` | sanitized rootfs files added over the BSP build |
| `configs/` | OpenWrt board `.config` |
| `scripts/` | build, extractor, activation-patch and helper scripts |
| `docs/` | vendor extraction/licensing notes and BSP reference manifest |
| `bsp/` | local BSP clone (ignored) |
| `vendor/` | local vendor files (ignored) |
| `cal/` | local per-device calibration (ignored) |
| `out/` | build outputs (ignored) |
| `logs/` | build logs (ignored) |

The image is generic: hostname `OpenWrt`, AP `TetOS`/`changeme`, empty WISP
uplink, no root password, no baked SSH keys, and a fresh ULA on first boot.
Personal settings belong in the router's overlay or a local config, not in
this repository.

---

## Source and licensing

This repository is source-only.  It contains the project's patches, scripts
and sanitized rootfs files; it does not contain vendor binaries, firmware,
calibration or a prebuilt image.  The build takes vendor files from the
public BSP and, optionally, from your own device/rootfs.

- **Per-device calibration** (`wifi_cali_data*.kv`, `hi5622v100.cal`) is
  specific to your radio.  Keep it in `cal/` with your local build; `cal/`
  and `vendor/` are gitignored.
- **Vendor components** come from the BSP and keep their own terms.  The
  BSP's own files are the reference; `docs/VENDOR.md` records the layout we
  observed.
- **A built image** contains the vendor components and your calibration, so
  it is a local image.
- **The activation patch** to `tri_sdk_l2.ko` is a local derivative of a
  vendor binary.  The repository contains only the patch script; the patched
  module stays in your local build.
- **The project's own scripts, patches and rootfs overlay** are intended to
  be GPL-2.0-compatible, matching the underlying OpenWrt BSP.  See
  `LICENSE`.  Third-party components keep their own licenses.
- **Banner art:** credit `@CioStarVT` where applicable.

---

## Credits

- BPI-SINOVOIP for the public `THG6500-TAX2-OPENWRT-BSP_TGP3` BSP.
- Triductor and Tenda for the TR6560 platform and vendor components.
- The OpenWrt project.
- `@CioStarVT` for the banner art.
