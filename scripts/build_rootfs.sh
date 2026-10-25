#!/bin/bash
# Assemble the release rootfs squashfs from a built BSP root tree.
#
# The caller is responsible for applying rootfs-overlay/, vendor files and
# the activation patch first (scripts/build_release.sh does all of that).
# Host-only: no flash writes.  Outputs:
#   $OUTD/rootfs_release.squashfs (+ .sha256)
#   $OUTD/rootfs_release_flash.bin (32 KiB padded for `sfc write`)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REL=$(cd "$HERE/.." && pwd)
B=${BSP:?set BSP to the BSP tree}
ROOT=${ROOT:-$B/build_dir/target-arm_cortex-a9_musl_eabi/root-tr6560}
MKSQ=${MKSQ:-$(ls "$B"/build_dir/host/squashfskit-*/squashfs-tools/mksquashfs 2>/dev/null | head -1 || true)}
OUTD=${OUTD:-$(cd "$HERE/.." && pwd)/out}
STAGE=$OUTD/rootfs_stage
OUT=$OUTD/rootfs_release.squashfs
LIMIT=${LIMIT:-$((0x760000))}
EXPECT_MODULE_SHA=${EXPECT_MODULE_SHA:-}
# Per-device RF calibration is never baked from the build tree.  Point CAL_DIR
# at a directory holding wifi_cali_data*.kv (and optionally hi5622v100.cal),
# e.g. vendor/cal from scripts/vendor_blobs.py.
CAL_DIR=${CAL_DIR:-}

[ -d "$ROOT" ] || { echo "missing root tree $ROOT" >&2; exit 1; }
[ -n "$MKSQ" ] && [ -x "$MKSQ" ] || { echo "missing mksquashfs" >&2; exit 1; }

echo "== 1. stage copy"
rm -rf "$STAGE"
mkdir -p "$OUTD"
cp -a "$ROOT" "$STAGE"

echo "== 1b. per-device RF calibration"
rm -f "$STAGE"/etc/wifi/wifi_cali_data*.kv "$STAGE"/etc/wifi/hi5622v100.cal
if [ -n "$CAL_DIR" ]; then
	cp -f "$CAL_DIR"/wifi_cali_data*.kv "$STAGE/etc/wifi/" 2>/dev/null || true
	if [ -f "$CAL_DIR/hi5622v100.cal" ]; then
		cp -f "$CAL_DIR/hi5622v100.cal" "$STAGE/etc/wifi/"
	fi
	ls "$STAGE"/etc/wifi/wifi_cali_data*.kv >/dev/null 2>&1 || {
		echo "ERROR: no wifi_cali_data*.kv in CAL_DIR=$CAL_DIR" >&2
		exit 1
	}
	echo "calibration: copied from $CAL_DIR"
else
	echo "WARNING: CAL_DIR unset; image has no per-device RF calibration" >&2
fi

echo "== 2. dropbear host keys are generated on first boot"
mkdir -p "$STAGE/etc/dropbear"
chmod 700 "$STAGE/etc/dropbear"
rm -f "$STAGE"/etc/dropbear/dropbear_*_host_key \
      "$STAGE"/etc/dropbear/dropbear_*_host_key.pub \
      "$STAGE"/etc/dropbear/authorized_keys
# A pre-generated web certificate is also device-specific; uhttpd makes a
# fresh one on first start.
rm -f "$STAGE"/etc/uhttpd.crt "$STAGE"/etc/uhttpd.key \
      "$STAGE"/etc/uhttpd.crt.new "$STAGE"/etc/uhttpd.key.new
# OpenSSH may be present for clients; never leave server keys in the image.
rm -f "$STAGE"/etc/ssh/ssh_host_* 2>/dev/null || true

echo "== 3. trim unreferenced Wi-Fi symbol blob"
if [ -e "$STAGE/etc/wifi/Total.wdk" ]; then
	rm -f "$STAGE/etc/wifi/Total.wdk"
	echo "removed etc/wifi/Total.wdk"
fi

echo "== 3b. apply rootfs trim manifest"
# The clean BSP installs the full vendor package set; this manifest is the
# exact set of files absent from the proven minimal image.  It removes
# prplmesh/easycwmp, Python, OpenSSH, BlueZ/glib/dbus/udev, lxc binaries,
# /home/cli, /opt, test tools and other unused package payloads.
TRIM=${TRIM:-$REL/files/project/trim-rootfs.list}
if [ -f "$TRIM" ]; then
	while IFS= read -r p; do
		[ -n "$p" ] || continue
		rm -f "$STAGE/$p"
	done < "$TRIM"
	echo "trimmed from $TRIM"
