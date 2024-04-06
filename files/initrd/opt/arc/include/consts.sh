
ARC_VERSION="24.1.1"
ARC_TITLE="Arc ${ARC_VERSION}"

# Define paths
PART1_PATH="/mnt/p1"
PART2_PATH="/mnt/p2"
PART3_PATH="/mnt/p3"
DSMROOT_PATH="/mnt/dsmroot"
TMP_PATH="/tmp"

UNTAR_PAT_PATH="${TMP_PATH}/DSM"
RAMDISK_PATH="${TMP_PATH}/ramdisk"
LOG_FILE="${TMP_PATH}/log.txt"
UPLOAD_PATH="${TMP_PATH}/upload"

PRESET_CONFIG_FILE="${PART1_PATH}/preset-config.yml"
if [ -f "${PRESET_CONFIG_FILE}" ]; then
  USER_CONFIG_FILE="${PART1_PATH}/preset-config.yml"
else
  USER_CONFIG_FILE="${PART1_PATH}/user-config.yml"
fi
GRUB_PATH="${PART1_PATH}/boot/grub"

ORI_ZIMAGE_FILE="${PART2_PATH}/zImage"
ORI_RDGZ_FILE="${PART2_PATH}/rd.gz"

ARC_BZIMAGE_FILE="${PART3_PATH}/bzImage-arc"
ARC_RAMDISK_FILE="${PART3_PATH}/initrd-arc"
MOD_ZIMAGE_FILE="${PART3_PATH}/zImage-dsm"
MOD_RDGZ_FILE="${PART3_PATH}/initrd-dsm"

ADDONS_PATH="${PART3_PATH}/addons"
MODULES_PATH="${PART3_PATH}/modules"
MODEL_CONFIG_PATH="${PART3_PATH}/configs"
PATCH_PATH="${PART3_PATH}/patches"
LKM_PATH="${PART3_PATH}/lkms"
CUSTOM_PATH="${PART3_PATH}/custom"
USER_UP_PATH="${PART3_PATH}/users"
BACKUPDIR="${PART3_PATH}/backup"
BB_USER_CONFIG_FILE="${BACKUPDIR}/user-config.yml"

EXTRACTOR_PATH="${PART3_PATH}/extractor"
EXTRACTOR_BIN="syno_extract_system_patch"