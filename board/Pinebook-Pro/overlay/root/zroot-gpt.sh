# Now it’s a regular installation process!
# When asked about partitioning, choose Shell, 
# and manually add a partition and set up a root filesystem:

DISK=nda0
DISK=mmcsd1

UBOOT_PATH="/usr/local/share/u-boot"

UBOOT="u-boot-helios64"
UBOOT="u-boot-rock-pi-4"
UBOOT="u-boot-nanopc-t4"
UBOOT="u-boot-khadas-edge-v"
UBOOT="u-boot-pinebook-pro"

ZPOOL="zroot"

echo "Warning: This script erases /dev/${DISK}"
echo "It then copies your FreeBSD system from /dev/mmcsd0"
echo
echo 'If you booted from SD:'
echo '   /dev/mmcsd0 will refer to the micro-SD card'
echo "   /dev/${DISK} will refer to the eMMC"
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

echo 'Copying u-boot to eMMC '
if [ -f ${UBOOT_PATH}/${UBOOT}/idbloader.img ] ; then
 echo 'Copying u-boot to eMMC idbloader.img'
 dd if=${UBOOT_PATH}/${UBOOT}/idbloader.img of=/dev/${DISK} seek=64 bs=512 conv=sync
 echo 'Copying u-boot to eMMC u-boot.itb'
 dd if=${UBOOT_PATH}/${UBOOT}/u-boot.itb of=/dev/${DISK} seek=16384 bs=512 conv=sync
fi

gpart add -t efi -l efi -a 512k -s 50m -b 16m ${DISK}
gpart add -t freebsd-swap -s 8G -a 64k -l swapfs ${DISK}
gpart add -t freebsd-zfs        -a 64k -l rootfs ${DISK}

newfs_msdos -L 'efi' /dev/${DISK}p1
mount_msdosfs	     /dev/${DISK}p1 /media

echo
echo 'Copying efi-boot to eMMC '
mkdir -p /media/EFI/BOOT

cp /boot/boot1.efi  /media/EFI/BOOT/bootaa64.efi
cp -r /boot/dtb /media

sync; sync; sync
umount /media

zpool create -f -R /media -O mountpoint=none -O atime=off	${ZPOOL} /dev/${DISK}p3
zfs set compress=lz4 						${ZPOOL}
zfs create -o canmount=off	-o mountpoint=none		${ZPOOL}/ROOT
zfs create 			-o mountpoint=/			${ZPOOL}/ROOT/default

zpool set bootfs=${ZPOOL}/ROOT/default 				${ZPOOL}

echo
echo 'Copying the system from SD to eMMC'
tar -c -f - -C / \
	--exclude .sujournal \
	--exclude .snap \
	--exclude media \
	--exclude usr/obj \
	--exclude usr/src \
	--exclude usr/ports \
	--exclude var/run \
	. \
| tar -xvf - -C /media

mkdir -p /media/media /media/var/run

echo 'opensolaris_load="YES"'				>> /media/boot/loader.conf
echo 'zfs_load="YES"'					>> /media/boot/loader.conf
echo 'vfs.zfs.arc_max="512M"' 				>> /media/boot/loader.conf
echo 'vfs.zfs.prefetch_disable=0'			>> /media/boot/loader.conf
echo 'vfs.root.mountfrom="zfs:zroot/ROOT/default"' 	>> /media/boot/loader.conf

echo 'zfs_enable="YES"'					>> /media/etc/rc.conf

chmod 1777 /media/tmp
chmod 1777 /media/var/tmp

cat << EOF > /media/etc/fstab
# Device		Mountpoint	FStype	Options			Dump	Pass#
/dev/gpt/efi		/boot/efi	msdosfs	rw,noauto		0	0
/dev/gpt/swapfs		none		swap	sw			0	0
md			/tmp		mfs	rw,noatime,-s128m	0	0
md			/var/log	mfs	rw,noatime,-s16m	0	0
EOF

exit