else
	echo "WARNING: trim manifest missing: $TRIM" >&2
fi

echo "== 4. verify baked fixes"
python3 "$HERE/patch_tri_sdk_l2.py" --check \
	"$STAGE/lib/modules/5.10.138/tri_sdk_l2.ko" || {
	echo "ERROR: tri_sdk_l2.ko is not activation-patched" >&2; exit 1; }
if [ -n "$EXPECT_MODULE_SHA" ]; then
	sha256sum "$STAGE/lib/modules/5.10.138/tri_sdk_l2.ko" | \
		grep -q "^$EXPECT_MODULE_SHA " || {
		echo "ERROR: tri_sdk_l2.ko sha is not $EXPECT_MODULE_SHA" >&2; exit 1; }
fi
grep -q assocList "$STAGE/www/luci-static/resources/wisp_status.js" || {
	echo "ERROR: client-list assocList fix missing" >&2; exit 1; }
BANNER_SHA=f93b369d5b81a0afb0d82cf11e6659662d8d5b580bae2a35750c7465cdac4da4
BANNER_ART_SHA=b3d5c48817164b3418345658c29c4058cc5a5d09ed874d0c4dc00107e90d3ae4
[ "$(sha256sum "$STAGE/etc/banner" | awk '{print $1}')" = "$BANNER_SHA" ] || {
	echo "ERROR: pre-auth banner is not the expected 1.5 KB art" >&2; exit 1; }
[ "$(stat -c %s "$STAGE/etc/banner")" -le 2050 ] || {
	echo "ERROR: banner exceeds dropbear MAX_BANNER_SIZE (2050)" >&2; exit 1; }
[ "$(sha256sum "$STAGE/etc/banner.art" | awk '{print $1}')" = "$BANNER_ART_SHA" ] || {
	echo "ERROR: after-login banner.art is missing or not the expected art" >&2; exit 1; }
grep -Eq "^[[:space:]]*option[[:space:]]+BannerFile[[:space:]]+'/etc/banner'" "$STAGE/etc/config/dropbear" || {
	echo "ERROR: dropbear BannerFile is not set" >&2; exit 1; }
grep -q '\[ -f /etc/banner.art \] && cat /etc/banner.art' "$STAGE/etc/profile" || {
	echo "ERROR: /etc/profile does not print banner.art on login" >&2; exit 1; }
grep -q 'dhcp-leasefile=/tmp/dhcp.leases' "$STAGE/usr/sbin/wisp-dhcp" || {
	echo "ERROR: DHCP lease file fix missing" >&2; exit 1; }
grep -q 'dhcp-hostsfile' "$STAGE/usr/sbin/wisp-dhcp" || {
	echo "ERROR: DHCP static-hosts support missing" >&2; exit 1; }
grep -q 'dhcp.leases' "$STAGE/www/luci-static/resources/view/status/include/40_dhcp.js" || {
	echo "ERROR: LuCI DHCP lease fallback missing" >&2; exit 1; }
grep -q 'wisp-dhcp' "$STAGE/etc/init.d/dnsmasq" || {
	echo "ERROR: dnsmasq reload hook for wisp-dhcp missing" >&2; exit 1; }
[ -e "$STAGE/etc/rc.d/S22wisp-dhcp" ] || {
	echo "ERROR: wisp-dhcp boot link missing" >&2; exit 1; }
grep -q 'chmod 644 "$WISP_DNS"' "$STAGE/usr/share/udhcpc/wisp.script" || {
	echo "ERROR: wisp.script resolv perms fix missing" >&2; exit 1; }
grep -q 'chmod 644 /tmp/resolv.conf.d/resolv.conf.auto' "$STAGE/etc/hotplug.d/iface/90-mode-dns" || {
	echo "ERROR: 90-mode-dns resolv perms fix missing" >&2; exit 1; }
grep -q '/etc/init.d/dnsmasq restart' "$STAGE/usr/share/udhcpc/wisp.script" || {
	echo "ERROR: wisp.script dnsmasq reload fix missing" >&2; exit 1; }
grep -q 'mode4' "$STAGE/usr/lib/lua/luci/version.lua" || {
	echo "ERROR: LuCI asset version is not mode4" >&2; exit 1; }
[ ! -e "$STAGE/lib/upgrade/platform.sh" ] || {
	echo "ERROR: broken platform.sh still present" >&2; exit 1; }
[ -e "$STAGE/lib/upgrade/platform.sh.rawflash-only" ] || {
	echo "ERROR: platform.sh was not renamed" >&2; exit 1; }
