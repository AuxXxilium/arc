#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh

set -o pipefail # Get exit code from process piped

# Sanity check
if [ ! -f "${ORI_RDGZ_FILE}" ]; then
  echo "ERROR: ${ORI_RDGZ_FILE} not found!" >"${LOG_FILE}"
  exit 1
fi

echo -e "Patching Ramdisk"

# Remove old rd.gz patched
rm -f "${MOD_RDGZ_FILE}"

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
SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
PLATFORM="$(readModelKey "${MODEL}" "platform")"
HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
KVMSUPPORT="$(readConfigKey "arc.kvm" "${USER_CONFIG_FILE}")"
MODULESCOPY="$(readConfigKey "arc.modulescopy" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

# Check if DSM Version changed
. "${RAMDISK_PATH}/etc/VERSION"

# Read DSM Informations
PRODUCTVERDSM="${majorversion}.${minorversion}"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
RD_COMPRESSED="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].rd-compressed")"
# Read new PAT Info from Config
PAT_URL="$(readConfigKey "arc.paturl" "${USER_CONFIG_FILE}")"
PAT_HASH="$(readConfigKey "arc.pathash" "${USER_CONFIG_FILE}")"

[ "${PAT_URL:0:1}" = "#" ] && PAT_URL=""
[ "${PAT_HASH:0:1}" = "#" ] && PAT_URL=""

if [ "${PRODUCTVERDSM}" != "${PRODUCTVER}" ]; then
  # Update new buildnumber
  echo -e "Ramdisk Version ${PRODUCTVER} does not match DSM Version ${PRODUCTVERDSM}!"
  echo -e "Try to use DSM Version ${PRODUCTVERDSM} for Patch."
  writeConfigKey "productver" "${USER_CONFIG_FILE}"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  PAT_URL=""
  PAT_HASH=""
fi

# Sanity check
if [[ -z "${PLATFORM}" || -z "${KVER}" ]]; then
  echo "ERROR: Configuration for model ${MODEL} and productversion ${PRODUCTVER} not found." >"${LOG_FILE}"
  exit 1
fi

# Modify KVER for Epyc7002
if [ "${PLATFORM}" = "epyc7002" ]; then
  KVER="${PRODUCTVER}-${KVER}"
fi

declare -A SYNOINFO
declare -A ADDONS
declare -A MODULES

# Read synoinfo from config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")
# Read synoinfo from config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")
# Read modules from config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && MODULES["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "modules" "${USER_CONFIG_FILE}")

# Patches (diff -Naru OLDFILE NEWFILE > xxx.patch)
while read -r PE; do
  RET=1
  echo "Patching with ${PE}" >"${LOG_FILE}"
  for PF in $(ls ${PATCH_PATH}/${PE} 2>/dev/null); do
    echo "Patching with ${PF}" >>"${LOG_FILE}"
    (
      cd "${RAMDISK_PATH}"
      busybox patch -p1 -i "${PF}" >>"${LOG_FILE}" 2>&1 # busybox patch and gun patch have different processing methods and parameters.
    )
    RET=$?
    [ ${RET} -eq 0 ] && break
  done
  [ ${RET} -ne 0 ] && exit 1
done <<<$(readModelArray "${MODEL}" "productvers.[${PRODUCTVER}].patch")

# Patch /etc/synoinfo.conf
# Add serial number to synoinfo.conf, to help to recovery a installed DSM
echo "Set synoinfo SN" >"${LOG_FILE}"
_set_conf_kv "SN" "${SN}" "${RAMDISK_PATH}/etc/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
for KEY in ${!SYNOINFO[@]}; do
  echo "Set synoinfo ${KEY}" >>"${LOG_FILE}"
  _set_conf_kv "${KEY}" "${SYNOINFO[${KEY}]}" "${RAMDISK_PATH}/etc/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
done

# Patch /sbin/init.post
grep -v -e '^[\t ]*#' -e '^$' "${PATCH_PATH}/config-manipulators.sh" >"${TMP_PATH}/rp.txt"
sed -e "/@@@CONFIG-MANIPULATORS-TOOLS@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm -f "${TMP_PATH}/rp.txt"
touch "${TMP_PATH}/rp.txt"
for KEY in ${!SYNOINFO[@]}; do
  echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
  echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc.defaults/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
