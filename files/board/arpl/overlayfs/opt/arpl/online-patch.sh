#!/usr/bin/env bash

. /opt/arpl/include/functions.sh

set -o pipefail # Get exit code from process piped

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
PLATFORM="`readModelKey "${MODEL}" "platform"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"

# Clean old files
rm -rf "${UNTAR_PAT_PATH}"

# Check for existing files
mkdir -p "${CACHE_PATH}/${MODEL}"
DSM_FILE="${CACHE_PATH}/${MODEL}/dsm.tar"
DSM_MODEL=`printf "${MODEL}" | jq -sRr @uri`
#DSM_BUILD="`readModelKey "${MODEL}" "builds.${BUILD}.dsm"`"
DSM_LINK="${DSM_MODEL}/${BUILD}/dsm.tar"
DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${DSM_LINK}"
rm -f "${DSM_FILE}"
STATUS="`curl --insecure -w "%{http_code}" -L "${DSM_URL}" -o "${DSM_FILE}"`"
if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
    echo -n "No DSM Image found!"
    return 1
else
    echo -n "DSM Image Download successfull!"
fi
# Unpack files
if [ -e "${DSM_FILE}" ]; then
    mkdir -p "${UNTAR_PAT_PATH}"
    tar -xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    # Copy DSM Files to locations
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${BOOTLOADER_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER"        "${BOOTLOADER_PATH}"
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${SLPART_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER"        "${SLPART_PATH}"
    cp -f "${UNTAR_PAT_PATH}/zImage"          "${ORI_ZIMAGE_FILE}"
    cp -f "${UNTAR_PAT_PATH}/rd.gz"           "${ORI_RDGZ_FILE}"
    # Write out .pat variables
    PAT_MD5_HASH="`cat "${UNTAR_PAT_PATH}/pat_hash"`"
    PAT_URL="`cat "${UNTAR_PAT_PATH}/pat_url"`"
    writeConfigKey "arc.pathash" "${PAT_MD5_HASH}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
    echo -n "Online Patch successful!"
else
    echo -n "Online Patch unsuccessful!"
    return 1
fi

# Unzipping ramdisk
echo -n "."
rm -rf "${RAMDISK_PATH}"  # Force clean
mkdir -p "${RAMDISK_PATH}"
(cd "${RAMDISK_PATH}"; xz -dc < "${ORI_RDGZ_FILE}" | cpio -idm) >/dev/null 2>&1

# Check if DSM buildnumber changed
. "${RAMDISK_PATH}/etc/VERSION"

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"
LAYOUT="`readConfigKey "layout" "${USER_CONFIG_FILE}"`"
KEYMAP="`readConfigKey "keymap" "${USER_CONFIG_FILE}"`"
echo