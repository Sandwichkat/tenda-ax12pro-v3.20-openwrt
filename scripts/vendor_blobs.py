#!/usr/bin/env python3
"""Local-only vendor blob / calibration extractor for the AX12 Pro build.

The release repo intentionally contains **no vendor binaries and no prebuilt
image**.  This tool extracts them on the user's machine from either:

  * the public BPI-SINOVOIP BSP repo (source of the prebuilt vendor files), or
  * the user's own device / their own rootfs dump (for fallback and for the
    per-device RF calibration, which is device-specific and kept local).

Output layout mirrors the rootfs (``lib/modules/...``, ``usr/sbin/...``,
``etc/wifi/...``) so it can be overlaid on the build root.  Calibration files
are kept separately under ``cal/`` and are local to your build.

Usage:
  vendor_blobs.py collect-bsp    <bsp-root>        <out-dir>
  vendor_blobs.py collect-rootfs <rootfs-dir>      <out-dir>
  vendor_blobs.py collect-device <ssh-host>        <out-dir>
  vendor_blobs.py collect-cal    <source-dir>      <out-dir>
  vendor_blobs.py manifest       <dir>
  vendor_blobs.py verify         <manifest>        <dir>

This script is the project's own work.  It does not contain or emit vendor
code into the repository; it copies files on the user's machine only.
"""

import argparse
import fnmatch
import glob
import hashlib
import os
import shutil
import subprocess
import sys
import tarfile

BSP_MODULE_DIR = "target/linux/tr6560/base-files/lib/modules/5.10.138"
BSP_PKG = "package/triductor/tr5220/files"
MODULE_REL = "lib/modules/5.10.138"

# Prebuilt modules shipped by the BSP (base-files) or the tr5220 package.
VENDOR_MODULE_GLOBS = (
    "tri_*.ko", "peanut_*.ko", "wifi_debug.ko", "wifi_kick.ko",
    "kgpio-tri6560.ko", "mdb-notify-multi.ko", "l2tp_nf_bp.ko",
)
# Userspace files from the vendor package.
VENDOR_USR_FILES = ("app_acs", "app_nlc", "app_sdt",
                    "create_ifname.sh", "extpriv.sh")
CAL_GLOBS = ("wifi_cali_data*.kv", "hi5622v100.cal")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def put(src, out, rel):
    dst = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    return rel


def is_cal(name):
    return any(fnmatch.fnmatch(name, pat) for pat in CAL_GLOBS)


def put_maybe_cal(src, out, rel_vendor=None, rel_cal=None):
    if is_cal(os.path.basename(src)):
        return put(src, out, rel_cal or os.path.join("cal",
                                                      os.path.basename(src)))
    return put(src, out, rel_vendor)


def write_manifest(out):
    vendor = []
    cal = []
    for root, _dirs, files in os.walk(out):
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, out)
            if rel in ("manifest.sha256", "cal/MANIFEST.sha256"):
                continue
            line = "%s  %s\n" % (sha256(path), rel)
            (cal if rel.startswith("cal" + os.sep) else vendor).append(line)
    with open(os.path.join(out, "manifest.sha256"), "w") as f:
        f.writelines(sorted(vendor))
    if cal:
        os.makedirs(os.path.join(out, "cal"), exist_ok=True)
        with open(os.path.join(out, "cal", "MANIFEST.sha256"), "w") as f:
            f.writelines(sorted(cal))
    print("manifest: %s (%d vendor files, %d cal files)" %
          (os.path.join(out, "manifest.sha256"), len(vendor), len(cal)))


def collect_bsp(bsp, out):
    if not os.path.isdir(os.path.join(bsp, BSP_PKG)):
        sys.exit("not a BSP tree (missing %s): %s" % (BSP_PKG, bsp))
    n = 0
    moddir = os.path.join(bsp, BSP_MODULE_DIR)
    for pat in VENDOR_MODULE_GLOBS:
        for src in glob.glob(os.path.join(moddir, pat)):
            put(src, out, os.path.join(MODULE_REL, os.path.basename(src)))
            n += 1
    pkg = os.path.join(bsp, BSP_PKG)
    for src in glob.glob(os.path.join(pkg, "bin", "*")):
        put(src, out, os.path.join("usr/sbin", os.path.basename(src)))
        n += 1
    for src in glob.glob(os.path.join(pkg, "config", "*")):
        if os.path.basename(src) == "Total.wdk":
            continue
        put(src, out, os.path.join("etc/wifi", os.path.basename(src)))
        n += 1
    for src in glob.glob(os.path.join(pkg, "ko", "*")):
        base = os.path.basename(src)
        if base == "Total.wdk":
            continue
        if base.endswith(".ko"):
            rel = os.path.join(MODULE_REL, base)
        elif base.endswith(".bin"):
            rel = os.path.join("etc/wifi", base)
        else:
            continue
        put(src, out, rel)
        n += 1
    mac = os.path.join(pkg, "lib", "netifd", "wireless", "mac80211.sh")
    if os.path.isfile(mac):
        put(mac, out, "lib/netifd/wireless/mac80211.sh")
        n += 1
    print("collected %d vendor files from BSP %s" % (n, bsp))
    write_manifest(out)