for f in "$STAGE/etc/init.d/wifi_pre" "$STAGE/etc/init.d/wifi_ap"; do
	if ! grep -q '0</dev/null 1>/dev/null 2>&1' "$f"; then
		echo "ERROR: hostapd/wpa_supplicant fd-2 guard missing in $f" >&2; exit 1
	fi
done
grep -q "option hostname 'OpenWrt'" "$STAGE/etc/config/system" || {
	echo "ERROR: default hostname is not OpenWrt" >&2; exit 1; }
grep -q 'list listen_https	0.0.0.0:443' "$STAGE/etc/config/uhttpd" || {
	echo "ERROR: HTTPS listener missing from uhttpd config" >&2; exit 1; }
grep -q 'option redirect_https	1' "$STAGE/etc/config/uhttpd" || {
	echo "ERROR: HTTP->HTTPS redirect not enabled" >&2; exit 1; }
grep -q 'chmod 600 "${UHTTPD_KEY}"' "$STAGE/etc/init.d/uhttpd" || {
	echo "ERROR: uhttpd private key permission fix missing" >&2; exit 1; }
[ -s "$STAGE/lib/modules/5.10.138/sch_cake.ko" ] || {
	echo "ERROR: sch_cake.ko missing (enable CONFIG_NET_SCH_CAKE=m)" >&2; exit 1; }
if ! sha256sum "$STAGE/lib/modules/5.10.138/sch_cake.ko" | grep -q "^a00a5998"; then
	echo "WARNING: sch_cake.ko sha differs from the known M9 build" >&2
	echo "         (expected for a clean rebuild; module is present)" >&2
fi
[ -x "$STAGE/etc/init.d/sqm_cake" ] && [ -L "$STAGE/etc/rc.d/S95sqm_cake" ] || {
	echo "ERROR: sqm_cake init script or boot link missing" >&2; exit 1; }
grep -q 'RATE_DOWN=36mbit' "$STAGE/etc/init.d/sqm_cake" || {
	echo "ERROR: sqm_cake download rate not set" >&2; exit 1; }
grep -q 'RATE_UP=16mbit' "$STAGE/etc/init.d/sqm_cake" || {
	echo "ERROR: sqm_cake upload rate not set" >&2; exit 1; }
[ -x "$STAGE/usr/sbin/cake_autorate" ] && [ -x "$STAGE/etc/init.d/cake_autorate" ] && \
	[ -L "$STAGE/etc/rc.d/S96cake_autorate" ] || {
	echo "ERROR: cake_autorate controller or boot link missing" >&2; exit 1; }
grep -q 'REFLECTOR=1.1.1.1' "$STAGE/usr/sbin/cake_autorate" || {
	echo "ERROR: autorate reflector missing" >&2; exit 1; }
grep -q 'DOWN_MAX=42000' "$STAGE/usr/sbin/cake_autorate" || {
	echo "ERROR: autorate download ceiling not set" >&2; exit 1; }
grep -q 'UP_MAX=20000' "$STAGE/usr/sbin/cake_autorate" || {
	echo "ERROR: autorate upload ceiling not set" >&2; exit 1; }
grep -q "option ula_prefix 'auto'" "$STAGE/etc/config/network" || {
	echo "ERROR: ULA is not auto-generated" >&2; exit 1; }
grep -q "option ip6assign '64'" "$STAGE/etc/config/network" || {
	echo "ERROR: LAN ip6assign is not 64" >&2; exit 1; }
grep -q "option ra 'server'" "$STAGE/etc/config/dhcp" || {
	echo "ERROR: LAN RA server not enabled" >&2; exit 1; }
grep -q "option ra_default '0'" "$STAGE/etc/config/dhcp" || {
	echo "ERROR: LAN RA default route not disabled" >&2; exit 1; }
# Release hygiene: optional private literal list, one pattern per line.
# Keep the developer's real SSIDs/PSKs/MACs/passwords out of this public
# script; put them in private/secret-patterns.txt (gitignored) if you want
# the extra scan.  The explicit generic gates below still run either way.
if [ -f "$REL/private/secret-patterns.txt" ]; then
	while IFS= read -r bad; do
		[ -n "$bad" ] || continue
		if grep -RIsq -- "$bad" "$STAGE"; then
			echo "ERROR: private pattern '$bad' found in image" >&2; exit 1
		fi
	done < "$REL/private/secret-patterns.txt"
else
	echo "NOTE: no private/secret-patterns.txt; generic release gates only"
fi
[ ! -e "$STAGE/etc/dropbear/authorized_keys" ] || {
	echo "ERROR: authorized_keys must not be baked" >&2; exit 1; }
if ls "$STAGE"/etc/dropbear/dropbear_*_host_key >/dev/null 2>&1; then
	echo "ERROR: dropbear host keys must not be baked" >&2; exit 1
