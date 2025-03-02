#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"
. "${ARC_PATH}/include/addons.sh"
. "${ARC_PATH}/include/modules.sh"

set -o pipefail # Get exit code from process piped

# Sanity check
if [ ! -f "${ORI_RDGZ_FILE}" ]; then
  echo "ERROR: ${ORI_RDGZ_FILE} not found!" >"${LOG_FILE}"
  exit 1
fi

# Remove old rd.gz patched
rm -f "${MOD_RDGZ_FILE}"

# Unzipping ramdisk
rm -rf "${RAMDISK_PATH}"
mkdir -p "${RAMDISK_PATH}"
(
  cd "${RAMDISK_PATH}"
  xz -dc <"${ORI_RDGZ_FILE}" | cpio -idm
) >/dev/null 2>&1

# Read Model Data
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
# Read new PAT Info from Config
PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"

# Check if DSM Version changed
. "${RAMDISK_PATH}/etc/VERSION"

if [[ -n "${BUILDNUM}" && ("${PRODUCTVER}" != "${majorversion}.${minorversion}" || "${BUILDNUM}" != "${buildnumber}" || "${SMALLNUM}" != "${smallfixnumber}") ]]; then
  OLDVER="${PRODUCTVER}(${BUILDNUM}$([[ ${SMALLNUM:-0} -ne 0 ]] && echo "u${SMALLNUM}"))"
  NEWVER="${majorversion}.${minorversion}(${buildnumber}$([[ ${smallfixnumber:-0} -ne 0 ]] && echo "u${smallfixnumber}"))"
  PAT_URL=""
  PAT_HASH=""
  echo -e "Version changed from ${OLDVER} to ${NEWVER}"
fi

# Re-read PAT_URL and PAT_HASH if they are empty or commented out
if [[ -z "${PAT_URL}" || "${PAT_URL:0:1}" == "#" ]]; then
  PAT_URL="$(readConfigKey "${PLATFORM}.\"${MODEL}\".\"${majorversion}.${minorversion}\".url" "${D_FILE}")"
fi
if [[ -z "${PAT_HASH}" || "${PAT_HASH:0:1}" == "#" ]]; then
  PAT_HASH="$(readConfigKey "${PLATFORM}.\"${MODEL}\".\"${majorversion}.${minorversion}\".hash" "${D_FILE}")"
fi

PRODUCTVER="${majorversion}.${minorversion}"
BUILDNUM="${buildnumber}"
SMALLNUM="${smallfixnumber}"

writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"

