REQUIRE_IMAGE_METADATA=1
CI_UBIPART="rootfs_data"
ROOTFS_DATA_DEV=$(find_mtd_part $CI_UBIPART)

platform_do_upgrade() {
	local flagA="$(cat /proc/mtd | grep kernelA | wc -l)"
	local flagB="$(cat /proc/mtd | grep kernelB | wc -l)"
	UPG_DEV_CHAR=$(find_char_mtd_part upgflag)
	if [ "$flagA" = "0" -a "$flagB" = "0" ]; then
	    PART_NAME=firmware
		# echo A > /tmp/upgflag.tmp
	elif [ "$flagA" = "0" -a "$flagB" = "1" ]; then
		PART_NAME=firmwareB
		# echo B > /tmp/upgflag.tmp
	elif [ "$flagA" = "1" -a "$flagB" = "0" ]; then
		PART_NAME=firmwareA
		# echo A > /tmp/upgflag.tmp
	else
		echo "firmware startup error"
		exit 1
	fi
	
	FIRMWARE_DEV=$(find_char_mtd_part ${PART_NAME})
	mtd erase ${FIRMWARE_DEV}
	default_do_upgrade "$1"

	echo "upgrade software=${PART_NAME}"
	# mtd erase ${UPG_DEV_CHAR}
	# dd if=/tmp/upgflag.tmp of=/tmp/upgflag bs=1 count=1
	# mtd -f write /tmp/upgflag ${UPG_DEV_CHAR}

	if [ -z "$NO_REBOOT" -o "$NO_REBOOT" != "1" ]; then
	    if [ -z "$UPGRADE_BACKUP" ];then
		    MTD_index=$(find_mtd_index ${CI_UBIPART})
		    MTD_DEV=mtdblock${MTD_index}
		    SIZE=$(cat /proc/partitions | grep $MTD_DEV | awk -F' ' '{print $3}')
		    dd if=/dev/zero of="$ROOTFS_DATA_DEV" bs=1k count=$SIZE
		    echo "erase conffiles successful"
	    fi
	fi
}

platform_check_image() {
	local magic="$(get_magic_long "$1")"

	[ "$#" -gt 1 ] && return 1

	[ "$magic" != "d00dfeed" -a "$magic" != "27051956" ] && {
		echo "Invalid image type."
		return 1
	}
	return 0
}

platform_copy_config() {
	local magic
	[ -f "$UPGRADE_BACKUP" ] && {
		sync
		echo "sysupgrade conffiles successful"
	}
}
