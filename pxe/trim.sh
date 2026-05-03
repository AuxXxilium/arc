#!/bin/bash
END_SECTOR=3788799
BYTE_SIZE=$(( (END_SECTOR + 1) * 512 ))
echo "Truncate to: ${BYTE_SIZE} bytes ($(( BYTE_SIZE / 1024 / 1024 )) MB)"

truncate -s ${BYTE_SIZE} /mnt/d/wangj/黑群晖/Arc_udisk_backup20260502.img
cp /mnt/d/wangj/黑群晖/Arc_udisk_backup20260502.img /mnt/d/software/Synology_Arc/arc-configured.img

ls -lh /mnt/d/software/Synology_Arc/arc-configured.img
fdisk -l /mnt/d/software/Synology_Arc/arc-configured.img
