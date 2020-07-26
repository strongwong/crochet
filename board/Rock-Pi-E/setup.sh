#

TARGET=arm64
TARGET_ARCH=aarch64

UBOOT_DIR="u-boot-rock-pi-e"
UBOOT_PATH="/usr/local/share/u-boot/${UBOOT_DIR}"
UBOOT_BIN="u-boot.itb"

rock-pi-e_check_uboot ( ) {
	uboot_port_test ${UBOOT_DIR} ${UBOOT_BIN}
}
strategy_add $PHASE_CHECK rock-pi-e_check_uboot

#
# Rock-Pi-E uses EFI, so the first partition will be a FAT partition.
#
rock-pi-e_partition_image ( ) {
	echo "Installing Partitions on ${DISK_MD}"
	dd if=${UBOOT_PATH}/idbloader.img of=/dev/${DISK_MD} conv=sync bs=512 seek=64
	dd if=${UBOOT_PATH}/${UBOOT_BIN}  of=/dev/${DISK_MD} conv=sync bs=512 seek=16384

        echo "Installing Partitions on ${DISK_MD}"
        disk_partition_gpt
        disk_partition_efi_create
        disk_partition_swap_create 1g
        disk_partition_ufs_create
}
strategy_add $PHASE_PARTITION_LWW rock-pi-e_partition_image

# Build & install loader.efi.
strategy_add $PHASE_BUILD_OTHER  freebsd_loader_efi_build
strategy_add $PHASE_BOOT_INSTALL mkdir -p EFI/BOOT
strategy_add $PHASE_BOOT_INSTALL freebsd_loader_efi_copy EFI/BOOT/bootaa64.efi
strategy_add $PHASE_BOOT_INSTALL cp ${UBOOT_PATH}/splash.bmp .

# Puts the kernel on the FreeBSD UFS partition.
strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_default_installkernel .

fix_dtb_path () {
        echo "Fix DTB path to ${BOARD_FREEBSD_MOUNTPOINT}/boot/dtb"
        DTBFILE="${BOARD_FREEBSD_MOUNTPOINT}/boot/dtb/rockchip/rk3328-rock-pi-e.dtb"
        if [ -f ${DTBFILE} ] ; then
                cp ${DTBFILE} ${BOARD_FREEBSD_MOUNTPOINT}/boot/dtb
        fi
}

PRIORITY=30 strategy_add $PHASE_FREEBSD_OPTION_INSTALL fix_dtb_path

