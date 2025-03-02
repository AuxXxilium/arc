# Define paths
PART1_PATH="/mnt/p1"
PART2_PATH="/mnt/p2"
PART3_PATH="/mnt/p3"
TMP_PATH="/tmp"

[ -f "${PART3_PATH}/automated" ] && rm -f "${PART3_PATH}/automated" >/dev/null 2>&1 || true
[ -f "${PART1_PATH}/ARC-BRANCH" ] && ARC_BRANCH="$(cat "${PART1_PATH}/ARC-BRANCH")" || ARC_BRANCH="null"
[ -f "${PART1_PATH}/ARC-VERSION" ] && ARC_VERSION="$(cat "${PART1_PATH}/ARC-VERSION")" || ARC_VERSION="null"
[ -f "${PART1_PATH}/ARC-BUILD" ] && ARC_BUILD="$(cat "${PART1_PATH}/ARC-BUILD")" || ARC_BUILD="null"
ARC_TITLE="Arc ${ARC_VERSION}"

RAMDISK_PATH="${TMP_PATH}/ramdisk"
LOG_FILE="${TMP_PATH}/log.txt"
TMP_UP_PATH="${TMP_PATH}/upload"

GRUB_PATH="${PART1_PATH}/boot/grub"
USER_GRUB_CONFIG="${GRUB_PATH}/grub.cfg"
USER_GRUBENVFILE="${GRUB_PATH}/grubenv"
USER_RSYSENVFILE="${GRUB_PATH}/rsysenv"
USER_CONFIG_FILE="${PART1_PATH}/user-config.yml"
HW_KEY="${PART2_PATH}/machine.key"

ORI_ZIMAGE_FILE="${PART2_PATH}/zImage"
ORI_RDGZ_FILE="${PART2_PATH}/rd.gz"
ARC_BZIMAGE_FILE="${PART3_PATH}/bzImage-arc"
ARC_RAMDISK_FILE="${PART3_PATH}/initrd-arc"
ARC_RAMDISK_USER_FILE="${PART3_PATH}/initrd-user"
MC_RAMDISK_FILE="${PART3_PATH}/microcode.img"
MOD_ZIMAGE_FILE="${PART3_PATH}/zImage-dsm"
MOD_RDGZ_FILE="${PART3_PATH}/initrd-dsm"

ADDONS_PATH="${PART3_PATH}/addons"
MODULES_PATH="${PART3_PATH}/modules"
MODEL_CONFIG_PATH="${PART3_PATH}/configs"
PATCH_PATH="${PART3_PATH}/patches"
LKMS_PATH="${PART3_PATH}/lkms"
CUSTOM_PATH="${PART3_PATH}/custom"
USER_UP_PATH="${PART3_PATH}/users"
UNTAR_PAT_PATH="${PART3_PATH}/DSM"

S_FILE="${MODEL_CONFIG_PATH}/serials.yml"
P_FILE="${MODEL_CONFIG_PATH}/platforms.yml"
D_FILE="${MODEL_CONFIG_PATH}/data.yml"

EXTRACTOR_PATH="${PART3_PATH}/extractor"
EXTRACTOR_BIN="syno_extract_system_patch"

HTTPPORT=$(grep -i '^HTTP_PORT=' /etc/arc.conf 2>/dev/null | cut -d'=' -f2)
[ -z "${HTTPPORT}" ] && HTTPPORT="" || true
DUFSPORT=$(grep -i '^DUFS_PORT=' /etc/arc.conf 2>/dev/null | cut -d'=' -f2)
[ -z "${DUFSPORT}" ] && DUFSPORT="7304" || true
TTYDPORT=$(grep -i '^TTYD_PORT=' /etc/arc.conf 2>/dev/null | cut -d'=' -f2)
[ -z "${TTYDPORT}" ] && TTYDPORT="7681" || true