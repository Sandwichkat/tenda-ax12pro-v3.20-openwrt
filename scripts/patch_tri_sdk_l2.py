#!/usr/bin/env python3
"""Locally apply the tri_sdk_l2.ko activation-check fix.

The vendor module runs an activation check every ~304 s and reboots the
router at uptime 3665 s when it fails.  The check ends in tri_shield_check
with:

    0xe68:  cmp r0, #0        (00 00 50 e3)
    0xe6c:  beq <failure>     (11 00 00 0a)

Force the success path by turning the compare into ``mov r0, #0`` and the
conditional branch into an unconditional branch with the same displacement:

    0xe68:  mov r0, #0        (00 00 a0 e3)
    0xe6c:  b   <same target> (11 00 00 ea)

This is a *local derivative* of the vendor binary.  The release repository
contains only this patch script; the patched module stays in your local
build.

Usage:
  patch_tri_sdk_l2.py <module.ko> [--output PATH]
  patch_tri_sdk_l2.py --check <module.ko>

Exit status for --check: 0 already patched, 1 unpatched, 2 unrecognised.
"""

import argparse
import hashlib
import sys

OFF_CMP = 0xE68
OFF_BEQ = 0xE6C
ORIG_CMP = bytes.fromhex("000050e3")
PATCH_CMP = bytes.fromhex("0000a0e3")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def classify(data):
    if len(data) < OFF_BEQ + 4:
        return "too-short"
    cmp_word = data[OFF_CMP:OFF_CMP + 4]
    beq_cond = data[OFF_BEQ + 3]
    if cmp_word == PATCH_CMP and beq_cond == 0xEA:
        return "patched"
    if cmp_word == ORIG_CMP and beq_cond == 0x0A:
        return "unpatched"
    return "unknown"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("module", help="tri_sdk_l2.ko")
    ap.add_argument("--check", action="store_true",
                    help="only report whether the fix is present")
    ap.add_argument("--output", help="write the patched module here "
                                     "(default: in place)")
    args = ap.parse_args()

    with open(args.module, "rb") as f:
        data = bytearray(f.read())
    state = classify(data)
    print("input: %s  size=%d  sha256=%s  state=%s" %
          (args.module, len(data), sha256(data), state))

    if args.check:
        sys.exit(0 if state == "patched" else 1 if state == "unpatched" else 2)
    if state == "patched":
        print("already patched; nothing to do")
        return
    if state != "unpatched":
        sys.exit("ERROR: unrecognised tri_shield_check bytes at 0x%x/0x%x; "
                 "refusing to patch" % (OFF_CMP, OFF_BEQ))

    data[OFF_CMP:OFF_CMP + 4] = PATCH_CMP
    data[OFF_BEQ + 3] = 0xEA  # AL condition, keep the branch displacement

    verify = classify(data)
    if verify != "patched":
        sys.exit("ERROR: internal patch verification failed (%s)" % verify)

    out = args.output or args.module
    with open(out, "wb") as f:
        f.write(data)
    print("patched: %s  size=%d  sha256=%s" %
          (out, len(data), sha256(data)))
    print("NOTE: local derivative of the vendor module; "
          "keep the patched module with your local build.")


if __name__ == "__main__":
    main()
