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
OPENSBI_SRC=$TOPDIR/../opensbi
BL_MCU_SDK_SRC=$TOPDIR/../bl_mcu_sdk
WAREHOSE_DIR=$TOPDIR/../out

# Override default function
board_check_image_size_set ( ) {
    return
}

board_default_create_image ( ) {
    return
}

board_generate_image_name ( ) {
    return
}

board_default_partition_image ( ) {
    return
}

build_tools ( ) {
  cc $BOARDDIR/tools/resolve_dep.c -g -lelf -o $BOARDDIR/tools/resolve_dep
}
strategy_add $PHASE_BUILD_TOOLS build_tools

build_opensbi ( ) {
    echo ">>>>>>>>>>>>>>>>>>> build OpenSBI <<<<<<<<<<<<<<<<<<<<<"
    gmake -C $OPENSBI_SRC PLATFORM=thead/c910 CROSS_COMPILE=riscv64-none-elf- -j 4 install
    cp $OPENSBI_SRC/install/platform/thead/c910/firmware/fw_jump.bin $WORKDIR/fw_jump.bin
}
strategy_add $PHASE_BUILD_OTHER build_opensbi

build_device_tree ( ) {
    echo ">>>>>>>>>>>>>>>>>>> build Device Tree <<<<<<<<<<<<<<<<<<<<<"
    dtc -I dts -O dtb -o $WORKDIR/bl808.dtb $BOARDDIR/bl808.dts
}
strategy_add $PHASE_BUILD_OTHER build_device_tree

build_spl ( ) {
    local CMAKE_DIR=$(dirname $(which cmake))
    echo ">>>>>>>>>>>>>>>>>>> build SPL <<<<<<<<<<<<<<<<<<<<<"
    env PATH=$BL_MCU_SDK_SRC/toolchain/FreeBSD_amd64/bin:$PATH \
    gmake -C $BL_MCU_SDK_SRC CHIP=bl808 CPU_ID=m0 CMAKE_DIR=$CMAKE_DIR \
      CROSS_COMPILE=riscv64-unknown-elf- SUPPORT_DUALCORE=y APP=low_load

    env PATH=$BL_MCU_SDK_SRC/toolchain/FreeBSD_amd64/bin:$PATH \
    gmake -C $BL_MCU_SDK_SRC CHIP=bl808 CPU_ID=d0 CMAKE_DIR=$CMAKE_DIR \
      CROSS_COMPILE=riscv64-unknown-elf- SUPPORT_DUALCORE=y APP=low_load
}
strategy_add $PHASE_BUILD_OTHER build_spl

board_default_mount_partitions ( ) {
    mkdir -p $BOARD_UFS_MOUNTPOINT_PREFIX
    mkdir -p $MFSROOT
    mkdir -p $MFSKERNEL
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

    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/bin/* $MFSROOT/bin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/etc/rc $MFSROOT/etc
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/libexec/ld-elf.so* $MFSROOT/libexec

    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/sbin/ifconfig $MFSROOT/sbin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/sbin/init $MFSROOT/sbin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/sbin/kld* $MFSROOT/sbin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/sbin/mdconfig $MFSROOT/sbin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/sbin/mount $MFSROOT/sbin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/sbin/sysctl $MFSROOT/sbin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/sbin/umount $MFSROOT/sbin

    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/login $MFSROOT/usr/bin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/env $MFSROOT/usr/bin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/su $MFSROOT/usr/bin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/top $MFSROOT/usr/bin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/systat $MFSROOT/usr/bin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/vmstat $MFSROOT/usr/bin
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/bin/fstat $MFSROOT/usr/bin

    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/share/locale/C.UTF-8/LC_CTYPE $MFSROOT/usr/share/locale/C.UTF-8

    # copy dependent libraries
    find $MFSROOT/bin $MFSROOT/usr/bin $MFSROOT/sbin -type f | xargs $BOARDDIR/tools/resolve_dep -L"lib:usr/lib" -C $BOARD_FREEBSD_MOUNTPOINT 1>$WORKDIR/dependency.list

    IFS=$'\n'       # make newlines the only separator
    set -f          # disable globbing
    for i in $(cat < "$WORKDIR/dependency.list"); do
      echo "Install: $i"
      install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/$i $MFSROOT/$i
    done

    # build freebsd root
    makefs -t ffs -R 1m -o label=mfsroot $WORKDIR/mfsroot.ufs $MFSROOT
    # compress freebsd root
    mkuzip -dS -A zstd -C 19 -o $WORKDIR/mfsroot.ufs.uzst $WORKDIR/mfsroot.ufs
}
PRIORITY=21 strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_build_mfsroot

board_build_kernel_img () {
    objcopy -O binary $MFSKERNEL/boot/kernel/kernel $WORKDIR/kernel.bin
    lz4 -9 -f $WORKDIR/kernel.bin $WORKDIR/kernel.bin.lz4
    cp $BOARDDIR/whole_img.its $WORKDIR/whole_img.its
    mkimage -f $WORKDIR/whole_img.its $WORKDIR/whole_img.itb

    # pack d0 with whole_img.itb image
    $BOARDDIR/patch_d0.perl "$BL_MCU_SDK_SRC/out/examples/low_load/low_load_bl808_d0.bin" "$WORKDIR/whole_img.itb"

    mkdir -p $WAREHOSE_DIR
    cp $BL_MCU_SDK_SRC/out/examples/low_load/low_load_bl808_d0.bin $WAREHOSE_DIR/bl808_freebsd_d0.bin
    cp $BL_MCU_SDK_SRC/out/examples/low_load/low_load_bl808_m0.bin $WAREHOSE_DIR/bl808_rtos_m0.bin
}
PRIORITY=30 strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_build_kernel_img

board_default_goodbye ( ) {
    echo "DONE."
    echo "BL808 root is: ${WORKDIR}/mfsroot"
    echo
}
