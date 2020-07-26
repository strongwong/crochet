#!/bin/sh
#
# Shell script to copy FreeBSD system from SD Card to eMMC or NVMe
# Warning:  This erases the eMMC or NVMe before copying!

# Copy system to DISK
DISK="nda0"
DISK="mmcsd1"

# U-Boot source
UBOOT="u-boot-helios64"
UBOOT="u-boot-khadas-edge-e"
UBOOT="u-boot-nanopc-t4"
UBOOT="u-boot-rock-pi-4"
UBOOT="u-boot-rock-pi-e"
UBOOT="u-boot-rock-pi-n10"
UBOOT="u-boot-pinebook-pro"

UBOOT_PATH="/usr/local/share/u-boot"

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
gpart destroy -F ${DISK} 2> /dev/null

echo "Copying u-boot to /dev/${DISK}"
if [ -f ${UBOOT_PATH}/${UBOOT}/idbloader.img ] ; then
 dd if=${UBOOT_PATH}/${UBOOT}/idbloader.img of=/dev/${DISK} seek=64 bs=512 conv=sync
 dd if=${UBOOT_PATH}/${UBOOT}/u-boot.itb of=/dev/${DISK} seek=16384 bs=512 conv=sync
fi

echo
echo "Creating GPT on /dev/${DISK}"
gpart create -s GPT ${DISK}
gpart add -t efi -l efi -a 512k -s 50m -b 16m ${DISK}

echo 
echo "Creating FreeBSD partition on /dev/${DISK}"
gpart add -t freebsd-swap -s 4G -a 64k -l swapfs ${DISK}
gpart add -t freebsd-ufs        -a 64k -l rootfs ${DISK}

echo "Creating MSDOS boot FS on /dev/${DISK}"
newfs_msdos -L 'efi' /dev/${DISK}p1
mount_msdosfs /dev/${DISK}p1 /media

echo
echo "Copying loader efi to /dev/${DISK}"
mkdir -p /media/EFI/BOOT

cp /boot/loader.efi /media/EFI/BOOT/bootaa64.efi
cp -r /boot/dtb /media

if [ -f ${UBOOT_PATH}/${UBOOT}/splash.bmp ] ; then
	cp ${UBOOT_PATH}/${UBOOT}/splash.bmp /media
fi

sync; sync; sync
umount /media

newfs -L 'rootfs' /dev/${DISK}p3
tunefs -N enable -a enable -t enable -L 'rootfs' /dev/${DISK}p3
mount /dev/${DISK}p3 /media

echo
echo "Copying the system from SD to /dev/${DISK}" 
tar -cf - -C / \
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

echo
echo 'Cleaning up the copied system'
# Reset permissions, ensure the required directories
(cd /media ;             mtree -Uief /etc/mtree/BSD.root.dist)
(cd /media/usr ;         mtree -Uief /etc/mtree/BSD.usr.dist)
(cd /media/usr/include ; mtree -Uief /etc/mtree/BSD.include.dist)
(cd /media/var ;         mtree -Uief /etc/mtree/BSD.var.dist)

# Have the copied system generate its own keys
# (In particular, if this SD card is used to copy
# a system onto a bunch of BBBlacks, we do not want
# them to all have the same SSH keys.)
rm -f /media/etc/ssh/*key*

echo
echo "Replacing fstab on /dev/${DISK}" 
cat <<EOF >/media/etc/fstab
# Device	Mountpoint	FStype	Options			Dump    Pass#
/dev/gpt/efi	/boot/efi	msdosfs	rw,noauto		0	0
/dev/gpt/rootfs	/		ufs	rw,noatime		1	1
/dev/gpt/swapfs	none		swap	sw			0	0
fdesc		/dev/fd		fdescfs	rw			0	0
proc		/proc		procfs	rw			0	0
md		/var/log	mfs	rw,noatime,-s16m	0	0
md		/tmp		mfs	rw,noatime,-s256m	0	0
EOF

echo "/media/etc/fstab"
cat   /media/etc/fstab
echo
sync; sync; sync

echo
echo 'System copied.'
echo
echo "/dev/${DISK} root filesystem is still mounted on /media"
echo 'You can make changes there now before rebooting if you wish.'
echo
echo "To reboot from /dev/${DISK}:"
echo '  * Clean shutdown: shutdown -p now'
echo '  * Remove power'
echo '  * Remove SD card'
echo '  * Reapply power (do NOT hold boot switch)'

