#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Sanity check
loaderIsConfigured || die "Loader is not configured!"

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="${ARPL_TITLE}"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE}+${COLUMNS})/2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""
TITLE="BOOTING..."
printf "\033[1;33m%*s\033[0m\n" $(((${#TITLE}+${COLUMNS})/2)) "${TITLE}"

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

# Arc Functions
DIRECTBOOT="`readConfigKey "arc.directboot" "${USER_CONFIG_FILE}"`"
DIRECTDSM="`readConfigKey "arc.directdsm" "${USER_CONFIG_FILE}"`"
GRUBCONF=`grub-editenv ${GRUB_PATH}/grubenv list | wc -l`

# Load necessary variables
VID="`readConfigKey "vid" "${USER_CONFIG_FILE}"`"
PID="`readConfigKey "pid" "${USER_CONFIG_FILE}"`"
MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"

echo -e "Model: \033[1;36m${MODEL}\033[0m"
echo -e "Build: \033[1;36m${BUILD}\033[0m"

if [ ! -f "${MODEL_CONFIG_PATH}/${MODEL}.yml" ] || [ -z "`readConfigKey "builds.${BUILD}" "${MODEL_CONFIG_PATH}/${MODEL}.yml"`" ]; then
  echo -e "\033[1;33m*** `printf "The current version of arpl does not support booting %s-%s, please rebuild." "${MODEL}" "${BUILD}"` ***\033[0m"
  exit 1
fi

declare -A CMDLINE

# Fixed values
#CMDLINE['netif_num']=0
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
# 
KVER=`readModelKey "${MODEL}" "builds.${BUILD}.kver"`

LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
BUS=`udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2`
if [ "${BUS}" = "ata" ]; then
  LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
  SIZE=$((`cat /sys/block/${LOADER_DEVICE_NAME}/size`/2048+10))
  # Read SATADoM type
  DOM="`readModelKey "${MODEL}" "dom"`"
fi

# Validate netif_num
MACS=()
for N in `seq 1 8`; do  # Currently, only up to 8 are supported.  (<==> menu.sh L396, <==> lkm: MAX_NET_IFACES)
  [ -n "${CMDLINE["mac${N}"]}" ] && MACS+=(${CMDLINE["mac${N}"]})
done
NETIF_NUM=${#MACS[*]}
NETRL_NUM=`ls /sys/class/net/ | grep eth | wc -l` # real network cards amount
if [ ${NETIF_NUM} -eq 0 ]; then
  echo -e "\033[1;33m*** `printf "Detected %s network cards, but No MACs were customized, they will use the original MACs." "${NETRL_NUM}"` ***\033[0m"
else
  # set netif_num to custom mac amount, netif_num must be equal to the MACX amount, otherwise the kernel will panic.
  CMDLINE["netif_num"]=${NETIF_NUM}  # The current original CMDLINE['netif_num'] is no longer in use, Consider deleting.
  if [ ${NETIF_NUM} -le ${NETRL_NUM} ]; then
    echo -e "\033[1;33m*** `printf "%s network cards dedected, %s MACs were customized, the rest will use the original MACs." "${NETRL_NUM}" "${CMDLINE["netif_num"]}"` ***\033[0m"
    ETHX=(`ls /sys/class/net/ | grep eth`)  # real network cards list
    for N in `seq $(expr ${NETIF_NUM} + 1) ${NETRL_NUM}`; do 
      MACR="`cat /sys/class/net/${ETHX[$(expr ${N} - 1)]}/address | sed 's/://g'`"
      # no duplicates
      while [[ "${MACS[*]}" =~ "$MACR" ]]; do # no duplicates
        MACR="${MACR:0:10}`printf "%02x" $((0x${MACR:10:2} + 1))`" 
      done
      CMDLINE["mac${N}"]="${MACR}"
    done
    CMDLINE["netif_num"]=${NETRL_NUM}
  fi
fi

# Prepare command line
CMDLINE_LINE=""
grep -q "force_junior" /proc/cmdline && CMDLINE_LINE+="force_junior "
[ ${EFI} -eq 1 ] && CMDLINE_LINE+="withefi " || CMDLINE_LINE+="noefi "
[ "${BUS}" = "ata" ] && CMDLINE_LINE+="synoboot_satadom=${DOM} dom_szmax=${SIZE} "
CMDLINE_LINE+="console=ttyS0,115200n8 earlyprintk earlycon=uart8250,io,0x3f8,115200n8 root=/dev/md0 loglevel=15 log_buf_len=32M"
CMDLINE_DIRECT="${CMDLINE_LINE}"
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

# Make Directboot persistent if DSM is installed
if [ "${DIRECTBOOT}" = "true" ]; then
  if [ "${DIRECTDSM}" = "true" ]; then
    grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
    grub-editenv ${GRUB_PATH}/grubenv set default="direct"
    echo -e "\033[1;33mEnable Directboot - DirectDSM\033[0m"
    echo -e "\033[1;33mDSM installed - Reboot with Directboot\033[0m"
    reboot
  elif [ "${DIRECTDSM}" = "false" ]; then
    grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
    grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
    writeConfigKey "arc.directdsm" "true" "${USER_CONFIG_FILE}"
    echo -e "\033[1;33mDSM not installed - Reboot with Directboot\033[0m"
    reboot
  fi
  exit 0
elif [ "${DIRECTBOOT}" = "false" ] && [ ${GRUBCONF} -gt 0 ]; then
    grub-editenv ${GRUB_PATH}/grubenv create
    echo -e "\033[1;33mDisable Directboot - DirectDSM\033[0m"
    writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
fi

ETHX=(`ls /sys/class/net/ | grep eth`)  # real network cards list
echo "`printf "Detected %s network cards, Waiting IP." "${#ETHX[@]}"`"
for N in $(seq 0 $(expr ${#ETHX[@]} - 1)); do
  COUNT=0
  echo -en "${ETHX[${N}]}: "
  while true; do
    if [ -z "`ip link show ${ETHX[${N}]} | grep 'UP'`" ]; then
      echo -en "\r${ETHX[${N}]}: DOWN\n"
      break
    fi
    if [ ${COUNT} -eq 8 ]; then # Under normal circumstances, no errors should occur here.
      echo -en "\r${ETHX[${N}]}: ERROR\n"
      break
    fi
    COUNT=$((${COUNT}+1))
    IP=`ip route show dev ${ETHX[${N}]} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p'`
    if [ -n "${IP}" ]; then
      echo -en "\r${ETHX[${N}]}: `printf "Access \033[1;34mhttp://%s:5000\033[0m to connect the DSM via web." "${IP}"`\n"
      break
    fi
    echo -n "."
    sleep 1
  done
done

echo -e "\033[1;37mLoading DSM kernel...\033[0m"

# Executes DSM kernel via KEXEC
kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
echo -e "\033[1;37m"Booting DSM..."\033[0m"
for T in `w | grep -v "TTY" | awk -F' ' '{print $2}'`
do
  echo -e "\n\033[1;43m[This interface will not be operational. Please use the http://find.synology.com/ find DSM and connect.]\033[0m\n" > "/dev/${T}" 2>/dev/null || true
done 
poweroff
exit 0