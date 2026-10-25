// ethdbg: MDIO (0x14000000) + ETH-related CRG experiments via /proc/ethdbg.
//
// Protocol reverse-engineered from retail hi_kmdio.ko (Linux 5.10.201):
//   read : wait ((0x2c>>16)&7)==0 ; 0x30 = ((0x8000|(reg<<8)|phy)<<16)
//          wait 0x20 & 3 ; 0x20 = rd(0x20) (clear) ; wait ((0x2c>>16)&7)==0
//          data = 0x38 & 0xffff
//   write: wait ((0x2c>>16)&7)==0 ; 0x30 = ((0xC000|(reg<<8)|phy)<<16) | val
//          wait 0x20 & 3 ; 0x20 = rd(0x20) (clear)
//
// Commands (results to kernel log, read with dmesg):
//   echo "r <phy> <reg>"          > /proc/ethdbg    MDIO clause22 read
//   echo "w <phy> <reg> <val>"    > /proc/ethdbg    MDIO clause22 write
//   echo "rr <phy> <reg>"         > /proc/ethdbg    read, print as R line (compact)
//   echo "scan"                   > /proc/ethdbg    read reg1 of phy 0..31
//   echo "raw <addr>"             > /proc/ethdbg    raw 32-bit read
//   echo "set <addr> <val>"       > /proc/ethdbg    raw 32-bit write
//   echo "pulse"                  > /proc/ethdbg    CRG+0x30: assert(0) then deassert(1)
//                                                 bits 6,26..31 (mdio+gephy resets)
//   echo "pulsebits <mask>"       > /proc/ethdbg    same, custom bit mask
//   echo "clkon"                  > /proc/ethdbg    CRG+0x20 |= bit3 (mdio_clk0)
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/delay.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Kat");
MODULE_DESCRIPTION("ETH/MDIO debug via /proc/ethdbg");

#define MDIO_BASE 0x14000000
#define CRG_BASE  0x14880000

static u32 rd32(u32 phys)
{
    void __iomem *b = ioremap(phys & ~0xfffUL, 0x1000);
    u32 v;
    if (!b)
        return 0xdeadbeef;
    v = readl(b + (phys & 0xfff));
    iounmap(b);
    return v;
}

static void wr32(u32 phys, u32 val)
{
    void __iomem *b = ioremap(phys & ~0xfffUL, 0x1000);
    if (!b)
        return;
    writel(val, b + (phys & 0xfff));
    (void)readl(b + (phys & 0xfff));
    iounmap(b);
}

static int mdio_wait_idle(u32 base, int loops)
{
    int i;
    for (i = 0; i < loops; i++) {
        if (((rd32(base + 0x2c) >> 16) & 7) == 0)
            return 0;
        udelay(10);
    }
    return -1;
}

static int mdio_wait_done(u32 base, int loops)
{
    int i;
    for (i = 0; i < loops; i++) {
        if (rd32(base + 0x20) & 3)
            return 0;
        udelay(10);
    }
    return -1;
}

static int mdio_read(u32 base, int phy, int reg, u32 *out)
{
    u32 v;
    if (mdio_wait_idle(base, 10000))
        return -1;
    wr32(base + 0x30, (u32)(0x8000 | ((reg & 0x1f) << 8) | (phy & 0x1f)) << 16);
    if (mdio_wait_done(base, 10000))
        return -2;
    v = rd32(base + 0x20);
    wr32(base + 0x20, v);
    if (mdio_wait_idle(base, 10000))
        return -3;
    *out = rd32(base + 0x38) & 0xffff;
    return 0;
}

static int mdio_write(u32 base, int phy, int reg, u32 val)
{
    u32 v;
    if (mdio_wait_idle(base, 10000))
        return -1;
    wr32(base + 0x30, (u32)(0xC000 | ((reg & 0x1f) << 8) | (phy & 0x1f)) << 16 |
                      (val & 0xffff));
    if (mdio_wait_done(base, 10000))
        return -2;
    v = rd32(base + 0x20);
    wr32(base + 0x20, v);
    return 0;
}

