#!/bin/bash
# Reproducible source-only build for the Tenda AX12 Pro V3.2 release rootfs.
#
# What this does:
#   1. clones the public BPI-SINOVOIP BSP at c793463e (or uses a local copy);
#   2. applies this repo's BSP patch + source additions + defconfig;
#   3. builds the BSP (kernel, packages, root tree);
#   4. layers the sanitized project root files and optional local vendor
#      extraction over the built root tree;
#   5. applies the local activation patch to tri_sdk_l2.ko, builds the
#      project Ethernet helpers, and produces the squashfs + padded flash
#      image.
#
# No vendor binary, firmware, per-device calibration or image is stored in
# this repository.  Vendor files come from the public BSP checkout, and
# calibration comes from CAL_DIR (the user's own device/rootfs dump).
#
# Usage:
#   scripts/build_release.sh [--bsp DIR] [--bsp-source DIR]
#                            [--vendor DIR] [--cal DIR] [--out DIR]
#
# Environment: JOBS (default nproc), BSP_COMMIT, BSP_URL.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REL=$(cd "$HERE/.." && pwd)
BSP=${BSP:-$REL/bsp}
BSP_SOURCE=${BSP_SOURCE:-}
BSP_URL=${BSP_URL:-https://github.com/BPI-SINOVOIP/THG6500-TAX2-OPENWRT-BSP_TGP3}
BSP_COMMIT=${BSP_COMMIT:-c793463e}
JOBS=${JOBS:-$(nproc)}
OUTD=${OUTD:-$REL/out}
VENDOR=${VENDOR:-$REL/vendor}
CAL_DIR=${CAL_DIR:-$REL/cal}
SRC_ETH=$REL/files/project/eth
LOG=$REL/logs/build.log

while [ $# -gt 0 ]; do
	case "$1" in
		--bsp) BSP=$2; shift 2 ;;
		--bsp-source) BSP_SOURCE=$2; shift 2 ;;
		--vendor) VENDOR=$2; shift 2 ;;
		--cal) CAL_DIR=$2; shift 2 ;;
		--out) OUTD=$2; shift 2 ;;
		-h|--help) sed -n '2,30p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

mkdir -p "$OUTD" "$REL/logs"

if [ ! -d "$BSP/.git" ]; then
	if [ -d "$BSP_SOURCE/.git" ]; then
		echo "== cloning BSP from local $BSP_SOURCE"
		git clone --local "$BSP_SOURCE" "$BSP"
	else
		echo "== cloning BSP from $BSP_URL"
		git clone "$BSP_URL" "$BSP"
	fi
	git -C "$BSP" checkout "$BSP_COMMIT"
fi

if [ ! -f "$BSP/.release-applied" ]; then
	echo "== applying project patches"
	"$HERE/apply_patches.sh" "$BSP"
	touch "$BSP/.release-applied"
else
	echo "== project patches already applied"
fi

# Reuse the download cache if the local BSP has one; this does not affect
# the source tree or the build outputs.
if [ -d "$BSP_SOURCE/dl" ] && [ ! -e "$BSP/dl" ]; then
	ln -s "$BSP_SOURCE/dl" "$BSP/dl"
fi

echo "== building BSP (log: $LOG)"
if ! ( cd "$BSP" && make defconfig && make -j"$JOBS" ) > "$LOG" 2>&1; then
	echo "ERROR: BSP build failed" >&2
	tail -100 "$LOG" >&2
	exit 1
fi

ROOT=$BSP/build_dir/target-arm_cortex-a9_musl_eabi/root-tr6560
[ -d "$ROOT" ] || { echo "ERROR: built root tree missing: $ROOT" >&2; exit 1; }

echo "== layering extracted vendor files"
if [ -d "$VENDOR" ]; then
	for d in etc lib usr; do
		if [ -d "$VENDOR/$d" ]; then
			mkdir -p "$ROOT/$d"
			cp -a "$VENDOR/$d/." "$ROOT/$d/"
		fi
	done
else
	echo "   no $VENDOR; using the public BSP's vendor files"
fi

echo "== layering project rootfs files"
cp -a "$REL/rootfs-overlay/." "$ROOT/"

# Sysupgrade is raw-flash only on this device; disable the LuCI upload path
# (sysupgrade -b backup still works).
rm -f "$ROOT/lib/upgrade/platform.sh"

# The kmod-sched-cake package normally installs this.  If the package was
# not selected, use the module the kernel build produced; sqm_cake insmods
# it by path, so modules.dep is not required.
if [ ! -s "$ROOT/lib/modules/5.10.138/sch_cake.ko" ]; then
	SCH_CAKE=$(find "$BSP/build_dir" -path '*linux-tr6560_norflash*' \
		-name sch_cake.ko -print -quit 2>/dev/null || true)
	if [ -n "$SCH_CAKE" ]; then
		install -D -m 0644 "$SCH_CAKE" "$ROOT/lib/modules/5.10.138/sch_cake.ko"
		echo "installed sch_cake.ko from the kernel build"
	else
		echo "WARNING: sch_cake.ko not found; check CONFIG_NET_SCH_CAKE=m" >&2
	fi
fi

echo "== activation fix (local derivative; never committed)"
python3 "$HERE/patch_tri_sdk_l2.py" "$ROOT/lib/modules/5.10.138/tri_sdk_l2.ko"

echo "== Ethernet helpers"
"$HERE/build_eth_utils.sh" "$BSP" "$ROOT" "$SRC_ETH"

echo "== rootfs image"
BSP=$BSP ROOT=$ROOT OUTD=$OUTD CAL_DIR=$CAL_DIR "$HERE/build_rootfs.sh"

echo
echo "== done"
ls -l "$OUTD"/rootfs_release* 2>/dev/null || true
