#!/usr/bin/env bash

set -e

. /opt/arc/include/functions.sh

LOADER_DISK="$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1)"
BUS=$(udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2)
[ "${BUS}" = "ata" ] && BUS="sata"

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="${ARC_TITLE}"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;30m%*s\033[0m\n" ${COLUMNS} ""
TITLE="BOOTING..."
[ ${EFI} -eq 1 ] && TITLE+=" [EFI]" || TITLE+=" [Legacy]"
TITLE+=" [${BUS^^}]"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check if DSM zImage changed, patch it if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
ZIMAGE_HASH_CUR="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')"
if [ "${ZIMAGE_HASH_CUR}" != "${ZIMAGE_HASH}" ]; then
  echo -e "\033[1;31mDSM zImage changed\033[0m"
  if ! /opt/arc/zimage-patch.sh; then
    dialog --backtitle "$(backtitle)" --title "Error" \
      --msgbox "zImage not patched:\n$(<"${LOG_FILE}")" 12 70
    exit 1
  fi
  echo
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
if [ "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;31mDSM Ramdisk changed\033[0m"
  if ! /opt/arc/ramdisk-patch.sh; then
    dialog --backtitle "$(backtitle)" --title "Error" \
      --msgbox "Ramdisk not patched:\n$(<"${LOG_FILE}")" 12 70
    exit 1
  fi
  echo
fi

# Load necessary variables
VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
CPU="$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')"
MEM="$(free -m | grep -i mem | awk '{print$2}') MB"

echo -e "Model: \033[1;37m${MODEL}\033[0m"
echo -e "DSM: \033[1;37m${PRODUCTVER}\033[0m"
echo -e "LKM: \033[1;37m${LKM}\033[0m"
echo -e "CPU: \033[1;37m${CPU}\033[0m"
echo -e "MEM: \033[1;37m${MEM}\033[0m"
echo

if [ ! -f "${MODEL_CONFIG_PATH}/${MODEL}.yml" ] || [ -z "$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}]")" ]; then
  echo -e "\033[1;33m*** The current version of Arc does not support booting ${MODEL}-${PRODUCTVER}, please rebuild. ***\033[0m"
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
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

if [ ! "${BUS}" = "usb" ]; then
  LOADER_DEVICE_NAME=$(echo ${LOADER_DISK} | sed 's|/dev/||')
  SIZE=$(($(cat /sys/block/${LOADER_DEVICE_NAME}/size) / 2048 + 10))
  # Read SATADoM type
  DOM="$(readModelKey "${MODEL}" "dom")"
fi

# Validate netif_num
MACS=()
for N in $(seq 1 8); do  # Currently, only up to 8 are supported.
  [ -n "${CMDLINE["mac${N}"]}" ] && MACS+=(${CMDLINE["mac${N}"]})
done
NETIF_NUM=${#MACS[*]}
CMDLINE["netif_num"]=${NETIF_NUM}
ETHXNUM=$(ls /sys/class/net/ | grep eth | wc -l) # Amount of NIC
ETHX=($(ls /sys/class/net/ | grep eth))  # Real NIC List
if [ ${ETHXNUM} -gt 8 ]; then
  ETHX=8
  echo -e "\033[0;31m*** WARNING: More than 8 NIC are not supported.***\033[0m"
fi
# set missing mac to cmdline if needed
if [ ${NETIF_NUM} -ne ${ETHXNUM} ]; then
  for N in $(seq $((${NETIF_NUM} + 1)) ${ETHXNUM}); do 
    MACR="$(cat /sys/class/net/${ETHX[$((${N} - 1))]}/address | sed 's/://g')"
    # no duplicates
    while [[ "${MACS[*]}" =~ "${MACR}" ]]; do # no duplicates
      MACR="${MACR:0:10}$(printf "%02x" $((0x${MACR:10:2} + 1)))" 
    done
    CMDLINE["mac${N}"]="${MACR}"
  done
  CMDLINE["netif_num"]=${ETHXNUM}
fi

# Prepare command line
CMDLINE_LINE=""
grep -q "force_junior" /proc/cmdline && CMDLINE_LINE+="force_junior "
[ ${EFI} -eq 1 ] && CMDLINE_LINE+="withefi " || CMDLINE_LINE+="noefi "
[ ! "${BUS}" = "usb" ] && CMDLINE_LINE+="synoboot_satadom=${DOM} dom_szmax=${SIZE} "
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
CMDLINE_DIRECT=$(echo ${CMDLINE_DIRECT} | sed 's/>/\\\\>/g')
echo -e "Cmdline:\n\033[1;37m${CMDLINE_LINE}\033[0m"
echo

DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
DIRECTDSM="$(readConfigKey "arc.directdsm" "${USER_CONFIG_FILE}")"
NOTSETMAC="$(readConfigKey "arc.notsetmac" "${USER_CONFIG_FILE}")"
# Make Directboot persistent if DSM is installed
if [ "${DIRECTBOOT}" = "true" ] && [ "${DIRECTDSM}" = "true" ]; then
    grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
    grub-editenv ${GRUB_PATH}/grubenv set default="direct"
    echo -e "\033[1;34mEnable Directboot - DirectDSM\033[0m"
    echo -e "\033[1;34mDSM installed - Reboot with Directboot\033[0m"
    exec reboot
elif [ "${DIRECTBOOT}" = "true" ] && [ "${DIRECTDSM}" = "false" ]; then
    grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
    grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
    writeConfigKey "arc.directdsm" "true" "${USER_CONFIG_FILE}"
    echo -e "\033[1;34mDSM not installed - Reboot with Directboot\033[0m"
    exec reboot
elif [ "${DIRECTBOOT}" = "false" ]; then
  BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=20
  echo "Detected ${#ETHX[@]} NIC. DHCP - Waiting for Connection:"
  for N in $(seq 0 $((${#ETHX[@]} - 1))); do
    DRIVER=$(ls -ld /sys/class/net/${ETHX[${N}]}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    COUNT=0
    sleep 3
    while true; do
      if ethtool ${ETHX[${N}]} | grep 'Link detected' | grep -q 'no'; then
        echo -e "\r${DRIVER}: NOT CONNECTED"
        break
      fi
      IP=$(ip route show dev ${ETHX[${N}]} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p')
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${ETHX[${N}]} | grep "Speed:" | awk '{print $2}')
        echo -e "\r${DRIVER} (${SPEED}): Access \033[1;34mhttp://${IP}:5000\033[0m to connect the DSM via web."
        break
      fi
      COUNT=$((${COUNT} + 1))
      if [ ${COUNT} -eq ${BOOTIPWAIT} ]; then
        echo -e "\r${DRIVER}: TIMEOUT."
        break
      fi
      sleep 1
    done
  done
  NOTSETMAC="$(readConfigKey "arc.notsetmac" "${USER_CONFIG_FILE}")"
  if [ "${NOTSETMAC}" = "true" ]; then
    echo -e "\r\033[1;34mDisable Boot MAC is true, the DSM IP can be different!\033[0m"
  fi
  BOOTWAIT="$(readConfigKey "arc.bootwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTWAIT}" ] && BOOTWAIT=10
  w | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while test ${BOOTIPWAIT} -ge 0; do
    MSG="$(printf "%2ds (accessing Arc will interrupt boot)" "${BOOTWAIT}")"
    echo -en "\r${MSG}"
    w | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      echo -en "\rA new access is connected, the boot process is interrupted.\n"
      rm -f WB WC
      exit 0
    fi
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
  done
  rm -f WB WC
  echo -en "\r$(printf "%${#MSG}s" " ")\n"
fi
echo
echo -e "\033[1;37mLoading DSM kernel...\033[0m"

# Executes DSM kernel via KEXEC
kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
echo -e "\033[1;37m"Booting DSM..."\033[0m"
for T in $(w | grep -v "TTY" | awk -F' ' '{print $2}')
do
  echo -e "\n\033[1;37mThis interface will not be operational. Please use \033[1;34mhttp://find.synology.com/ \033[1;37mto find DSM and connect.\033[0m\n" >"/dev/${T}" 2>/dev/null || true
done 
KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
[ "${KERNELLOAD}" = "kexec" ] && kexec -f -e || poweroff
exit 0