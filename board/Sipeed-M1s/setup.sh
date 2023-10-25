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
BOUFFALO_SDK_SRC=$TOPDIR/../bouffalo_sdk
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
    echo ">>>>>>>>>>>>>>>>>>> build SPL <<<<<<<<<<<<<<<<<<<<<"
    env PATH=$TOPDIR/../prebuilts/t-head-xuantie-gcc-freebsd/FreeBSD_amd64/bin:$PATH \
      gmake -C $BOUFFALO_SDK_SRC/examples/freebsd_loader
}
strategy_add $PHASE_BUILD_OTHER build_spl

board_default_mount_partitions ( ) {
    mkdir -p $BOARD_UFS_MOUNTPOINT_PREFIX
    mkdir -p $MFSROOT
    mkdir -p $MFSKERNEL
}

freebsd_env_setup ( ) {
    BOARD_FREEBSD_MOUNTPOINT=$BOARD_UFS_MOUNTPOINT_PREFIX
    $MAKE -C $FREEBSD_SRC TARGET_ARCH=$TARGET_ARCH TARGET=$TARGET buildenvvars > $WORKDIR/env.sh
}
strategy_add $PHASE_FREEBSD_START freebsd_env_setup

PRIORITY=10 strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_default_installkernel $MFSKERNEL

board_build_mfsroot () {
    echo ">>>>>>>>>>>>>>>>>>> cherry pick root <<<<<<<<<<<<<<<<<<<<<"
    mtree -N $FREEBSD_SRC/etc -deU -i -f $BOARDDIR/mtree/bl808.root.dist -p $MFSROOT
    mtree -N $FREEBSD_SRC/etc -deU -i -f $BOARDDIR/mtree/bl808.usr.dist -p $MFSROOT/usr

    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/etc/rc $MFSROOT/etc
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/etc/motd $MFSROOT/etc
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
    install -C -o root -g wheel -m 555 $BOARD_FREEBSD_MOUNTPOINT/usr/share/misc/termcap* $MFSROOT/usr/share/misc

    # install user app
    find $BOARD_FREEBSD_MOUNTPOINT/bin -type f | xargs -I {} \
      install -C -o root -g wheel -m 555 {} $MFSROOT/bin

    find $BOARD_FREEBSD_MOUNTPOINT/usr/local/bin -type f | xargs -I {} \
      install -C -o root -g wheel -m 555 {} $MFSROOT/usr/local/bin

    # copy dependent libraries
    find $MFSROOT/bin $MFSROOT/usr/bin $MFSROOT/sbin $MFSROOT/usr/local/bin -type f | \
      xargs $BOARDDIR/tools/resolve_dep -L"lib:usr/lib" -C $BOARD_FREEBSD_MOUNTPOINT 1>$WORKDIR/dependency.list

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
    cp "$BOUFFALO_SDK_SRC/examples/freebsd_loader/loader_d0/build/build_out/loader_d0_bl808_d0.bin" "$WORKDIR/low_load_bl808_d0.bin"
    $BOARDDIR/patch_d0.perl "$WORKDIR/low_load_bl808_d0.bin" "$WORKDIR/whole_img.itb"

    mkdir -p $WAREHOSE_DIR
    cp $WORKDIR/low_load_bl808_d0.bin $WAREHOSE_DIR/bl808_freebsd_d0.bin
    cp $BOUFFALO_SDK_SRC/examples/freebsd_loader/rtos_m0/build/build_out/rtos_m0_bl808_m0.bin $WAREHOSE_DIR/bl808_rtos_m0.bin
}
PRIORITY=30 strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_build_kernel_img

board_default_goodbye ( ) {
    if [ -d $BOARDDIR/overlay ] && [ ! -L $TOPDIR/../overlay ]; then
        ln -s $BOARDDIR/overlay $TOPDIR/../overlay
    fi
    echo
    echo "DONE."
    echo "BL808 RTOS bin is: `realpath $WAREHOSE_DIR/bl808_rtos_m0.bin`"
    echo "BL808 FreeBSD bin is: `realpath $WAREHOSE_DIR/bl808_freebsd_d0.bin`"
    echo
    echo "The application environment has been deployed and you can try it now:"
    echo "  make apps/helloworld/install"
    echo "  make"
    echo
}
