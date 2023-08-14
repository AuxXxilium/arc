#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/extensions.sh

set -o pipefail # Get exit code from process piped

# Sanity check
[ -f "${ORI_RDGZ_FILE}" ] || (die "${ORI_RDGZ_FILE} not found!" | tee -a "${LOG_FILE}")

echo -e "Patching Ramdisk"

# Remove old rd.gz patched
rm -f "${MOD_RDGZ_FILE}"

# Check disk space left
LOADER_DISK="$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1)"
LOADER_DEVICE_NAME=$(echo ${LOADER_DISK} | sed 's|/dev/||')
SPACELEFT=$(df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print$4}')

# Unzipping ramdisk
rm -rf "${RAMDISK_PATH}" # Force clean
mkdir -p "${RAMDISK_PATH}"
(
  cd "${RAMDISK_PATH}"
  xz -dc <"${ORI_RDGZ_FILE}" | cpio -idm
) >/dev/null 2>&1

# Read Model Data
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
UNIQUE=$(readModelKey "${MODEL}" "unique")
PLATFORM="$(readModelKey "${MODEL}" "platform")"

# Check if DSM Version changed
. "${RAMDISK_PATH}/etc/VERSION"

PRODUCTVERDSM=${majorversion}.${minorversion}

if [ -n "${PRODUCTVERDSM}" ]; then
  # Update new buildnumber
  writeConfigKey "productver" "${PRODUCTVERDSM}" "${USER_CONFIG_FILE}"
fi
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
RD_COMPRESSED="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].rd-compressed")"

# Sanity check
[ -z "${PLATFORM}" ] || [ -z "${KVER}" ] && (die "ERROR: Configuration for Model ${MODEL} and Version ${PRODUCTVER} not found." | tee -a "${LOG_FILE}")

# Update PAT Info for Update
PAT_MODEL="$(echo "${MODEL}" | sed -e 's/\./%2E/g' -e 's/+/%2B/g')"
PAT_MAJOR="$(echo "${PRODUCTVER}" | cut -b 1)"
PAT_MINOR="$(echo "${PRODUCTVER}" | cut -b 3)"
PAT_URL="$(curl -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${PAT_MODEL}&major=${PAT_MAJOR}&minor=${PAT_MINOR}" | jq -r '.info.system.detail[0].items[0].files[0].url')"
PAT_HASH="$(curl -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${PAT_MODEL}&major=${PAT_MAJOR}&minor=${PAT_MINOR}" | jq -r '.info.system.detail[0].items[0].files[0].checksum')"
PAT_URL="${PAT_URL%%\?*}"
writeConfigKey "arc.pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
writeConfigKey "arc.paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"

declare -A SYNOINFO
declare -A ADDONS
declare -A EXTENSIONS
declare -A USERMODULES

# Read synoinfo, addons and extensions from config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && EXTENSIONS["${KEY}"]="${VALUE}"
done < <(readConfigMap "extensions" "${USER_CONFIG_FILE}")

# Read modules from user config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")

# Patches
while read -r f; do
  echo "Patching with ${f}" >"${LOG_FILE}" 2>&1
  (cd "${RAMDISK_PATH}" && patch -p1 <"${PATCH_PATH}/${f}") >>"${LOG_FILE}" 2>&1 || dieLog
done < <(readModelArray "${MODEL}" "productvers.[${PRODUCTVER}].patch")

# Patch /etc/synoinfo.conf
for KEY in ${!SYNOINFO[@]}; do
  _set_conf_kv "${KEY}" "${SYNOINFO[${KEY}]}" "${RAMDISK_PATH}/etc/synoinfo.conf" >"${LOG_FILE}" 2>&1 || dieLog
done
# Add serial number to synoinfo.conf, to help to recovery a installed DSM
_set_conf_kv "SN" "${SN}" "${RAMDISK_PATH}/etc/synoinfo.conf" >"${LOG_FILE}" 2>&1 || dieLog

# Patch /sbin/init.post
grep -v -e '^[\t ]*#' -e '^$' "${PATCH_PATH}/config-manipulators.sh" >"${TMP_PATH}/rp.txt"
sed -e "/@@@CONFIG-MANIPULATORS-TOOLS@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm "${TMP_PATH}/rp.txt"
touch "${TMP_PATH}/rp.txt"
for KEY in ${!SYNOINFO[@]}; do
  echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
  echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc.defaults/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
done
echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc.defaults/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
sed -e "/@@@CONFIG-GENERATED@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm "${TMP_PATH}/rp.txt"

