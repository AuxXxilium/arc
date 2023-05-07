#!/usr/bin/env bash

. /opt/arpl/include/functions.sh

set -e

# Sanity check
loaderIsConfigured || die "Loader is not configured!"

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="Arc v${ARPL_VERSION}"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE}+${COLUMNS})/2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""
TITLE="BOOTING..."
printf "\033[1;33m%*s\033[0m\n" $(((${#TITLE}+${COLUMNS})/2)) "${TITLE}"

# Arc Functions
DIRECTBOOT="`readConfigKey "arc.directboot" "${USER_CONFIG_FILE}"`"
DIRECTDSM="`readConfigKey "arc.directdsm" "${USER_CONFIG_FILE}"`"
GRUBCONF=`grub-editenv ${GRUB_PATH}/grubenv list | wc -l`
BACKUPBOOT="`readConfigKey "arc.backupboot" "${USER_CONFIG_FILE}"`"
if [ "${BACKUPBOOT}" = "true" ]; then
  # Uncompress backup
  tar -xvf ${BACKUPDIR}/arc-backup.tar -C /
  sleep 1
  USER_CONFIG_FILE=${BB_USER_CONFIG_FILE}
fi
CONSOLE=`cat ${USER_CONFIG_FILE} | grep "console:" | wc -w`

# Check if DSM zImage changed, patch it if necessary
ZIMAGE_HASH="`readConfigKey "zimage-hash" "${USER_CONFIG_FILE}"`"
if [ "`sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print$1}'`" != "${ZIMAGE_HASH}" ]; then
  echo -e "\033[1;43mDSM zImage changed\033[0m"
  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" \
      --msgbox "zImage not patched:\n`<"${LOG_FILE}"`" 12 70
    exit 1
  fi
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="`readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}"`"
if [ "`sha256sum "${ORI_RDGZ_FILE}" | awk '{print$1}'`" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;43mDSM Ramdisk changed\033[0m"
  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" \
      --msgbox "Ramdisk not patched:\n`<"${LOG_FILE}"`" 12 70
    exit 1
  fi
fi

# Load necessary variables
VID="`readConfigKey "vid" "${USER_CONFIG_FILE}"`"
PID="`readConfigKey "pid" "${USER_CONFIG_FILE}"`"
MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"

echo -e "Model: \033[1;36m${MODEL}\033[0m"
echo -e "Build: \033[1;36m${BUILD}\033[0m"

if [ ! -f "${MODEL_CONFIG_PATH}/${MODEL}.yml" ] || [ -z "`readConfigKey "builds.${BUILD}" "${MODEL_CONFIG_PATH}/${MODEL}.yml"`" ]; then
  echo -e "\033[1;33m*** The current version does not support booting for ${MODEL} and ${BUILD}, please rebuild. ***\033[0m"
  exit 1
fi

declare -A CMDLINE

# Fixed values
CMDLINE['netif_num']=0
# Automatic values
CMDLINE['syno_hw_version']="${MODEL}"
[ -z "${VID}" ] && VID="0x0000" # Sanity check
[ -z "${PID}" ] && PID="0x0000" # Sanity check
CMDLINE['vid']="${VID}"
CMDLINE['pid']="${PID}"
CMDLINE['sn']="${SN}"

# Read cmdline
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readModelMap "${MODEL}" "builds.${BUILD}.cmdline")
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

LOADER_DISK=`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`
BUS=`udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2`
if [ "${BUS}" = "ata" ]; then
  LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
  SIZE=$((`cat /sys/block/${LOADER_DEVICE_NAME}/size`/2048+10))
  # Read SATADoM type
  DOM="`readModelKey "${MODEL}" "dom"`"
fi

# Validate netif_num
NETIF_NUM=${CMDLINE["netif_num"]}
NETNUM=`lshw -class network -short | grep -ie "eth[0-9]" | wc -l`
[ ${NETNUM} -gt 8 ] && NETNUM=8 && echo -e "\033[1;33m*** WARNING: Only 8 Ethernet ports are supported by Redpill***\033[0m"
if [ ${NETIF_NUM} -ne ${NETNUM} ]; then
  echo -e "\033[1;33m*** netif_num is not equal to macX amount, set netif_num to ${NETNUM} ***\033[0m"
  CMDLINE["netif_num"]=${NETNUM}
fi

# Prepare command line
CMDLINE_LINE=""
grep -q "force_junior" /proc/cmdline && CMDLINE_LINE+="force_junior "
[ ${EFI} -eq 1 ] && CMDLINE_LINE+="withefi " || CMDLINE_LINE+="noefi "
[ "${BUS}" = "ata" ] && CMDLINE_LINE+="synoboot_satadom=${DOM} dom_szmax=${SIZE} "
CMDLINE_DIRECT="${CMDLINE_LINE}"
CMDLINE_LINE+="console=ttyS0,115200n8 earlyprintk earlycon=uart8250,io,0x3f8,115200n8 root=/dev/md0 loglevel=15 log_buf_len=32M"
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  CMDLINE_DIRECT+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
  [ -n "${VALUE}" ] && CMDLINE_DIRECT+="=${VALUE}"
done
# Escape special chars
#CMDLINE_LINE=`echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g'`
CMDLINE_DIRECT=`echo ${CMDLINE_DIRECT} | sed 's/>/\\\\>/g'`
echo -e "Cmdline:\n\033[1;36m${CMDLINE_LINE}\033[0m"

# Wait for an IP
COUNT=0
echo -n "IP"
while true; do
  IPLIST="`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p'`"
  if [ -n "${IPLIST}" ]; then
    echo -e ": \033[1;32m\n${IPLIST}\033[0m"
    break
  fi
  if [ ${COUNT} -eq 30 ]; then
    echo -e ": \033[1;31m\nERROR\033[0m"
    break
  fi
  sleep 3
  COUNT=$((${COUNT}+3))
done

# Make Directboot persistent if DSM is installed
if [ "${DIRECTBOOT}" = "true" ]; then
  if [ "${DIRECTDSM}" = "true" ]; then
    #if [ ${GRUBCONF} -eq 0 ]; then
      grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
      grub-editenv ${GRUB_PATH}/grubenv set default="direct"
      echo -e "\033[1;33mEnable Directboot - DirectDSM\033[0m"
    #fi
    echo -e "\033[1;33mDSM installed - Reboot with Directboot\033[0m"
    reboot
    exit 0
  elif [ "${DIRECTDSM}" = "false" ]; then
    grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
    echo -e "\033[1;33mDSM not installed - Reboot with Directboot\033[0m"
    grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
    writeConfigKey "arc.directdsm" "true" "${USER_CONFIG_FILE}"
    reboot
    exit 0
  fi
elif [ "${DIRECTBOOT}" = "false" ] && [ ${GRUBCONF} -gt 0 ]; then
    grub-editenv ${GRUB_PATH}/grubenv create
    echo -e "\033[1;33mDisable Directboot - DirectDSM\033[0m"
    writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
fi

echo -e "\033[1;37mLoading DSM kernel...\033[0m"

if [ "${BACKUPBOOT}" = "true" ]; then
  # Executes DSM kernel via KEXEC
  kexec -l "${BB_MOD_ZIMAGE_FILE}" --initrd "${BB_MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  echo -e "\033[1;37mBooting Backup DSM...\033[0m"
  if [ ${CONSOLE} -gt 0 ]; then
    echo -e "\033[1;37mWaiting for DSM Console...\033[0m"
    poweroff
  else
    kexec -e
  fi
  exit 0
elif [ "${BACKUPBOOT}" = "false" ] || [ "${BACKUPBOOT}" = "" ]; then
  # Executes DSM kernel via KEXEC
  kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  echo -e "\033[1;37mBooting DSM...\033[0m"
  if [ ${CONSOLE} -gt 0 ]; then
    echo -e "\033[1;37mWaiting for DSM Console...\033[0m"
    poweroff
  else
    kexec -e
  fi
  exit 0
fi