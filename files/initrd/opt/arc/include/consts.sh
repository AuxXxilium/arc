# Define paths
PART1_PATH="/mnt/p1"
PART2_PATH="/mnt/p2"
PART3_PATH="/mnt/p3"
TMP_PATH="/tmp"

[ -f "${PART3_PATH}/automated" ] && rm -f "${PART3_PATH}/automated" >/dev/null 2>&1 || true
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

ORI_ZIMAGE_FILE="${PART2_PATH}/zImage"
ORI_RDGZ_FILE="${PART2_PATH}/rd.gz"
ARC_BZIMAGE_FILE="${PART3_PATH}/bzImage-arc"
ARC_RAMDISK_FILE="${PART3_PATH}/initrd-arc"
ARC_RAMDISK_USER_FILE="${PART3_PATH}/initrd-user"
MOD_ZIMAGE_FILE="${PART3_PATH}/zImage-dsm"
MOD_RDGZ_FILE="${PART3_PATH}/initrd-dsm"

ADDONS_PATH="${PART3_PATH}/addons"
MODULES_PATH="${PART3_PATH}/modules"
CONFIGS_PATH="${PART3_PATH}/configs"
PATCH_PATH="${PART3_PATH}/patches"
LKMS_PATH="${PART3_PATH}/lkms"
CUSTOM_PATH="${PART3_PATH}/custom"
USER_UP_PATH="${PART3_PATH}/users"
UNTAR_PAT_PATH="${PART3_PATH}/DSM"

S_FILE="${CONFIGS_PATH}/serials.yml"
P_FILE="${CONFIGS_PATH}/platforms.yml"
D_FILE="${CONFIGS_PATH}/data.yml"

EXTRACTOR_PATH="${PART3_PATH}/extractor"
EXTRACTOR_BIN="syno_extract_system_patch"

KVER5L=(epyc7002 geminilakenk r1000nk v1000nk)
IGPU1L=(apollolake geminilake)
IGPU2L=(epyc7002 geminilakenk r1000nk v1000nk)
NVMECACHE=(DS719+ DS918+ DS1019+ DS1621xs+ RS1619xs+)
MPT3PL=(purley broadwellnkv2 epyc7002 geminilakenk r1000nk v1000nk)
IGFXRL=(apollolake geminilake geminilakenk)
XAPICRL=(apollolake geminilake purley geminilakenk)

HTTPPORT=$(grep -i '^HTTP_PORT=' /etc/arc.conf 2>/dev/null | cut -d'=' -f2)
[ -z "${HTTPPORT}" ] && HTTPPORT="7080"
DUFSPORT=$(grep -i '^DUFS_PORT=' /etc/arc.conf 2>/dev/null | cut -d'=' -f2)
[ -z "${DUFSPORT}" ] && DUFSPORT="7304"
TTYDPORT=$(grep -i '^TTYD_PORT=' /etc/arc.conf 2>/dev/null | cut -d'=' -f2)
[ -z "${TTYDPORT}" ] && TTYDPORT="7681"

API_URL="https://api.github.com/repos/AuxXxilium/arc/releases"
UPDATE_URL="https://github.com/AuxXxilium/arc/releases/download"
BETA_API_URL="https://api.github.com/repos/AuxXxilium/arc-beta/releases"
BETA_URL="https://github.com/AuxXxilium/arc-beta/releases/download"