def collect_rootfs(rootfs, out):
    n = 0
    for pat in VENDOR_MODULE_GLOBS:
        for src in glob.glob(os.path.join(rootfs, MODULE_REL, pat)):
            put(src, out, os.path.join(MODULE_REL, os.path.basename(src)))
            n += 1
    for name in VENDOR_USR_FILES:
        src = os.path.join(rootfs, "usr/sbin", name)
        if os.path.isfile(src):
            put(src, out, os.path.join("usr/sbin", name))
            n += 1
    wifi = os.path.join(rootfs, "etc/wifi")
    for src in glob.glob(os.path.join(wifi, "*")):
        base = os.path.basename(src)
        if base == "Total.wdk":
            continue
        rel = os.path.join("etc/wifi", base)
        put_maybe_cal(src, out, rel_vendor=rel,
                      rel_cal=os.path.join("cal", base))
        n += 1
    mac = os.path.join(rootfs, "lib/netifd/wireless/mac80211.sh")
    if os.path.isfile(mac):
        put(mac, out, "lib/netifd/wireless/mac80211.sh")
        n += 1
    print("collected %d files from rootfs %s" % (n, rootfs))
    write_manifest(out)


def collect_device(host, out):
    remote = ["lib/modules/5.10.138", "usr/sbin", "etc/wifi",
              "lib/netifd/wireless/mac80211.sh"]
    cmd = ["ssh", "-o", "BatchMode=yes",
           "-o", "StrictHostKeyChecking=accept-new", host,
           "tar", "-C", "/", "-cf", "-"] + remote
    print("reading from %s ..." % host)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    n = 0
    with tarfile.open(fileobj=proc.stdout, mode="r|") as tar:
        for m in tar:
            if not m.isfile():
                continue
            name = m.name.lstrip("./")
            base = os.path.basename(name)
            if name.startswith("lib/modules/5.10.138/"):
                if not any(fnmatch.fnmatch(base, p)
                           for p in VENDOR_MODULE_GLOBS):
                    continue
                rel = os.path.join(MODULE_REL, base)
            elif name.startswith("usr/sbin/"):
                if base not in VENDOR_USR_FILES:
                    continue
                rel = os.path.join("usr/sbin", base)
            elif name == "lib/netifd/wireless/mac80211.sh":
                rel = name
            elif name.startswith("etc/wifi/"):
                if base == "Total.wdk":
                    continue
                rel = os.path.join("etc/wifi", base)
            else:
                continue
            if is_cal(base):
                rel = os.path.join("cal", base)
            dst = os.path.join(out, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with tar.extractfile(m) as src, open(dst, "wb") as f:
                shutil.copyfileobj(src, f)
            os.chmod(dst, m.mode & 0o777)
            n += 1
    if proc.wait() != 0:
        sys.exit("ssh/tar failed (rc=%d)" % proc.returncode)
    print("collected %d files from device %s" % (n, host))
    write_manifest(out)


def collect_cal(src, out):
    n = 0
    for pat in CAL_GLOBS:
        for path in glob.glob(os.path.join(src, pat)):
            put(path, out, os.path.join("cal", os.path.basename(path)))
            n += 1
    if not n:
        sys.exit("no calibration files (%s) under %s" %
                 (", ".join(CAL_GLOBS), src))
    print("collected %d calibration files to %s/cal (keep local)" %
          (n, out))


def verify(manifest, out):
    ok = 0
    bad = 0
    with open(manifest) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            digest, rel = line.split("  ", 1)
            path = os.path.join(out, rel)
            if not os.path.isfile(path):
                print("MISSING %s" % rel)
                bad += 1
            elif sha256(path) != digest:
                print("MISMATCH %s" % rel)
                bad += 1
            else:
                ok += 1
    print("verified %d files, %d problems" % (ok, bad))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name, help_ in (("collect-bsp", "BSP tree"),
                        ("collect-rootfs", "extracted rootfs"),
                        ("collect-device", "live device over ssh")):
        p = sub.add_parser(name, help="collect vendor files from " + help_)
        p.add_argument("source")
        p.add_argument("out")
    p = sub.add_parser("collect-cal", help="collect per-device calibration")
    p.add_argument("source")
    p.add_argument("out")
    p = sub.add_parser("manifest", help="write manifest.sha256")
    p.add_argument("dir")
    p = sub.add_parser("verify", help="verify against a manifest")
    p.add_argument("manifest")
    p.add_argument("dir")
    a = ap.parse_args()
    if a.cmd == "collect-bsp":
        collect_bsp(a.source, a.out)
    elif a.cmd == "collect-rootfs":
        collect_rootfs(a.source, a.out)
    elif a.cmd == "collect-device":
        collect_device(a.source, a.out)
    elif a.cmd == "collect-cal":
        collect_cal(a.source, a.out)
    elif a.cmd == "manifest":
        write_manifest(a.dir)
    elif a.cmd == "verify":
        sys.exit(verify(a.manifest, a.dir))


if __name__ == "__main__":
    main()
