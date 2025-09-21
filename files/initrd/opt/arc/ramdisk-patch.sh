#!/usr/bin/env bash
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"
. "${ARC_PATH}/include/addons.sh"
. "${ARC_PATH}/include/modules.sh"

set -o pipefail # Get exit code from process piped

# Read Model Data
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
DT="$(readConfigKey "dt" "${USER_CONFIG_FILE}")"

# Read kver data
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
is_in_array "${PLATFORM}" "${KVER5L[@]}" && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"

# Sanity check
if [ -z "${PLATFORM}" ] || [ -z "${KVER}" ]; then
  echo "ERROR: Configuration for Model ${MODEL} and Version ${PRODUCTVER} not found." >"${LOG_FILE}"
  exit 1
fi

# Read new PAT Info from Config
PAT_URL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
PAT_HASH="$(readConfigKey "pathash" "${USER_CONFIG_FILE}")"

[ "${PAT_URL:0:1}" = "#" ] && PAT_URL=""
[ "${PAT_HASH:0:1}" = "#" ] && PAT_HASH=""

# Sanity check
if [ ! -f "${ORI_RDGZ_FILE}" ]; then
  echo "ERROR: ${ORI_RDGZ_FILE} not found!" >"${LOG_FILE}"
  exit 1
fi

# Unzipping ramdisk
rm -rf "${RAMDISK_PATH}" # Force clean
mkdir -p "${RAMDISK_PATH}"
(cd "${RAMDISK_PATH}" && xz -dc <"${ORI_RDGZ_FILE}" | cpio -idm) >/dev/null 2>&1

# Check if DSM Version changed
. "${RAMDISK_PATH}/etc/VERSION"

if [ -n "${PRODUCTVER}" ] && [ -n "${BUILDNUM}" ] && [ -n "${SMALLNUM}" ] &&
  ([ ! "${PRODUCTVER}" = "${majorversion:-0}.${minorversion:-0}" ] || [ ! "${BUILDNUM}" = "${buildnumber:-0}" ] || [ ! "${SMALLNUM}" = "${smallfixnumber:-0}" ]); then
  OLDVER="${PRODUCTVER}(${BUILDNUM}$([[ ${SMALLNUM:-0} -ne 0 ]] && echo "u${SMALLNUM}"))"
  NEWVER="${majorversion}.${minorversion}(${buildnumber}$([[ ${smallfixnumber:-0} -ne 0 ]] && echo "u${smallfixnumber}"))"
  PAT_URL=""
  PAT_HASH=""
  echo -e ">> Version changed from ${OLDVER} to ${NEWVER}"
fi

# Update buildnumber
PRODUCTVER="${majorversion}.${minorversion}"
BUILDNUM="${buildnumber}"
SMALLNUM="${smallfixnumber}"
writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"

# Read addons, modules and synoinfo
declare -A ADDONS
declare -A MODULES
declare -A SYNOINFO

while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && MODULES["${KEY}"]="${VALUE}"
done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")

while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

# Patches (diff -Naru OLDFILE NEWFILE > xxx.patch)
PATCHES=(
  "ramdisk-etc-rc-*.patch"
  "ramdisk-init-script-*.patch"
  "ramdisk-post-init-script-*.patch"
)

for PE in "${PATCHES[@]}"; do
  RET=2
  MATCHED=0
  for PF in ${PATCH_PATH}/${PE}; do
    [ ! -e "${PF}" ] && continue
    MATCHED=1
    (cd "${RAMDISK_PATH}" && busybox patch -p1 -i "${PF}") >>"${LOG_FILE}" 2>&1
    RET=$?
    [ ${RET} -eq 0 ] && break
  done
  [ ${RET} -ne 0 ] && exit 1
done

# Addons
mkdir -p "${RAMDISK_PATH}/addons"
echo "Create addons.sh" >>"${LOG_FILE}"
{
  echo "#!/usr/bin/env sh"
  echo 'echo "addons.sh called with params ${@}"'
  echo "export LOADERLABEL=\"ARC\""
  echo "export LOADERVERSION=\"${ARC_VERSION}\""
  echo "export LOADERBUILD=\"${ARC_BUILD}\""
  echo "export PLATFORM=\"${PLATFORM}\""
  echo "export MODEL=\"${MODEL}\""
  echo "export PRODUCTVER=\"${PRODUCTVER}\""
  echo "export MLINK=\"${PAT_URL}\""
  echo "export MCHECKSUM=\"${PAT_HASH}\""
  echo "export LAYOUT=\"${LAYOUT:-qwerty}\""
  echo "export KEYMAP=\"${KEYMAP:-en}\""
} >"${RAMDISK_PATH}/addons/addons.sh"
chmod +x "${RAMDISK_PATH}/addons/addons.sh"

# System Addons
SYSADDONS="revert misc eudev disks localrss notify mountloader"
if [ "${KVER:0:1}" = "5" ]; then
  SYSADDONS="redpill ${SYSADDONS}"
fi

for ADDON in ${SYSADDONS}; do
  if [ "${ADDON}" = "disks" ]; then
    [ -f "${USER_UP_PATH}/model.dts" ] && cp -f "${USER_UP_PATH}/model.dts" "${RAMDISK_PATH}/addons/model.dts"
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && cp -f "${USER_UP_PATH}/${MODEL}.dts" "${RAMDISK_PATH}/addons/model.dts"
  fi
  installAddon "${ADDON}" "${PLATFORM}" "${KVERP}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# User Addons