static ssize_t ethdbg_write(struct file *f, const char __user *ubuf,
                            size_t len, loff_t *off)
{
    char buf[128];
    char op[16];
    u32 a = 0, b = 0, c = 0;
    int n;

    if (len >= sizeof(buf))
        len = sizeof(buf) - 1;
    if (copy_from_user(buf, ubuf, len))
        return -EFAULT;
    buf[len] = '\0';

    n = sscanf(buf, " %15s %x %x %x", op, &a, &b, &c);
    if (n < 1) {
        pr_info("ethdbg: parse error\n");
        return len;
    }

    if (!strcmp(op, "r") || !strcmp(op, "rr")) {
        u32 v = 0;
        int rc = mdio_read(MDIO_BASE, a, b, &v);
        pr_info("ethdbg: MDIO R phy=%u reg=%u rc=%d val=0x%04x\n", a, b, rc, v);
    } else if (!strcmp(op, "w")) {
        int rc = mdio_write(MDIO_BASE, a, b, c);
        pr_info("ethdbg: MDIO W phy=%u reg=%u val=0x%04x rc=%d\n", a, b, c, rc);
    } else if (!strcmp(op, "scan")) {
        int phy;
        for (phy = 0; phy < 32; phy++) {
            u32 v = 0;
            int rc = mdio_read(MDIO_BASE, phy, 1, &v);
            if (rc == 0)
                pr_info("ethdbg: SCAN phy=%d reg1=0x%04x\n", phy, v);
            else
                pr_info("ethdbg: SCAN phy=%d rc=%d\n", phy, rc);
        }
    } else if (!strcmp(op, "raw")) {
        pr_info("ethdbg: RAW 0x%08x = 0x%08x\n", a, rd32(a));
    } else if (!strcmp(op, "dd")) {
        u32 i, words = b ? b : 64;
        if (words > 2048)
            words = 2048;
        for (i = 0; i < words; i += 4) {
            u32 p = a + i * 4;
            pr_info("ethdbg: DD %08x: %08x %08x %08x %08x\n",
                    p, rd32(p), rd32(p + 4), rd32(p + 8), rd32(p + 12));
        }
        pr_info("ethdbg: DD end %08x\n", a + words * 4);
    } else if (!strcmp(op, "clear")) {
        u32 old = rd32(a);
        u32 now = old & ~b;
        wr32(a, now);
        pr_info("ethdbg: CLEAR 0x%08x &= ~0x%08x (old 0x%08x now 0x%08x)\n",
                a, b, old, rd32(a));
    } else if (!strcmp(op, "set")) {
        wr32(a, b);
        pr_info("ethdbg: SET 0x%08x <= 0x%08x (now 0x%08x)\n", a, b, rd32(a));
    } else if (!strcmp(op, "pulse") || !strcmp(op, "pulsebits")) {
        u32 mask = (n >= 2) ? a : 0xFC000040; /* bits 6,26..31 */
        u32 old = rd32(CRG_BASE + 0x30);
        u32 save = old & mask;
        wr32(CRG_BASE + 0x30, old & ~mask);
        pr_info("ethdbg: PULSE crg30 0x%08x -> 0x%08x (assert)\n", old, rd32(CRG_BASE + 0x30));
        mdelay(50);
        wr32(CRG_BASE + 0x30, (old & ~mask) | save);
        pr_info("ethdbg: PULSE crg30 released -> 0x%08x\n", rd32(CRG_BASE + 0x30));
        mdelay(50);
    } else if (!strcmp(op, "clkon")) {
        u32 old = rd32(CRG_BASE + 0x20);
        wr32(CRG_BASE + 0x20, old | 0x8);
        pr_info("ethdbg: CLKON crg20 0x%08x -> 0x%08x\n", old, rd32(CRG_BASE + 0x20));
    } else {
        pr_info("ethdbg: unknown op '%s'\n", op);
    }
    return len;
}

static const struct proc_ops ethdbg_ops = {
    .proc_write = ethdbg_write,
};

static struct proc_dir_entry *ent;

static int __init ethdbg_init(void)
{
    ent = proc_create("ethdbg", 0666, NULL, &ethdbg_ops);
    if (!ent)
        return -ENOMEM;
    pr_info("ethdbg: /proc/ethdbg ready\n");
    return 0;
}

static void __exit ethdbg_exit(void)
{
    proc_remove(ent);
    pr_info("ethdbg: unloaded\n");
}

module_init(ethdbg_init);
module_exit(ethdbg_exit);
