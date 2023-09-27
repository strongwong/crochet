MAKE=bmake
KERNCONF=GENERIC
UBLDR_LOADADDR=0x42000000
TARGET_ARCH=riscv64
TARGET=riscv
FREEBSD_SRC=${TOPDIR}/../freebsd/src
FREEBSD_SYS=${FREEBSD_SRC}/sys
SRCCONF=${BOARDDIR}/src.conf
MFSROOT=$WORKDIR/mfsroot
MFSKERNEL=$WORKDIR/mfskernel

board_generate_image_name () {
}

board_default_partition_image () {
    echo "Do noting"
}

board_default_mount_partitions () {
  mkdir -p $BOARD_UFS_MOUNTPOINT_PREFIX
  mkdir -p $MFSROOT
  mkdir -p $MFSKERNEL
}

board_check_image_size_set () {
}

board_default_create_image ( ) {
}

freebsd_env_setup ( ) {
  BOARD_FREEBSD_MOUNTPOINT=$BOARD_UFS_MOUNTPOINT_PREFIX
}
strategy_add $PHASE_FREEBSD_START freebsd_env_setup

PRIORITY=10 strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_default_installkernel $MFSKERNEL

board_build_mfsroot () {
    echo ">>>>>>>>>>>>>>>>>>> cherry pick root <<<<<<<<<<<<<<<<<<<<<"
    mtree -N $FREEBSD_SRC/etc -deU -i -f $BOARDDIR/mtree/bl808.root.dist -p $MFSROOT
    mtree -N $FREEBSD_SRC/etc -deU -i -f $BOARDDIR/mtree/bl808.usr.dist -p $MFSROOT/usr
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/bin/* $MFSROOT/bin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/etc/rc $MFSROOT/etc
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/lib/lib* $MFSROOT/lib
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/libexec/ld-elf.so* $MFSROOT/libexec

    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/sbin/ifconfig $MFSROOT/sbin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/sbin/init $MFSROOT/sbin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/sbin/kld* $MFSROOT/sbin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/sbin/mdconfig $MFSROOT/sbin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/sbin/mount $MFSROOT/sbin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/sbin/sysctl $MFSROOT/sbin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/sbin/umount $MFSROOT/sbin

    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/login $MFSROOT/usr/bin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/env $MFSROOT/usr/bin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/su $MFSROOT/usr/bin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/top $MFSROOT/usr/bin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/systat $MFSROOT/usr/bin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/vmstat $MFSROOT/usr/bin
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/fstat $MFSROOT/usr/bin

    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/lib/librt.so* $MFSROOT/usr/lib
    install -C -o root -g wheel -m 444 $BOARD_FREEBSD_MOUNTPOINT/usr/share/locale/C.UTF-8/LC_CTYPE $MFSROOT/usr/share/locale/C.UTF-8

    # build freebsd root
    makefs -t ffs -R 1m -o label=mfsroot $WORKDIR/mfsroot.ufs $MFSROOT
}
PRIORITY=21 strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_build_mfsroot

board_build_kernel_img () {
  objcopy -O binary $MFSKERNEL/boot/kernel/kernel $WORKDIR/kernel_808.img
}

PRIORITY=30 strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_build_kernel_img

board_default_goodbye ( ) {
    echo "DONE."
    echo "BL808 root is: ${WORKDIR}/mfsroot"
    echo
}