for ADDON in "${!ADDONS[@]}"; do
  if [ "${ADDON}" = "notification" ]; then
    WEBHOOKNOTIFY="$(readConfigKey "arc.webhooknotify" "${USER_CONFIG_FILE}")"
    [ "${WEBHOOKNOTIFY}" = "true" ] && WEBHOOK="$(readConfigKey "arc.webhook" "${USER_CONFIG_FILE}")"
    DISCORDNOTIFY="$(readConfigKey "arc.discordnotify" "${USER_CONFIG_FILE}")"
    [ "${DISCORDNOTIFY}" = "true" ] && DISCORDUSERID="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
    PARAMS="${WEBHOOK:-false} ${DISCORDUSERID:-false}"
  else
    PARAMS="${ADDONS[${ADDON}]}"
  fi
  installAddon "${ADDON}" "${PLATFORM}" "${KVERP}" || echo "Addon ${ADDON} not found"
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# Extract modules to ramdisk
installModules "${PLATFORM}" "${KVERP}" "${!MODULES[@]}" || exit 1

# Copying fake modprobe
[ "${KVER:0:1}" = "4" ] && cp -f "${PATCH_PATH}/iosched-trampoline.sh" "${RAMDISK_PATH}/usr/sbin/modprobe"
# Copying LKM to /usr/lib/modules
gzip -dc "${LKMS_PATH}/rp-${PLATFORM}-${KVERP}-${LKM}.ko.gz" >"${RAMDISK_PATH}/usr/lib/modules/rp.ko" 2>>"${LOG_FILE}" || exit 1

# Patch synoinfo.conf
echo -n "" >"${RAMDISK_PATH}/addons/synoinfo.conf"
for KEY in "${!SYNOINFO[@]}"; do
  echo "Set synoinfo ${KEY}" >>"${LOG_FILE}"
  echo "${KEY}=\"${SYNOINFO[${KEY}]}\"" >>"${RAMDISK_PATH}/addons/synoinfo.conf"
  _set_conf_kv "${RAMDISK_PATH}/etc/synoinfo.conf" "${KEY}" "${SYNOINFO[${KEY}]}" || exit 1
  _set_conf_kv "${RAMDISK_PATH}/etc.defaults/synoinfo.conf" "${KEY}" "${SYNOINFO[${KEY}]}" || exit 1
done
if [ ! -x "${RAMDISK_PATH}/usr/bin/get_key_value" ]; then
  printf '#!/bin/sh\n%s\n_get_conf_kv "$@"' "$(declare -f _get_conf_kv)" >"${RAMDISK_PATH}/usr/bin/get_key_value"
  chmod a+x "${RAMDISK_PATH}/usr/bin/get_key_value"
fi
if [ ! -x "${RAMDISK_PATH}/usr/bin/set_key_value" ]; then
  printf '#!/bin/sh\n%s\n_set_conf_kv "$@"' "$(declare -f _set_conf_kv)" >"${RAMDISK_PATH}/usr/bin/set_key_value"
  chmod a+x "${RAMDISK_PATH}/usr/bin/set_key_value"
fi

# Copying modulelist
if [ -f "${USER_UP_PATH}/modulelist" ]; then
  cp -f "${USER_UP_PATH}/modulelist" "${RAMDISK_PATH}/addons/modulelist"
else
  cp -f "${ARC_PATH}/include/modulelist" "${RAMDISK_PATH}/addons/modulelist"
fi

# backup current loader configs
mkdir -p "${RAMDISK_PATH}/usr/arc"
{
  echo "LOADERLABEL=\"Arc\""
  echo "LOADERVERSION=\"${ARC_VERSION}\""
  echo "LOADERBUILD=\"${ARC_BUILD}\""
} >"${RAMDISK_PATH}/usr/arc/VERSION"
BACKUP_PATH="${RAMDISK_PATH}/usr/arc/backup"
rm -rf "${BACKUP_PATH}"
for F in "${USER_GRUB_CONFIG}" "${USER_CONFIG_FILE}"; do
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
  echo -e "DEVICE=eth${N}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=auto_dhcp\nIPV6_ACCEPT_RA=1" >"${RAMDISK_PATH}/etc/sysconfig/network-scripts/ifcfg-eth${N}"
done

# Kernel 5.x patches
if [ "${KVER:0:1}" = "5" ]; then
  echo -e ">> apply Kernel 5.x Fixes"
  sed -i 's#/dev/console#/var/log/lrc#g' "${RAMDISK_PATH}/usr/bin/busybox"
  sed -i '/^echo "START/a \\nmknod -m 0666 /dev/console c 1 3' "${RAMDISK_PATH}/linuxrc.syno"
fi

# Broadwellntbap patches
if [ "${PLATFORM}" = "broadwellntbap" ]; then
  echo -e ">> apply Broadwellntbap Fixes"
  sed -i 's/IsUCOrXA="yes"/XIsUCOrXA="yes"/g; s/IsUCOrXA=yes/XIsUCOrXA=yes/g' "${RAMDISK_PATH}/usr/syno/share/environments.sh"
fi

# Reassembly ramdisk
rm -f "${MOD_RDGZ_FILE}"
if [ "${RD_COMPRESSED}" = "true" ]; then
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 --format=lzma >"${MOD_RDGZ_FILE}") >>"${LOG_FILE}" 2>&1 || exit 1
else
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${MOD_RDGZ_FILE}") >>"${LOG_FILE}" 2>&1 || exit 1
fi

sync

# Clean
rm -rf "${RAMDISK_PATH}"