fi
[ ! -e "$STAGE/etc/wifi/hostapd_ax.conf" ] || {
	echo "ERROR: unused hostapd_ax.conf is still present" >&2; exit 1; }
! grep -q '^config host' "$STAGE/etc/config/dhcp" || {
	echo "ERROR: a static DHCP lease is baked" >&2; exit 1; }
grep -q "option ssid 'TetOS'" "$STAGE/etc/config/wisp" && \
grep -q "option psk 'changeme'" "$STAGE/etc/config/wisp" || {
	echo "ERROR: release AP SSID/PSK placeholders missing" >&2; exit 1; }
grep -q "wisp.uplink.psk missing" "$STAGE/etc/init.d/wifi_pre" || {
	echo "ERROR: wifi_pre missing-uplink handling not baked" >&2; exit 1; }
echo "all fix checks passed"

echo "== 5. mksquashfs"
rm -f "$OUT"
"$MKSQ" "$STAGE" "$OUT" -noappend -comp xz -Xbcj arm -Xdict-size 100% \
	-b 1M -no-xattrs -all-root -processors "$(nproc)" > "$OUTD/mksquashfs.log" 2>&1

SIZE=$(stat -c %s "$OUT")
echo "rootfs: $SIZE B (0x$(printf %x "$SIZE")) / limit $LIMIT B"
if [ "$SIZE" -gt "$LIMIT" ]; then
	echo "ERROR: rootfs exceeds the rootfs partition" >&2
	exit 1
fi
echo "slack: $((LIMIT - SIZE)) B"
sha256sum "$OUT" | tee "$OUT.sha256"

PAD=$(( (SIZE + 0x7FFF) / 0x8000 * 0x8000 ))
cp -f "$OUT" "$OUTD/rootfs_release_flash.bin"
truncate -s "$PAD" "$OUTD/rootfs_release_flash.bin"
echo "flash image: $OUTD/rootfs_release_flash.bin ($PAD B = 0x$(printf %x "$PAD"))"
sha256sum "$OUTD/rootfs_release_flash.bin"

echo "== 6. required files present:"
USQ=$(ls "$B"/build_dir/host/squashfskit-*/squashfs-tools/unsquashfs 2>/dev/null | head -1 || true)
[ -n "$USQ" ] && [ -x "$USQ" ] || { echo "missing unsquashfs" >&2; exit 1; }
"$USQ" -l "$OUT" > "$OUTD/filelist.txt" 2>/dev/null
for f in etc/config/mode usr/sbin/mode usr/sbin/wisp-dhcp usr/sbin/wisp-sta \
         usr/share/udhcpc/wisp.script etc/init.d/mode etc/rc.button/reset \
         etc/init.d/mode_watch etc/rc.d/S14mode etc/rc.d/S15wifi_pre \
         etc/rc.d/S16mode_watch etc/rc.d/S19tri_eth_up etc/rc.d/S21wifi_net \
         etc/rc.d/S22wifi_ap etc/rc.d/S95sqm_cake etc/rc.d/S96cake_autorate \
         etc/rc.d/S99custom_led_show \
         etc/init.d/wifi_pre etc/init.d/wifi_ap etc/init.d/wifi_net \
         etc/init.d/tri_eth_up etc/init.d/custom_led_show \
         etc/init.d/sqm_cake etc/init.d/cake_autorate \
         www/luci-static/resources/view/mode.js \
         www/luci-static/resources/view/wisp.js \
         www/luci-static/resources/wisp_status.js \
         usr/share/luci/menu.d/luci-app-mode.json \
         usr/share/rpcd/acl.d/luci-app-mode.json \
         usr/share/rpcd/acl.d/luci-app-wisp.json \
         etc/banner etc/banner.art etc/wifi_after_eth \
         etc/uci-defaults/99-custom-led \
         etc/wifi/cfg_vspm3xx_board.ini etc/opkg/distfeeds.conf \
         lib/eth/cs_cli lib/eth/ethdbg.ko lib/eth/trihlp \
         lib/modules/5.10.138/tri_sdk_l2.ko \
         lib/upgrade/platform.sh.rawflash-only \
         etc/config/system etc/config/wisp etc/config/ucitrack \
         etc/init.d/wisp-dhcp etc/rc.d/S22wisp-dhcp \
         www/luci-static/resources/view/status/include/40_dhcp.js \
         usr/lib/lua/luci/version.lua; do
	if grep -qxF "squashfs-root/$f" "$OUTD/filelist.txt"; then
		echo "  OK $f"
	else
		echo "  MISSING $f" >&2
		exit 1
	fi
done
echo "== done"
