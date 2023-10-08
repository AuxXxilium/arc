
ARC_VERSION="23.1.1"
ARC_TITLE="Arc ${ARC_VERSION}"

# Define paths
INCLUDE_PATH="/opt/arc/include"

TMP_PATH="/tmp"
UNTAR_PAT_PATH="${CACHE_PATH}/dsm"
RAMDISK_PATH="${TMP_PATH}/ramdisk"
LOG_FILE="${TMP_PATH}/log.txt"

USER_CONFIG_FILE="${BOOTLOADER_PATH}/user-config.yml"
GRUB_PATH="${BOOTLOADER_PATH}/boot/grub"
SYSINFO_PATH="${BOOTLOADER_PATH}/sysinfo.yml"

ORI_ZIMAGE_FILE="${SLPART_PATH}/zImage"
ORI_RDGZ_FILE="${SLPART_PATH}/rd.gz"

MOD_ZIMAGE_FILE="${CACHE_PATH}/zImage-dsm"
MOD_RDGZ_FILE="${CACHE_PATH}/initrd-dsm"

ADDONS_PATH="${CACHE_PATH}/addons"
EXTENSIONS_PATH="${CACHE_PATH}/extensions"
MODULES_PATH="${CACHE_PATH}/modules"
MODEL_CONFIG_PATH="${CACHE_PATH}/configs"
PATCH_PATH="${CACHE_PATH}/patches"
LKM_PATH="${CACHE_PATH}/lkms"

USER_UP_PATH="${CACHE_PATH}/users"

BACKUPDIR="${CACHE_PATH}/backup"
BB_USER_CONFIG_FILE="${BACKUPDIR}/user-config.yml"