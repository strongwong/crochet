#
TARGET=arm64
TARGET_ARCH=aarch64
KERNCONF=EXPERT
SUNXI_UBOOT_DIR="u-boot-nanopi-k1-plus"
SUNXI_UBOOT_BIN="u-boot-sunxi-with-spl.bin "
UBOOT_PATH="/usr/local/share/u-boot/${SUNXI_UBOOT_DIR}"
IMAGE_SIZE=$((1000 * 1000 * 1000))

nanopi_k1_plus_check_uboot ( ) {
    uboot_port_test ${SUNXI_UBOOT_DIR} ${SUNXI_UBOOT_BIN}
}
strategy_add $PHASE_CHECK nanopi_k1_plus_check_uboot

#
# NanoPi K1 Plus uses EFI, so the first partition will be a FAT partition.
#
nanopi_k1_plus_partition_image ( ) {
    echo "Installing Partitions on ${DISK_MD}"
    dd if=${UBOOT_PATH}/${SUNXI_UBOOT_BIN} conv=sync of=/dev/${DISK_MD} bs=1024 seek=8 >/dev/null 2>&1
    disk_partition_mbr
    disk_fat_create 16m 16 1m
    disk_ufs_create
}
strategy_add $PHASE_PARTITION_LWW nanopi_k1_plus_partition_image

nanopi_k1_plus_populate_boot_partition ( ) {
    mkdir -p efi/boot
    echo bootaa64 > startup.nsh
    cp ${UBOOT_PATH}/${SUNXI_UBOOT_BIN} .
    cp ${UBOOT_PATH}/README .
}
strategy_add $PHASE_BOOT_INSTALL nanopi_k1_plus_populate_boot_partition

# Build & install loader.efi.
strategy_add $PHASE_BUILD_OTHER  freebsd_loader_efi_build
strategy_add $PHASE_BOOT_INSTALL mkdir -p efi efi/boot
strategy_add $PHASE_BOOT_INSTALL freebsd_loader_efi_copy efi/boot/bootaa64.efi

# NanoPi K1 Plus puts the kernel on the FreeBSD UFS partition.
strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_default_installkernel .

# overlay/etc/fstab mounts the FAT partition at /boot/msdos
strategy_add $PHASE_FREEBSD_BOARD_INSTALL mkdir -p boot/msdos

#
add_qemu ( ) {
    echo "Installing qemu-aarch64-static"
    mkdir -p ${BOARD_FREEBSD_MOUNTPOINT}/usr/local/bin
    cp -av /usr/local/bin/qemu-aarch64-static ${BOARD_FREEBSD_MOUNTPOINT}/usr/local/bin/.
}

del_qemu ( ) {
    echo "Removing qemu-aarch64-static"
    rm -v ${BOARD_FREEBSD_MOUNTPOINT}/usr/local/bin/qemu-aarch64-static
}

fix_dtb_path () {
    echo "Fix DTB path to ${BOARD_FREEBSD_MOUNTPOINT}/boot/dtb"
    DTBFILE="${BOARD_FREEBSD_MOUNTPOINT}/boot/dtb/allwinner/sun50i-h5-nanopi-k1-plus.dtb"
    if [ -f ${DTBFILE} ] ; then
	cp ${DTBFILE} ${BOARD_FREEBSD_MOUNTPOINT}/boot/dtb
    fi
}

PRIORITY=50  strategy_add $PHASE_FREEBSD_OPTION_INSTALL add_qemu
PRIORITY=150 strategy_add $PHASE_FREEBSD_OPTION_INSTALL del_qemu
PRIORITY=200 strategy_add $PHASE_FREEBSD_OPTION_INSTALL fix_dtb_path

