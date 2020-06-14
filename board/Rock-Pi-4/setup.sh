#
KERNCONF=EXPERT
KERNCONF=FREENAS

TARGET=arm64
TARGET_ARCH=aarch64

UBOOT_DIR="u-boot-rock-pi-4"
UBOOT_PATH="/usr/local/share/u-boot/${UBOOT_DIR}"
UBOOT_BIN="u-boot.itb"

IMAGE_SIZE=$((1000 * 1000 * 1000))

rock-pi-4_check_uboot ( ) {
	uboot_port_test ${UBOOT_DIR} ${UBOOT_BIN}
}
strategy_add $PHASE_CHECK rock-pi-4_check_uboot

#
# Rock-Pi-4 uses EFI, so the first partition will be a FAT partition.
#
rock-pi-4_partition_image ( ) {
	echo "Installing Partitions on ${DISK_MD}"
	dd if=${UBOOT_PATH}/idbloader.img of=/dev/${DISK_MD} conv=sync bs=512 seek=64
	dd if=${UBOOT_PATH}/${UBOOT_BIN}  of=/dev/${DISK_MD} conv=sync bs=512 seek=16384
	disk_partition_mbr
	disk_fat_create 16m 16 1m
	disk_ufs_create
}
strategy_add $PHASE_PARTITION_LWW rock-pi-4_partition_image

# Build & install loader.efi.
strategy_add $PHASE_BUILD_OTHER  freebsd_loader_efi_build
strategy_add $PHASE_BOOT_INSTALL mkdir -p EFI/BOOT
strategy_add $PHASE_BOOT_INSTALL freebsd_loader_efi_copy EFI/BOOT/bootaa64.efi

# Rock-Pi-4 puts the kernel on the FreeBSD UFS partition.
strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_default_installkernel .