# Read model data
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
[ "${PLATFORM}" = "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"

# Sanity check
if [ -z "${PLATFORM}" ] || [ -z "${KVER}" ]; then
  echo "ERROR: Configuration for Model ${MODEL} and Version ${PRODUCTVER} not found." >"${LOG_FILE}"
  exit 1
fi

# Read synoinfo and addons from config
declare -A SYNOINFO ADDONS MODULES

while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

# Read modules from user config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && MODULES["${KEY}"]="${VALUE}"
done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")

# Patches (diff -Naru OLDFILE NEWFILE > xxx.patch)
PATCHES=(
  "ramdisk-etc-rc-*.patch"
  "ramdisk-init-script-*.patch"
  "ramdisk-post-init-script-*.patch"
  "ramdisk-disable-root-pwd-*.patch"
  "ramdisk-disable-disabled-ports-*.patch"
)

for PATCH in "${PATCHES[@]}"; do
  echo "Patching with ${PATCH}" >>"${LOG_FILE}"
  for PF in ${PATCH_PATH}/${PATCH}; do
    [ -e "${PF}" ] || continue
    echo "Applying patch ${PF}" >>"${LOG_FILE}"
    if ! (cd "${RAMDISK_PATH}" && busybox patch -p1 -i "${PF}") >>"${LOG_FILE}" 2>&1; then
      echo "Failed to apply patch ${FILE}" >>"${LOG_FILE}"
      continue
    fi
  done
done

# Add serial number to synoinfo.conf, to help to recovery a installed DSM
echo "Set synoinfo SN" >"${LOG_FILE}"
_set_conf_kv "SN" "${SN}" "${RAMDISK_PATH}/etc/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
_set_conf_kv "SN" "${SN}" "${RAMDISK_PATH}/etc.defaults/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
for KEY in "${!SYNOINFO[@]}"; do
  echo "Set synoinfo ${KEY}" >>"${LOG_FILE}"
  _set_conf_kv "${KEY}" "${SYNOINFO[${KEY}]}" "${RAMDISK_PATH}/etc/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
  _set_conf_kv "${KEY}" "${SYNOINFO[${KEY}]}" "${RAMDISK_PATH}/etc.defaults/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
done

# Patch /sbin/init.post
grep -v -e '^[\t ]*#' -e '^$' "${PATCH_PATH}/config-manipulators.sh" >"${TMP_PATH}/rp.txt"
sed -e "/@@@CONFIG-MANIPULATORS-TOOLS@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm -f "${TMP_PATH}/rp.txt"

# Generate synoinfo configurations
{
  echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc/synoinfo.conf'"
  echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc.defaults/synoinfo.conf'"
  for KEY in "${!SYNOINFO[@]}"; do
    echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc/synoinfo.conf'"
    echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc.defaults/synoinfo.conf'"
  done
} >"${TMP_PATH}/rp.txt"

sed -e "/@@@CONFIG-GENERATED@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm -f "${TMP_PATH}/rp.txt"

# Extract Modules to Ramdisk
installModules "${PLATFORM}" "${KVERP}" "${!MODULES[@]}" || exit 1

# Copying fake modprobe
[ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 5 ] && cp -f "${PATCH_PATH}/iosched-trampoline.sh" "${RAMDISK_PATH}/usr/sbin/modprobe"
# Copying LKM to /usr/lib/modules
gzip -dc "${LKMS_PATH}/rp-${PLATFORM}-${KVERP}-${LKM}.ko.gz" >"${RAMDISK_PATH}/usr/lib/modules/rp.ko" 2>"${LOG_FILE}" || exit 1

# Addons
echo "Create addons.sh" >"${LOG_FILE}"
mkdir -p "${RAMDISK_PATH}/addons"
{
  echo "#!/bin/sh"
  echo 'echo "addons.sh called with params ${@}"'
  echo "export LOADERLABEL=\"ARC\""
  echo "export LOADERVERSION=\"${ARC_VERSION}\""
  echo "export LOADERBUILD=\"${ARC_BUILD}\""
  echo "export LOADERBRANCH=\"${ARC_BRANCH}\""
  echo "export PLATFORM=\"${PLATFORM}\""
  echo "export MODEL=\"${MODEL}\""
  echo "export MODELID=\"${MODELID}\""
  echo "export PRODUCTVERL=\"${PRODUCTVERL}\""
  echo "export MLINK=\"${PAT_URL}\""
  echo "export MCHECKSUM=\"${PAT_HASH}\""
  echo "export LAYOUT=\"${LAYOUT:-qwerty}\""
  echo "export KEYMAP=\"${KEYMAP:-en}\""
} >"${RAMDISK_PATH}/addons/addons.sh"
chmod +x "${RAMDISK_PATH}/addons/addons.sh"

# Add redpill Addon if Platform is epyc7002
if [ "${PLATFORM}" = "epyc7002" ]; then
  installAddon "redpill" "${PLATFORM}" || exit 1
  echo "/addons/redpill.sh \${1}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
fi

# System Addons
for ADDON in "revert" "misc" "eudev" "disks" "localrss" "notify" "wol" "mountloader"; do
  PARAMS=""
  if [ "${ADDON}" = "disks" ]; then
    HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
    PARAMS="${HDDSORT}"
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && cp -f "${USER_UP_PATH}/${MODEL}.dts" "${RAMDISK_PATH}/addons/model.dts"
  fi
  installAddon "${ADDON}" "${PLATFORM}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# User Addons
for ADDON in "${!ADDONS[@]}"; do
  PARAMS="${ADDONS[${ADDON}]}"
  installAddon "${ADDON}" "${PLATFORM}" || echo "Addon ${ADDON} not found"
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# Enable Telnet
echo "inetd" >>"${RAMDISK_PATH}/addons/addons.sh"

echo "Modify files" >"${LOG_FILE}"

# Build modules dependencies
# ${ARC_PATH}/depmod -a -b ${RAMDISK_PATH} 2>/dev/null

# Copying modulelist
if [ -f "${USER_UP_PATH}/modulelist" ]; then
  cp -f "${USER_UP_PATH}/modulelist" "${RAMDISK_PATH}/addons/modulelist"
else
  cp -f "${ARC_PATH}/include/modulelist" "${RAMDISK_PATH}/addons/modulelist"
fi

# backup current loader configs
BACKUP_PATH="${RAMDISK_PATH}/usr/arc/backup"
rm -rf "${BACKUP_PATH}"
for F in "${USER_GRUB_CONFIG}" "${USER_CONFIG_FILE}" "${USER_UP_PATH}" "${HW_KEY}"; do
  if [ -f "${F}" ]; then
    FD="$(dirname "${F}")"
    mkdir -p "${FD/\/mnt/${BACKUP_PATH}}"
    cp -f "${F}" "${FD/\/mnt/${BACKUP_PATH}}"
  elif [ -d "${F}" ]; then
    SIZE="$(du -sm "${F}" 2>/dev/null | awk '{print $1}')"
    if [ ${SIZE:-0} -gt 4 ]; then
      echo "Backup of ${F} skipped, size is ${SIZE}MB" >>"${LOG_FILE}"
      continue
    fi
    FD="$(dirname "${F}")"
    mkdir -p "${FD/\/mnt/${BACKUP_PATH}}"
    cp -rf "${F}" "${FD/\/mnt/${BACKUP_PATH}}"
  fi
done

# Network card configuration file
for N in $(seq 0 7); do
  echo -e "DEVICE=eth${N}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=dhcp\nIPV6_ACCEPT_RA=1" >"${RAMDISK_PATH}/etc/sysconfig/network-scripts/ifcfg-eth${N}"
done

# SA6400 patches
if [ "${PLATFORM}" = "epyc7002" ]; then
  echo -e "Apply Epyc7002 Fixes"
  sed -i 's#/dev/console#/var/log/lrc#g' ${RAMDISK_PATH}/usr/bin/busybox
  sed -i '/^echo "START/a \\nmknod -m 0666 /dev/console c 1 3' ${RAMDISK_PATH}/linuxrc.syno
fi

# Broadwellntbap patches
if [ "${PLATFORM}" = "broadwellntbap" ]; then
  echo -e "Apply Broadwellntbap Fixes"
  sed -i 's/IsUCOrXA="yes"/XIsUCOrXA="yes"/g; s/IsUCOrXA=yes/XIsUCOrXA=yes/g' ${RAMDISK_PATH}/usr/syno/share/environments.sh
fi

# Call user patch scripts
for F in $(ls -1 ${USER_UP_PATH}/*.sh 2>/dev/null); do
  echo "Calling ${F}" >"${LOG_FILE}"
  . "${F}" >>"${LOG_FILE}" 2>&1 || exit 1
done

# Reassembly ramdisk
if [ "${RD_COMPRESSED}" = "true" ]; then
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 --format=lzma >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
else
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
fi

sync

# Clean
rm -rf "${RAMDISK_PATH}"