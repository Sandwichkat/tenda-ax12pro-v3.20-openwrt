# Out-of-tree Ethernet debug/poke module for the TR6560 build.
# KDIR and CROSS_COMPILE are supplied by scripts/build_eth_utils.sh.
obj-m += ethdbg.o

KDIR ?= /path/to/linux-5.10.138
CROSS_COMPILE ?= arm-triductor-linux-

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) clean
