#!/bin/bash
# Build the project's Ethernet userspace/kernel helpers and install them in
# a built BSP root tree:
#   lib/eth/ethdbg.ko  out-of-tree debug/poke module (project source)
#   lib/eth/trihlp     /dev/tri_hlp ioctl helper (project source)
#   lib/eth/cs_cli     vendor CLI copied from the public BSP's own tree
#
# Usage: build_eth_utils.sh <bsp-root> <root-tree> <source-dir>
set -euo pipefail

BSP=${1:?usage: $0 <bsp-root> <root-tree> <source-dir>}
ROOT=${2:?}
SRC=${3:?}

KERNEL=$(ls -d "$BSP"/build_dir/target-*/linux-tr6560_norflash/linux-5.10.138 2>/dev/null | head -1 || true)
[ -n "$KERNEL" ] && [ -d "$KERNEL" ] || {
	echo "ERROR: kernel build tree not found under $BSP/build_dir" >&2; exit 1; }

CROSS=$(ls "$BSP"/staging_dir/toolchain-*/bin/arm-triductor-linux-gcc 2>/dev/null | head -1 || true)
[ -n "$CROSS" ] && [ -x "$CROSS" ] || {
	echo "ERROR: cross gcc not found under $BSP/staging_dir" >&2; exit 1; }
CROSS_PREFIX=${CROSS%gcc}
export STAGING_DIR="$BSP/staging_dir"

mkdir -p "$ROOT/lib/eth"

echo "== ethdbg.ko"
make -C "$SRC" KDIR="$KERNEL" CROSS_COMPILE="$CROSS_PREFIX" clean >/dev/null 2>&1 || true
make -C "$SRC" KDIR="$KERNEL" CROSS_COMPILE="$CROSS_PREFIX" all
install -D -m 0644 "$SRC/ethdbg.ko" "$ROOT/lib/eth/ethdbg.ko"

echo "== trihlp"
"${CROSS_PREFIX}gcc" -Os -s -o "$ROOT/lib/eth/trihlp" "$SRC/trihlp.c"
chmod 0755 "$ROOT/lib/eth/trihlp"

echo "== cs_cli (vendor, copied from the BSP tree -- not stored in this repo)"
install -D -m 0755 "$BSP/target/linux/tr6560/base-files/bin/cs_cli" \
	"$ROOT/lib/eth/cs_cli"

echo "== clean module build residue"
make -C "$SRC" KDIR="$KERNEL" CROSS_COMPILE="$CROSS_PREFIX" clean >/dev/null 2>&1 || true
rm -f "$SRC"/.*.cmd "$SRC"/Module.symvers "$SRC"/modules.order \
      "$SRC"/ethdbg.ko "$SRC"/ethdbg.mod "$SRC"/ethdbg.mod.c \
      "$SRC"/ethdbg.mod.o "$SRC"/ethdbg.o

ls -l "$ROOT/lib/eth"
