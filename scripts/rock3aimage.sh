#!/bin/sh

# Default build for Debian 32bit
ARCH="armv8"

while getopts ":v:p:a:" opt; do
  case $opt in
    v)
      VERSION=$OPTARG
      ;;
    p)
      PATCH=$OPTARG
      ;;
    a)
      ARCH=$OPTARG
      ;;
  esac
done

BUILDDATE=$(date -I)
IMG_FILE="Volumio${VERSION}-${BUILDDATE}-rock3a.img"

if [ "$ARCH" = arm ]; then
  DISTRO="Raspbian"
else
  DISTRO="Debian 32bit"
fi

echo "Creating Image File ${IMG_FILE} with $DISTRO rootfs"
dd if=/dev/zero of=${IMG_FILE} bs=1M count=2800

echo "Creating Image Bed"
LOOP_DEV=`sudo losetup -f --show ${IMG_FILE}`

parted -s "${LOOP_DEV}" mklabel gpt
parted -s "${LOOP_DEV}" mkpart primary fat16 16 128
parted -s "${LOOP_DEV}" mkpart primary ext3 129 2500
parted -s "${LOOP_DEV}" mkpart primary ext3 2501 100%
parted -s "${LOOP_DEV}" set 1 boot on
parted -s "${LOOP_DEV}" set 1 legacy_boot on
parted -s "${LOOP_DEV}" name 1 boot
parted -s "${LOOP_DEV}" name 2 rootfs
parted -s "${LOOP_DEV}" print
partprobe "${LOOP_DEV}"
kpartx -s -a "${LOOP_DEV}"

BOOT_PART=`echo /dev/mapper/"$( echo ${LOOP_DEV} | sed -e 's/.*\/\(\w*\)/\1/' )"p1`
SYS_PART=`echo /dev/mapper/"$( echo ${LOOP_DEV} | sed -e 's/.*\/\(\w*\)/\1/' )"p2`
DATA_PART=`echo /dev/mapper/"$( echo ${LOOP_DEV} | sed -e 's/.*\/\(\w*\)/\1/' )"p3`
echo "Using: " ${BOOT_PART}
echo "Using: " ${SYS_PART}
echo "Using: " ${DATA_PART}
if [ ! -b "${BOOT_PART}" ]
then
	echo "${BOOT_PART} doesn't exist"
	exit 1
fi

echo "Creating boot and rootfs filesystems"
mkfs -t vfat -n BOOT "${BOOT_PART}"
mkfs -F -t ext4 -L volumio "${SYS_PART}"
mkfs -F -t ext4 -L volumio_data "${DATA_PART}"
sync