done
echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc.defaults/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
sed -e "/@@@CONFIG-GENERATED@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm -f "${TMP_PATH}/rp.txt"

# Extract Modules to Ramdisk
installModules "${PLATFORM}" "${KVER}" "${!MODULES[@]}" || exit 1

# Copying fake modprobe
cp -f "${PATCH_PATH}/iosched-trampoline.sh" "${RAMDISK_PATH}/usr/sbin/modprobe"
# Copying LKM to /usr/lib/modules
gzip -dc "${LKM_PATH}/rp-${PLATFORM}-${KVER}-${LKM}.ko.gz" >"${RAMDISK_PATH}/usr/lib/modules/rp.ko" 2>"${LOG_FILE}" || exit 1

# Addons
echo "Create addons.sh" >"${LOG_FILE}"
mkdir -p "${RAMDISK_PATH}/addons"
echo "#!/bin/sh" >"${RAMDISK_PATH}/addons/addons.sh"
echo 'echo "addons.sh called with params ${@}"' >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LOADERLABEL=ARC" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LOADERVERSION=${ARC_VERSION}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export PLATFORM=${PLATFORM}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MODEL=${MODEL}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MLINK=${PAT_URL}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MCHECKSUM=${PAT_HASH}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LAYOUT=${LAYOUT}" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export KEYMAP=${KEYMAP}" >>"${RAMDISK_PATH}/addons/addons.sh"
chmod +x "${RAMDISK_PATH}/addons/addons.sh"

# Required addons: "revert" "misc" "eudev" "disks" "localrss" "wol"
# This order cannot be changed.
for ADDON in "revert" "misc" "eudev" "disks" "localrss" "notify" "wol"; do
  PARAMS=""
  if [ "${ADDON}" = "disks" ]; then
    PARAMS="${HDDSORT} ${USBMOUNT}"
  fi
  if [ "${ADDON}" = "eudev" ]; then
    PARAMS="${MODULESCOPY} ${KVMSUPPORT}"
  fi
  installAddon "${ADDON}" "${PLATFORM}" "${KVER}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# User Addons
for ADDON in ${!ADDONS[@]}; do
  PARAMS=${ADDONS[${ADDON}]}
  installAddon "${ADDON}" "${PLATFORM}" "${KVER}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# Enable Telnet
echo "inetd" >>"${RAMDISK_PATH}/addons/addons.sh"

echo "Modify files" >"${LOG_FILE}"
# Remove function from scripts
[ "2" = "${BUILDNUM:0:1}" ] && sed -i 's/function //g' $(find "${RAMDISK_PATH}/addons/" -type f -name "*.sh")

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
IPV6="$(readConfigKey "arc.ipv6" "${USER_CONFIG_FILE}")"
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
for ETH in ${ETHX}; do
  if [ "${IPV6}" = "true" ]; then
    echo -e "DEVICE=${ETH}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=dhcp\nIPV6_ACCEPT_RA=1" >"${RAMDISK_PATH}/etc/sysconfig/network-scripts/ifcfg-${ETH}"
  else
    echo -e "DEVICE=${ETH}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=no" >"${RAMDISK_PATH}/etc/sysconfig/network-scripts/ifcfg-${ETH}"
  fi
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

#if [ "${PLATFORM}" = "kvmx64" ]; then
#  sed -i 's/kvmx64/RRING/g' ${RAMDISK_PATH}/etc/synoinfo.conf ${RAMDISK_PATH}/etc/VERSION
#fi

# Call user patch scripts
for F in $(ls -1 ${SCRIPTS_PATH}/*.sh 2>/dev/null); do
  echo "Calling ${F}" >"${LOG_FILE}"
  . "${F}" >>"${LOG_FILE}" 2>&1 || exit 1
done

# Reassembly ramdisk
if [ "${RD_COMPRESSED}" == "true" ]; then
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 --format=lzma >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
else
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
fi

sync

# Clean
rm -rf "${RAMDISK_PATH}"