#!/bin/bash
# Apply the project's BSP source patch and source additions to a pristine
# checkout of BPI-SINOVOIP/THG6500-TAX2-OPENWRT-BSP_TGP3 at c793463e.
#
# Usage: apply_patches.sh <bsp-root>
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REL=$(cd "$HERE/.." && pwd)
BSP=${1:?usage: $0 <bsp-root>}

[ -d "$BSP/.git" ] || { echo "ERROR: not a git checkout: $BSP" >&2; exit 1; }
[ -f "$REL/patches/0001-bsp-source.patch" ] || {
	echo "ERROR: missing $REL/patches/0001-bsp-source.patch" >&2; exit 1; }

echo "== apply tracked BSP source changes"
git -C "$BSP" apply --check "$REL/patches/0001-bsp-source.patch"
git -C "$BSP" apply "$REL/patches/0001-bsp-source.patch"

echo "== install untracked project source files"
cp -a "$REL/files/bsp/." "$BSP/"

echo "== project build config"
install -D -m 0644 "$REL/configs/tenda_ax12_pro.config" "$BSP/.config"
# CAKE is needed by the project's sqm_cake init script.  The kmod package
# installs sch_cake.ko and updates modules.dep.
if grep -q '^# CONFIG_PACKAGE_kmod-sched-cake is not set$' "$BSP/.config"; then
	sed -i 's/^# CONFIG_PACKAGE_kmod-sched-cake is not set$/CONFIG_PACKAGE_kmod-sched-cake=y/' "$BSP/.config"
elif ! grep -q '^CONFIG_PACKAGE_kmod-sched-cake=' "$BSP/.config"; then
	echo 'CONFIG_PACKAGE_kmod-sched-cake=y' >> "$BSP/.config"
fi
grep -n 'CONFIG_PACKAGE_kmod-sched-cake' "$BSP/.config"

echo "== CAKE kernel module"
KCFG="$BSP/target/linux/tr6560/norflash/config-5.10"
grep -q '^CONFIG_NET_SCHED=' "$KCFG" || echo 'CONFIG_NET_SCHED=y' >> "$KCFG"
grep -q '^CONFIG_NET_SCH_CAKE=' "$KCFG" || echo 'CONFIG_NET_SCH_CAKE=m' >> "$KCFG"
grep -n 'CONFIG_NET_SCH' "$KCFG" | tail -5

echo "applied to $BSP"
