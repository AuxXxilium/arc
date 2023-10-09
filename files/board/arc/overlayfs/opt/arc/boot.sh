#0!/usr/bin/env bash

set -e

. /opt/arc/include/functions.sh

LOADER_DISK="$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1)"
BUS=$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_BUS | cut -d= -f2)
[ "${BUS}" = "ata" ] && BUS="sata"

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

# Print text centralized
clear
COLUMNS=${COLUMNS:-50}
TITLE="${ARC_TITLE}"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;30m%*s\033[0m\n" ${COLUMNS} ""
TITLE="BOOTING:"
[ ${EFI} -eq 1 ] && TITLE+=" [EFI]" || TITLE+=" [Legacy]"
TITLE+=" [${BUS^^}]"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check if DSM zImage/Ramdisk is changed, patch it if necessary, update Files if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
ZIMAGE_HASH_CUR="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')"
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
if [ "${ZIMAGE_HASH_CUR}" != "${ZIMAGE_HASH}" ] || [ "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;34mDSM zImage/Ramdisk changed! Try to Patch them.\033[0m"
  livepatch
  if [ ${FAIL} -eq 1 ]; then
    echo -e "\033[1;34mPatching DSM Files failed! Please stay patient for Update.\033[0m" 0 0
    exit 1
  fi
fi

# Read model/system variables
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
CPU="$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')"
RAMTOTAL=0
while read -r LINE; do
  RAMSIZE=${LINE}
  RAMTOTAL=$((${RAMTOTAL} + ${RAMSIZE}))
done < <(dmidecode -t memory | grep -i "Size" | cut -d" " -f2 | grep -i "[1-9]")
VENDOR="$(dmidecode -s system-product-name)"
BOARD="$(dmidecode -s baseboard-product-name)"

echo -e "\033[1;37mDSM:\033[0m"
echo -e "Model: \033[1;37m${MODEL}\033[0m"
echo -e "Version: \033[1;37m${PRODUCTVER}\033[0m"
echo -e "LKM: \033[1;37m${LKM}\033[0m"
echo -e "Macsys: \033[1;37m${MACSYS}\033[0m"
echo
echo -e "\033[1;37mSystem:\033[0m"
echo -e "Vendor | Board: \033[1;37m${VENDOR}\033[0m | \033[1;37m${BOARD}\033[0m"
echo -e "CPU: \033[1;37m${CPU}\033[0m"
echo -e "MEM: \033[1;37m${RAMTOTAL}GB\033[0m"
echo

if [ ! -f "${MODEL_CONFIG_PATH}/${MODEL}.yml" ] || [ -z "$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}]")" ]; then
  echo -e "\033[1;33m*** The current version of Arc does not support booting ${MODEL}-${PRODUCTVER}, please rebuild. ***\033[0m"
  exit 1
fi

HASATA=0
for D in $(lsblk -dnp -o name); do
  [ "${D}" = "${LOADER_DISK}" ] && continue
  if [ "$(udevadm info --query property --name ${D} | grep ID_BUS | cut -d= -f2)" = "ata" ]; then
    HASATA=1
    break
  fi
done
[ ${HASATA} = "0" ] &&  echo -e "\033[1;33m*** Please insert at least one Sata/SAS Disk for System Installation, except the Bootloader Disk. ***\033[0m"

# Read necessary variables
VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "arc.kernelpanic" "${USER_CONFIG_FILE}")"
DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
BOOTCOUNT="$(readConfigKey "arc.bootcount" "${USER_CONFIG_FILE}")"
[ -z "${BOOTCOUNT}" ] && BOOTCOUNT=0

declare -A CMDLINE

# Automatic values
CMDLINE['syno_hw_version']="${MODEL}"
[ -z "${VID}" ] && VID="0x46f4" # Sanity check
[ -z "${PID}" ] && PID="0x0001" # Sanity check
CMDLINE['vid']="${VID}"
CMDLINE['pid']="${PID}"
CMDLINE['sn']="${SN}"
if [ "$MACSYS" = "new" ]; then
  MAC1="$(readConfigKey "arc.mac1" "${USER_CONFIG_FILE}")"
  CMDLINE['mac1']="${MAC1}"
  CMDLINE['netif_num']="1"
elif [ "$MACSYS" = "old" ]; then
  NIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  for N in $(seq 1 ${NIC}); do  # Currently, only up to 8 are supported.
    MAC="$(readConfigKey "arc.mac${N}" "${USER_CONFIG_FILE}")"
    [ -n "${MAC}" ] && CMDLINE['mac${N}']="${MAC}"
    [ -z "${MAC}" ] && CMDLINE['mac${N}']="$(cat /sys/class/net/${ETHX[$((${N} - 1))]}/address | sed 's/://g')"
  done
  CMDLINE["netif_num"]=${NIC}
fi

# Read cmdline
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
if [ ! "${BUS}" = "usb" ]; then
  LOADER_DEVICE_NAME=$(echo "${LOADER_DISK}" | sed 's|/dev/||')
  SIZE=$(($(cat /sys/block/${LOADER_DEVICE_NAME}/size) / 2048 + 10))
  # Read SATADoM type
  DOM="$(readModelKey "${MODEL}" "dom")"
fi

# Prepare command line
CMDLINE_LINE=""
grep -q "force_junior" /proc/cmdline && CMDLINE_LINE+="force_junior "
[ ${EFI} -eq 1 ] && CMDLINE_LINE+="withefi " || CMDLINE_LINE+="noefi "
[ ! "${BUS}" = "usb" ] && CMDLINE_LINE+="synoboot_satadom=${DOM} dom_szmax=${SIZE} "
if [ "$MACSYS" = "new" ]; then
  CMDLINE_LINE+="panic=${KERNELPANIC:-0} console=ttyS0,115200n8 earlyprintk earlycon=uart8250,io,0x3f8,115200n8 root=/dev/md0 skip_vender_mac_interfaces=0,1,2,3,4,5,6,7 loglevel=15 log_buf_len=32M"
elif [ "$MACSYS" = "old" ]; then
  CMDLINE_LINE+="panic=${KERNELPANIC:-0} console=ttyS0,115200n8 earlyprintk earlycon=uart8250,io,0x3f8,115200n8 root=/dev/md0 loglevel=15 log_buf_len=32M"
fi
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
echo -e "\033[1;37mCmdline:\033[0m\n${CMDLINE_LINE}"
echo

# Make Directboot persistent if DSM is installed
if [ "${DIRECTBOOT}" = "true" ] && [ ${BOOTCOUNT} -gt 0 ]; then
  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
  grub-editenv ${GRUB_PATH}/grubenv set default="direct"
  BOOTCOUNT=$((${BOOTCOUNT} + 1))
  writeConfigKey "arc.bootcount" "${BOOTCOUNT}" "${USER_CONFIG_FILE}"
  echo -e "\033[1;34mDSM installed - Make Directboot persistent\033[0m"
  exec reboot
elif [ "${DIRECTBOOT}" = "true" ] && [ ${BOOTCOUNT} -eq 0 ]; then
  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
  grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
  BOOTCOUNT=$((${BOOTCOUNT} + 1))
  writeConfigKey "arc.bootcount" "${BOOTCOUNT}" "${USER_CONFIG_FILE}"
  echo -e "\033[1;34mDSM not installed - Reboot with Directboot\033[0m"
  exec reboot
elif [ "${DIRECTBOOT}" = "false" ]; then
  ETHX=($(ls /sys/class/net/ | grep eth)) # real network cards list
  # Read Ip Settings
  STATICIP="$(readConfigKey "arc.staticip" "${USER_CONFIG_FILE}")"
  BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
  echo -e "\033[1;34mDetected ${#ETHX[@]} NIC.\033[0m \033[1;37mWaiting for Connection:\033[0m"
  for N in $(seq 0 $((${#ETHX[@]} - 1))); do
    DRIVER=$(ls -ld /sys/class/net/${ETHX[${N}]}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    COUNT=0
    while true; do
      if ethtool ${ETHX[${N}]} | grep 'Link detected' | grep -q 'no'; then
        echo -e "\r${DRIVER}: NOT CONNECTED"
        break
      fi
      IP=$(ip route show dev ${ETHX[${N}]} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p')
      if [ "${STATICIP}" = "true" ]; then
        ARCIP="$(readConfigKey "arc.ip" "${USER_CONFIG_FILE}")"
        NETMASK="$(readConfigKey "arc.netmask" "${USER_CONFIG_FILE}")"
        if [ "${ETHX[${N}]}" = "eth0" ] && [ -n "${ARCIP}" ] && [ ${BOOTCOUNT} -gt 0 ]; then
          IP="${ARCIP}"
          NETMASK=$(convert_netmask "${NETMASK}")
          ip addr add ${IP}/${NETMASK} dev eth0
          MSG="STATIC"
        else
          MSG="DHCP"
        fi
      else
        MSG="DHCP"
      fi
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${ETHX[${N}]} | grep "Speed:" | awk '{print $2}')
        echo -e "\r\033[1;37m${DRIVER} (${SPEED} | ${MSG}):\033[0m Access \033[1;34mhttp://${IP}:5000\033[0m to connect to DSM via web."
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
  BOOTWAIT="$(readConfigKey "arc.bootwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTWAIT}" ] && BOOTWAIT=5
  w | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while test ${BOOTWAIT} -ge 0; do
    MSG="$(printf "%2ds (Accessing Arc Overlay will interrupt Boot)" "${BOOTWAIT}")"
    echo -en "\r${MSG}"
    w | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      echo -en "\rA new access is connected, Boot is interrupted.\n"
      rm -f WB WC
      exit 0
    fi
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
  done
  rm -f WB WC
  echo -en "\r$(printf "%$((${#MSG} * 3))s" " ")\n"
fi
echo -e "\033[1;37mLoading DSM kernel...\033[0m"

# Write new Bootcount
BOOTCOUNT=$((${BOOTCOUNT} + 1))
writeConfigKey "arc.bootcount" "${BOOTCOUNT}" "${USER_CONFIG_FILE}"
# Executes DSM kernel via KEXEC
kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
echo -e "\033[1;37m"Booting DSM..."\033[0m"
for T in $(w | grep -v "TTY" | awk -F' ' '{print $2}')
do
  echo -e "\n\033[1;37mThis interface will not be operational. Please use \033[1;34mhttps://finds.synology.com/ \033[1;37mto find DSM and connect.\033[0m\n" >"/dev/${T}" 2>/dev/null || true
done
[ "${KERNELLOAD}" = "kexec" ] && kexec -f -e || poweroff
exit 0