# Extract modules to ramdisk
rm -rf "${TMP_PATH}/modules"
mkdir -p "${TMP_PATH}/modules"
tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
for F in $(ls "${TMP_PATH}/modules/"*.ko); do
  M="$(basename ${F})"
  if arrayExistItem "${M:0:-3}" "${!USERMODULES[@]}"; then
    cp -f "${F}" "${RAMDISK_PATH}/usr/lib/modules/${M}"
  else
    rm -f "${RAMDISK_PATH}/usr/lib/modules/${M}"
  fi
done
mkdir -p "${RAMDISK_PATH}/usr/lib/firmware"
tar -zxf "${MODULES_PATH}/firmware.tgz" -C "${RAMDISK_PATH}/usr/lib/firmware"
# Clean
rm -rf "${TMP_PATH}/modules"

# Copying fake modprobe
cp -f "${PATCH_PATH}/iosched-trampoline.sh" "${RAMDISK_PATH}/usr/sbin/modprobe"
# Copying LKM to /usr/lib/modules
gzip -dc "${LKM_PATH}/rp-${PLATFORM}-${KVER}-${LKM}.ko.gz" >"${RAMDISK_PATH}/usr/lib/modules/rp.ko"

# Addons
#MAXDISKS=$(readConfigKey "maxdisks" "${USER_CONFIG_FILE}")
# Check if model needs Device-tree dynamic patch
DT="$(readModelKey "${MODEL}" "dt")"

mkdir -p "${RAMDISK_PATH}/addons"
mkdir -p "${RAMDISK_PATH}/addons"
echo "#!/bin/sh" >"${RAMDISK_PATH}/addons/addons.sh"
echo 'echo "addons.sh called with params ${@}"' >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export PLATFORM=${PLATFORM}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MODEL=${MODEL}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MLINK=${PAT_URL}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MCHECKSUM=${PAT_HASH}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LAYOUT=${LAYOUT}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export KEYMAP=${KEYMAP}" >>"${RAMDISK_PATH}/addons/addons.sh"
chmod +x "${RAMDISK_PATH}/addons/addons.sh"

# User Addons
for ADDON in ${!ADDONS[@]}; do
  PARAMS=${ADDONS[${ADDON}]}
  if ! installAddon ${ADDON}; then
    echo -n "${ADDON} is not available for this Platform!" | tee -a "${LOG_FILE}"
    exit 1
  fi
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >> "${RAMDISK_PATH}/addons/addons.sh" 2>"${LOG_FILE}" || dieLog
done

# User Extensions
for EXTENSION in ${!EXTENSIONS[@]}; do
  PARAMS=${EXTENSIONS[${EXTENSION}]}
  if ! installExtension ${EXTENSION}; then
    echo -n "${EXTENSION} is not available for this Platform!" | tee -a "${LOG_FILE}"
    exit 1
  fi
  echo "/addons/${EXTENSION}.sh \${1} ${PARAMS}" >> "${RAMDISK_PATH}/addons/addons.sh" 2>"${LOG_FILE}" || dieLog
done

# Required addons: misc, eudev, disks, wol, acpid, bootwait
installAddon misc
echo "/addons/misc.sh \${1} " >> "${RAMDISK_PATH}/addons/addons.sh" 2>"${LOG_FILE}" || dieLog
installAddon eudev
echo "/addons/eudev.sh \${1} " >> "${RAMDISK_PATH}/addons/addons.sh" 2>"${LOG_FILE}" || dieLog
installAddon disks
echo "/addons/disks.sh \${1} ${DT} ${UNIQUE}" >> "${RAMDISK_PATH}/addons/addons.sh" 2>"${LOG_FILE}" || dieLog
installAddon wol
echo "/addons/wol.sh \${1} " >> "${RAMDISK_PATH}/addons/addons.sh" 2>"${LOG_FILE}" || dieLog
installAddon localrss
echo "/addons/localrss.sh \${1} " >>"${RAMDISK_PATH}/addons/addons.sh" 2>"${LOG_FILE}" || dieLog
# Enable Telnet
echo "inetd" >>"${RAMDISK_PATH}/addons/addons.sh"

[ "2" = "${BUILD:0:1}" ] && sed -i 's/function //g' $(find "${RAMDISK_PATH}/addons/" -type f -name "*.sh")

# Build modules dependencies
/opt/arpl/depmod -a -b ${RAMDISK_PATH} 2>/dev/null

# Reassembly ramdisk
if [ "${RD_COMPRESSED}" == "true" ]; then
  (cd "${RAMDISK_PATH}" && find . | cpio -o -H newc -R root:root | xz -9 --format=lzma >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || dieLog
else
  (cd "${RAMDISK_PATH}" && find . | cpio -o -H newc -R root:root >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || dieLog
fi

# Clean
rm -rf "${RAMDISK_PATH}"

# Update SHA256 hash
RAMDISK_HASH="$(sha256sum ${ORI_RDGZ_FILE} | awk '{print$1}')"
writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"