#!/bin/sh
#
# Shell script to copy FreeBSD system from SD Card to eMMC or NVMe
# Warning:  This erases the eMMC or NVMe before copying!

DISK=nda0
DISK=mmcsd1

UBOOT_PATH="/usr/local/share/u-boot"

UBOOT="u-boot-helios64"
UBOOT="u-boot-khadas-edge-v"
UBOOT="u-boot-nanopc-t4"
UBOOT="u-boot-rock-pi-4"
UBOOT="u-boot-rock-pi-e"
UBOOT="u-boot-rock-pi-n10"
UBOOT="u-boot-pinebook-pro"

ZPOOL="zroot"

echo "Warning: This script erases /dev/${DISK}"
echo "It then copies your FreeBSD system from /dev/mmcsd0"
echo
echo 'If you booted from SD:'
echo '   /dev/mmcsd0 will refer to the micro-SD card'
echo "   /dev/${DISK} will refer to the DESTINATION"
echo
echo 'If you booted from eMMC, it will be the other way around'
echo '(Check the boot messages to verify your situation.)'
echo
echo 'If you are certain you want this script to erase stuff,'
echo 'edit the script, remove the "exit 1" command, and run it again.'

exit 1

echo
echo "Erasing /dev/${DISK}!  (Hope you meant this!)"

gpart destroy -F ${DISK} 
gpart create -s GPT ${DISK}

echo "Copying u-boot to /dev/${DISK}"
if [ -f ${UBOOT_PATH}/${UBOOT}/idbloader.img ] ; then
 dd if=${UBOOT_PATH}/${UBOOT}/idbloader.img of=/dev/${DISK} seek=64 bs=512 conv=sync
 dd if=${UBOOT_PATH}/${UBOOT}/u-boot.itb of=/dev/${DISK} seek=16384 bs=512 conv=sync
fi

gpart add -t efi -l efi -a 512k -s 50m -b 16m ${DISK}
gpart add -t freebsd-swap -s 4G -a 64k -l swapfs ${DISK}
gpart add -t freebsd-zfs        -a 64k -l rootfs ${DISK}

newfs_msdos -L 'efi' /dev/${DISK}p1
mount_msdosfs	     /dev/${DISK}p1 /media

echo
echo "Copying loader efi to /dev/${DISK}"
mkdir -p /media/EFI/BOOT

cp /boot/loader.efi  /media/EFI/BOOT/bootaa64.efi
cp -r /boot/dtb /media

if [ -f ${UBOOT_PATH}/${UBOOT}/splash.bmp ] ; then
        cp ${UBOOT_PATH}/${UBOOT}/splash.bmp /media
fi

sync; sync; sync
umount /media

zpool create -f -R /media -O mountpoint=none -O atime=off	${ZPOOL} /dev/${DISK}p3
zfs set compress=lz4 						${ZPOOL}
zfs create -o canmount=off	-o mountpoint=none		${ZPOOL}/ROOT
zfs create 			-o mountpoint=/			${ZPOOL}/ROOT/default

zpool set bootfs=${ZPOOL}/ROOT/default 				${ZPOOL}

echo
echo "Copying the system from SD to /dev/${DISK}"
tar -c -f - -C / \
	--exclude .sujournal \
	--exclude .snap \
	--exclude media \
	--exclude usr/obj \
	--exclude usr/src \
	--exclude usr/ports \
	--exclude var/run \
	. \
| tar -xf - -C /media

mkdir -p /media/media /media/var/run

echo 'vfs.zfs.arc_max="512M"' 				>> /media/boot/loader.conf
echo 'vfs.zfs.prefetch_disable=0'			>> /media/boot/loader.conf
echo 'vfs.root.mountfrom="ufs:/dev/gpt/rootfs"' 	>> /media/boot/loader.conf
echo 'vfs.root.mountfrom="zfs:zroot/ROOT/default"' 	>> /media/boot/loader.conf

echo 'zfs_enable="YES"'					>> /media/etc/rc.conf

chmod 1777 /media/tmp
chmod 1777 /media/var/tmp

cat << EOF > /media/etc/fstab
# Device	Mountpoint	FStype	Options			Dump	Pass#
/dev/gpt/efi	/boot/efi	msdosfs	rw,noauto		0	0
/dev/gpt/swapfs	none		swap	sw			0	0
fdesc		/dev/fd		fdescfs	rw			0	0
proc		/proc		procfs	rw			0	0
md		/var/log	mfs	rw,noatime,-s16m	0	0
md		/tmp		mfs	rw,noatime,-s256m	0	0
EOF

exit
