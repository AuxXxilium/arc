#!/usr/bin/env bash

. /opt/arpl/include/functions.sh

set -o pipefail # Get exit code from process piped

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"

# Check for existing files
mkdir -p "${CACHE_PATH}/${MODEL}/${BUILD}"
DSM_FILE="${CACHE_PATH}/${MODEL}/${BUILD}/dsm.tar"
DSM_MODEL="`printf "${MODEL}" | jq -sRr @uri`"
# Clean old files
rm -rf "${UNTAR_PAT_PATH}"
rm -f "${DSM_FILE}"
# Get new files
DSM_LINK="${DSM_MODEL}/${BUILD}/dsm.tar"
DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${DSM_LINK}"
STATUS="`curl --insecure -s -w "%{http_code}" -L "${DSM_URL}" -o "${DSM_FILE}"`"
if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
    echo -e "\033[1;37mNo DSM Image found!\033[0m"
    return 1
else
    echo -e "\033[1;37mDSM Image Download successfull!\033[0m"
fi
# Unpack files
if [ -f "${DSM_FILE}" ]; then
    mkdir -p "${UNTAR_PAT_PATH}"
    tar -xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    # Write out .pat variables
    PAT_MD5_HASH="`cat "${UNTAR_PAT_PATH}/pat_hash"`"
    PAT_URL="`cat "${UNTAR_PAT_PATH}/pat_url"`"
    writeConfigKey "arc.pathash" "${PAT_MD5_HASH}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
    echo -e "\033[1;37mOnline Patch successful!\033[0m"
elif [ ! -f "${DSM_FILE}" ]; then
    echo -e "\033[1;37mOnline Patch failed!\nDSM File corrupted!\033[0m"
    return 1
else
    echo -e "\033[1;37mOnline Patch failed!\033[0m"
    return 1
fi

# Unzipping new ramdisk
rm -rf "${RAMDISK_PATH}"  # Force clean
mkdir -p "${RAMDISK_PATH}"
(cd "${RAMDISK_PATH}"; xz -dc < "${ORI_RDGZ_FILE}" | cpio -idm) >/dev/null 2>&1
echo