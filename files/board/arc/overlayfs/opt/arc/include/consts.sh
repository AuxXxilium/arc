
<<<<<<< HEAD:files/board/arc/overlayfs/opt/arc/include/consts.sh
ARC_VERSION="23.01.04"
=======
ARPL_VERSION="1.0-beta10b"
>>>>>>> 04fd54c (Fixing grub.cfg bug invalid font):files/board/arpl/overlayfs/opt/arpl/include/consts.sh

# Define paths
TMP_PATH="/tmp"
UNTAR_PAT_PATH="${TMP_PATH}/pat"
RAMDISK_PATH="${TMP_PATH}/ramdisk"
LOG_FILE="${TMP_PATH}/log.txt"

USER_CONFIG_FILE="${BOOTLOADER_PATH}/user-config.yml"
GRUB_PATH="${BOOTLOADER_PATH}/grub"

ORI_ZIMAGE_FILE="${SLPART_PATH}/zImage"
ORI_RDGZ_FILE="${SLPART_PATH}/rd.gz"

ARC_BZIMAGE_FILE="${CACHE_PATH}/bzImage-arc"
ARC_RAMDISK_FILE="${CACHE_PATH}/initrd-arc"
MOD_ZIMAGE_FILE="${CACHE_PATH}/zImage-dsm"
MOD_RDGZ_FILE="${CACHE_PATH}/initrd-dsm"
ADDONS_PATH="${CACHE_PATH}/addons"
LKM_PATH="${CACHE_PATH}/lkms"
MODULES_PATH="${CACHE_PATH}/modules"

MODEL_CONFIG_PATH="/opt/arc/model-configs"
INCLUDE_PATH="/opt/arc/include"
PATCH_PATH="/opt/arc/patch"
