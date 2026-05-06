#!/bin/bash
set -e
cd /root && mkdir -p pxe-final && cd pxe-final

echo '=== [1] Extract kernel + initrd from arc-configured.img ==='
losetup -P /dev/loop0 /mnt/d/software/Synology_Arc/arc-configured.img
mkdir -p p3 && mount /dev/loop0p3 p3
cp p3/bzImage-apex bzImage
cp p3/initrd-apex initrd-original
umount p3 && losetup -d /dev/loop0

echo '=== [2] Extract initrd ==='
mkdir -p w && cd w
zstd -dc ../initrd-original | cpio -idm 2>&1 | tail -1

echo '=== [3] Inject modifications ==='
mv init init.buildroot
cp /mnt/d/software/Synology_Arc/pxe/init-pxe.sh init
chmod +x init

cp /mnt/d/software/Synology_Arc/files/initrd/opt/arc/include/functions.sh opt/arc/include/functions.sh
echo '  getBus patch:' && grep 'loop' opt/arc/include/functions.sh

echo '=== [4] Compress CONFIGURED arc.img and embed ==='
gzip -c /mnt/d/software/Synology_Arc/arc-configured.img > opt/arc/arc.img.gz
echo '  Embedded:' && ls -lh opt/arc/arc.img.gz

echo '=== [5] Repack ==='
find . | cpio -o -H newc -R root:root 2>/dev/null | zstd -19 -o ../initrd
ls -lh ../bzImage ../initrd

echo '=== [6] Copy to output ==='
cp ../bzImage /mnt/d/software/Synology_Arc/pxe/pxe-output/bzImage
cp ../initrd /mnt/d/software/Synology_Arc/pxe/pxe-output/initrd
cp /mnt/d/software/Synology_Arc/pxe/boot.ipxe /mnt/d/software/Synology_Arc/pxe/pxe-output/boot.ipxe

rm -rf /root/pxe-final
echo '=== Done! ==='
