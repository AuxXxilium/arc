#!/usr/bin/env bash

set -e
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh

# Get Loader Disk Bus
BUS=$(getBus "${LOADER_DISK}")

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

# Print Title centralized
clear
COLUMNS=${COLUMNS:-50}
BANNER="$(figlet -c -w "$(((${COLUMNS})))" "Arc Loader")"
TITLE="Version:"
TITLE+=" ${ARC_TITLE}"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" ${COLUMNS} "${BANNER}"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
TITLE="Boot:"
[ ${EFI} -eq 1 ] && TITLE+=" [UEFI]" || TITLE+=" [Legacy]"
TITLE+=" [${BUS}]"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check if DSM zImage/Ramdisk is changed, patch it if necessary, update Files if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
ZIMAGE_HASH_CUR="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')"
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
if [[ "${ZIMAGE_HASH_CUR}" != "${ZIMAGE_HASH}" || "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]]; then
  echo -e "\033[1;31mDSM zImage/Ramdisk changed!\033[0m"
  livepatch
  echo
fi

# Read model/system variables
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
CPU="$(echo $(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}'))"
RAMTOTAL=$(($(free -m | grep -i mem | awk '{print$2}') / 1024 + 1))
RAM="${RAMTOTAL}GB"
VENDOR="$(dmesg 2>/dev/null | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')"

echo -e "\033[1;37mDSM:\033[0m"
echo -e "Model: \033[1;37m${MODEL}\033[0m"
echo -e "Version: \033[1;37m${PRODUCTVER}\033[0m"
echo -e "LKM: \033[1;37m${LKM}\033[0m"
echo -e "Macsys: \033[1;37m${MACSYS}\033[0m"
echo
echo -e "\033[1;37mSystem:\033[0m"
echo -e "VENDOR: \033[1;37m${VENDOR}\033[0m"
echo -e "CPU: \033[1;37m${CPU}\033[0m"
echo -e "MEM: \033[1;37m${RAM}\033[0m"
echo

if [[ ! -f "${MODEL_CONFIG_PATH}/${MODEL}.yml" || -z "$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}]")" ]]; then
  echo -e "\033[1;33m*** The current version of Arc does not support booting ${MODEL}-${PRODUCTVER}, please rebuild. ***\033[0m"
  exit 1
fi

if ! readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem; then
  HASATA=0
  for D in $(lsblk -dpno NAME); do
    [ "${D}" = "${LOADER_DISK}" ] && continue
    if [ "$(getBus "${D}")" = "sata" -o "$(getBus "${D}")" = "scsi" ]; then
      HASATA=1
      break
    fi
  done
  [ ${HASATA} = "0" ] && echo -e "\033[1;31m*** Please insert at least one Sata/SAS/SCSI Disk for System installation, except for the Bootloader Disk. ***\033[0m"
fi

# Read necessary variables
VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "arc.kernelpanic" "${USER_CONFIG_FILE}")"
DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
EMMCBOOT="$(readConfigKey "arc.emmcboot" "${USER_CONFIG_FILE}")"
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true

declare -A CMDLINE

# Read and Set Cmdline
MODELID="$(readModelKey ${MODEL} "id")"
CMDLINE['syno_hw_version']="${MODELID:-${MODEL}}"
[ -z "${VID}" ] && VID="0x46f4" # Sanity check
[ -z "${PID}" ] && PID="0x0001" # Sanity check
CMDLINE['vid']="${VID}"
CMDLINE['pid']="${PID}"
CMDLINE['sn']="${SN}"

NIC=0
for ETH in ${ETHX}; do
  MAC="$(readConfigKey "mac.${ETH}" "${USER_CONFIG_FILE}")"
  [ -n "${MAC}" ] && NIC=$((${NIC} + 1)) && CMDLINE["mac${NIC}"]="${MAC}"
done
CMDLINE['netif_num']="${NIC}"

if [ "${MACSYS}" = "hardware" ]; then
  CMDLINE['skip_vender_mac_interfaces']="0,1,2,3,4,5,6,7"
elif [ "${MACSYS}" = "custom" ]; then
  CMDLINE['skip_vender_mac_interfaces']="$(seq -s, ${NIC} 7)"
fi

# set fixed cmdline
if grep -q "force_junior" /proc/cmdline; then
  CMDLINE['force_junior']=""
fi
if grep -q "recovery" /proc/cmdline; then
  CMDLINE['force_junior']=""
  CMDLINE['recovery']=""
fi
if [ ${EFI} -eq 1 ]; then
  CMDLINE['withefi']=""
else
  CMDLINE['noefi']=""
fi
if [ ! "${BUS}" = "usb" ]; then
  SZ=$(blockdev --getsz ${LOADER_DISK} 2>/dev/null)  # SZ=$(cat /sys/block/${LOADER_DISK/\/dev\//}/size)
  SS=$(blockdev --getss ${LOADER_DISK} 2>/dev/null)  # SS=$(cat /sys/block/${LOADER_DISK/\/dev\//}/queue/hw_sector_size)
  SIZE=$((${SZ} * ${SS} / 1024 / 1024 + 10))
  # Read SATADoM type
  DOM="$(readModelKey "${MODEL}" "dom")"
  CMDLINE['synoboot_satadom']="${DOM}"
  CMDLINE['dom_szmax']="${SIZE}"
fi
CMDLINE['panic']="${KERNELPANIC:-0}"
CMDLINE['console']="ttyS0,115200n8"
#CMDLINE['no_console_suspend']="1"
CMDLINE['consoleblank']="600"
CMDLINE['earlyprintk']=""
CMDLINE['earlycon']="uart8250,io,0x3f8,115200n8"
CMDLINE['root']="/dev/md0"

[ ! "${MODEL}" = "SA6400" ] && CMDLINE['elevator']="elevator"
CMDLINE['loglevel']="15"
CMDLINE['log_buf_len']="32M"

if [ -n "$(ls /dev/mmcblk* 2>/dev/null)" ] && [ ! "${BUS}" = "mmc" ] && [ ! "${EMMCBOOT}" = "true" ]; then
  [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE['modprobe.blacklist']+=","
  CMDLINE['modprobe.blacklist']+="sdhci,sdhci_pci,sdhci_acpi"
fi

if [ "$(readModelKey "${MODEL}" "dt")" = "true" ] && ! echo "epyc7002 purley broadwellnkv2" | grep -wq "$(readModelKey "${MODEL}" "platform")"; then
  [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE['modprobe.blacklist']+=","
  CMDLINE['modprobe.blacklist']+="mpt3sas"
fi

# Read cmdline
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done <<<$(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

# Prepare command line
CMDLINE_LINE=""
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
CMDLINE_LINE=$(echo "${CMDLINE_LINE}" | sed 's/^ //') # Remove leading space

# Boot
if [ "${DIRECTBOOT}" = "true" ]; then
  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
  grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
  echo -e "\033[1;34mReboot with Directboot\033[0m"
  exec reboot
elif [ "${DIRECTBOOT}" = "false" ]; then
  BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
  echo -e "\033[1;34mDetected ${NIC} NIC.\033[0m \033[1;37mWaiting for Connection:\033[0m"
  for ETH in ${ETHX}; do
    IP=""
    DRIVER="$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')"
    COUNT=0
    while true; do
      IP="$(getIP ${ETH})"
      MSG="DHCP"
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${ETH} 2>/dev/null | grep "Speed:" | awk '{print $2}')
        echo -e "\r\033[1;37m${DRIVER} (${SPEED} | ${MSG}):\033[0m Access \033[1;34mhttp://${IP}:5000\033[0m to connect to DSM via web."
        ethtool -s ${ETH} wol g 2>/dev/null
        [ ! -n "${IPCON}" ] && IPCON="${IP}"
        break
      fi
      if [ ${COUNT} -gt ${BOOTIPWAIT} ]; then
        echo -e "\r\033[1;37m${DRIVER}:\033[0m TIMEOUT"
        break
      fi
      sleep 3
      if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
        echo -e "\r\033[1;37m${DRIVER}:\033[0m NOT CONNECTED"
        break
      fi
      COUNT=$((${COUNT} + 3))
    done
  done
  # Exec Bootwait to check SSH/Web connection
  BOOTWAIT=1
  w | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while test ${BOOTWAIT} -ge 0; do
    MSG="\033[1;33mAccess SSH/Web will interrupt boot...\033[0m"
    echo -en "\r${MSG}"
    w | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      echo -en "\r\033[1;33mAccess SSH/Web detected and boot is interrupted.\033[0m\n"
      rm -f WB WC
      exit 0
    fi
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
  done
  rm -f WB WC
  echo -en "\r$(printf "%$((${#MSG} * 2))s" " ")\n"
  echo -e "\033[1;37mLoading DSM kernel...\033[0m"

  # Executes DSM kernel via KEXEC
  kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  echo -e "\033[1;37m"Booting DSM..."\033[0m"
  for T in $(w | grep -v "TTY" | awk -F' ' '{print $2}')
  do
    echo -e "\n\033[1;37mThis interface will not be operational. Wait a few minutes.\033[0m\nUse \033[1;34mhttp://${IPCON}:5000\033[0m or try \033[1;34mhttp://find.synology.com/ \033[0mto find DSM and proceed.\n" >"/dev/${T}" 2>/dev/null || true
  done

  # Clear logs for dbgutils addons
  rm -rf "${PART1_PATH}/logs" >/dev/null 2>&1 || true

  [ "${KERNELLOAD}" = "kexec" ] && kexec -i -a -e || poweroff
  exit 0
fi