echo "Preparing for the rock3a kernel/ platform files"
if [ -d platform-rock3a ]
then
	echo "Platform folder already exists - keeping it"
    # if you really want to re-clone from the repo, then delete the platform-rock3a folder
    # that will refresh all the odroid platforms, see below
  rm -rf platform-rock3a/*
  cp ../buildroot-rockpi-3a/output/images/rock3a.tar.xz platform-rock3a/
	cd platform-rock3a
	if [ ! -d rock3a ]; then
	   tar xfJ rock3a.tar.xz
	fi
	cd ..
else
	echo "Clone all rock3a files from repo"
	git clone --depth 1 https://github.com/GASB0/Platform-rock3a.git platform-rock3a
	echo "Unpack the rock3a platform files"
    cd platform-rock3a
	tar xfJ rock3a.tar.xz
	cd ..
fi

echo "Copying the bootloader"
# FIXME: Problems regarding mounting seem to originate from here
dd if=platform-rock3a/rock3a/u-boot/idbloader.bin seek=64 of=${LOOP_DEV} status=progress
dd if=platform-rock3a/rock3a/u-boot/uboot.img seek=16384 of=${LOOP_DEV} status=progress
# dd if=platform-rock3a/rock3a/u-boot/trust.bin seek=24576 of=${LOOP_DEV} status=progress
sync

echo "Preparing for Volumio rootfs"
if [ -d /mnt ]
then
  umount /mnt
	echo "/mount folder exist"
else
	mkdir /mnt
fi
if [ -d /mnt/volumio ]
then
	echo "Volumio Temp Directory Exists - Cleaning it"
	rm -rf /mnt/volumio/*
else
	echo "Creating Volumio Temp Directory"
	mkdir /mnt/volumio
fi

echo "Creating mount point for the images partition"
mkdir /mnt/volumio/images
mount -t ext4 "${SYS_PART}" /mnt/volumio/images
mkdir /mnt/volumio/rootfs
mkdir /mnt/volumio/rootfs/boot
# FIXME: This is the line what breaks when executing the script
echo "$BOOT_PART"
sudo mount -t vfat "${BOOT_PART}" /mnt/volumio/rootfs/boot

# Checking if there's a lz4 file
echo "Extracting $ARCH filesystem image"
foundLZ4Files=$(find build/ -type f -name "*.lz4")
if [ $(echo $foundLZ4Files | wc -l ) != 0 ]; then
  fileToExtract=$(echo $foundLZ4Files | grep -iE ".*$ARCH.*" | sed 1q)
  unlz4 -d $fileToExtract build/rootfs.tar
  mkdir build/$ARCH/
  mkdir build/$ARCH/root
  tar xf build/rootfs.tar -C build/$ARCH/root
fi

echo "Copying Volumio RootFs"
cp -pdR build/$ARCH/root/* /mnt/volumio/rootfs

echo "Copying rock3a boot files"
cp -R platform-rock3a/rock3a/boot/* /mnt/volumio/rootfs/boot/
# cp platform-rock3a/rock3a/boot/Image /mnt/volumio/rootfs/boot
echo "Copying rock3a modules and firmware"
cp -pdR platform-rock3a/rock3a/lib/modules /mnt/volumio/rootfs/lib/
# # cp -pdR platform-rock3a/rock3a/lib/firmware /mnt/volumio/rootfs/lib/
# # echo "Copying rock3a DAC detection service"
# # cp platform-odroid/odroidc1/etc/odroiddac.service /mnt/volumio/rootfs/lib/systemd/system/
# # cp platform-odroid/odroidc1/etc/odroiddac.sh /mnt/volumio/rootfs/opt/
# # echo "Copying framebuffer init script"
# # cp platform-odroid/odroidc1/etc/C1_init.sh /mnt/volumio/rootfs/usr/local/bin/c1-init.sh

# # echo "Copying OdroidC1 inittab"
# # cp platform-odroid/odroidc1/etc/inittab /mnt/volumio/rootfs/etc/

#TODO: odroids should be able to run generic debian
# sed -i "s/Raspbian/Debian/g" /mnt/volumio/rootfs/etc/issue

sync

echo "Preparing to run chroot for more RADXA-${MODEL} configuration"
cp scripts/rock3aconfig.sh /mnt/volumio/rootfs
cp scripts/initramfs/init /mnt/volumio/rootfs/root
cp scripts/initramfs/mkinitramfs-custom.sh /mnt/volumio/rootfs/usr/local/sbin
#copy the scripts for updating from usb
wget -P /mnt/volumio/rootfs/root http://repo.volumio.org/Volumio2/Binaries/volumio-init-updater

mount /dev /mnt/volumio/rootfs/dev -o bind
mount /proc /mnt/volumio/rootfs/proc -t proc
mount /sys /mnt/volumio/rootfs/sys -t sysfs

echo $PATCH > /mnt/volumio/rootfs/patch

if [ -f "/mnt/volumio/rootfs/$PATCH/patch.sh" ] && [ -f "config.js" ]; then
        if [ -f "UIVARIANT" ] && [ -f "variant.js" ]; then
                UIVARIANT=$(cat "UIVARIANT")
                echo "Configuring variant $UIVARIANT"
                echo "Starting config.js for variant $UIVARIANT"
                node config.js $PATCH $UIVARIANT
                echo $UIVARIANT > /mnt/volumio/rootfs/UIVARIANT
        else
                echo "Starting config.js"
                node config.js $PATCH
        fi
fi

chroot /mnt/volumio/rootfs /bin/bash -x <<'EOF'
su -
/rock3aconfig.sh
EOF

UIVARIANT_FILE=/mnt/volumio/rootfs/UIVARIANT
if [ -f "${UIVARIANT_FILE}" ]; then
    echo "Starting variant.js"
    node variant.js
    rm $UIVARIANT_FILE
fi

#cleanup
rm /mnt/volumio/rootfs/rock3aconfig.sh /mnt/volumio/rootfs/root/init

echo "Unmounting Temp devices"
umount -l /mnt/volumio/rootfs/dev
umount -l /mnt/volumio/rootfs/proc
umount -l /mnt/volumio/rootfs/sys

# # echo "Copying LIRC configuration files for HK stock remote"
# # cp platform-odroid/odroidc1/etc/lirc/lircd.conf /mnt/volumio/rootfs/etc/lirc
# # cp platform-odroid/odroidc1/etc/lirc/hardware.conf /mnt/volumio/rootfs/etc/lirc
# # cp platform-odroid/odroidc1/etc/lirc/lircrc /mnt/volumio/rootfs/etc/lirc

echo "==> rock3a device installed"

#echo "Removing temporary platform files"
#echo "(you can keep it safely as long as you're sure of no changes)"
#rm -r platform-odroid
sync

echo "Finalizing Rootfs creation"
sh scripts/finalize.sh

echo "Preparing rootfs base for SquashFS"

if [ -d /mnt/squash ]; then
	echo "Volumio SquashFS Temp Dir Exists - Cleaning it"
	rm -rf /mnt/squash/*
else
	echo "Creating Volumio SquashFS Temp Dir"
	mkdir /mnt/squash
fi

echo "Copying Volumio rootfs to Temp Dir"
cp -rp /mnt/volumio/rootfs/* /mnt/squash/

if [ -e /mnt/kernel_current.tar ]; then
	echo "Volumio Kernel Partition Archive exists - Cleaning it"
	rm -rf /mnt/kernel_current.tar
fi

echo "Creating Kernel Partition Archive"
tar cf /mnt/kernel_current.tar --exclude='resize-volumio-datapart' -C /mnt/squash/boot/ .

echo "Removing the Kernel"
rm -rf /mnt/squash/boot/*

echo "Creating SquashFS, removing any previous one"
rm -r Volumio.sqsh
mksquashfs /mnt/squash/* Volumio.sqsh

echo "Squash filesystem created"
echo "Cleaning squash environment"
rm -rf /mnt/squash

#copy the squash image inside the boot partition
cp Volumio.sqsh /mnt/volumio/images/volumio_current.sqsh
sync
echo "Unmounting Temp Devices"
umount -l /mnt/volumio/images
umount -l /mnt/volumio/rootfs/boot

rm -rf /mnt/volumio/*

dmsetup remove_all
losetup -d ${LOOP_DEV}
sync

md5sum "$IMG_FILE" > "${IMG_FILE}.md5"
