#!/usr/bin/env bash

set -e
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

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
[ ${EFI} -eq 1 ] && TITLE+=" [UEFI]" || TITLE+=" [BIOS]"
TITLE+=" [${BUS}]"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check if DSM zImage/Ramdisk is changed, patch it if necessary, update Files if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
ZIMAGE_HASH_CUR="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')"
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
OFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
if [ "${ZIMAGE_HASH_CUR}" != "${ZIMAGE_HASH}" ] || [ "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;31mDSM zImage/Ramdisk changed!\033[0m"
  livepatch
  echo
fi

# Read model/system variables
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
CPU="$(echo $(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}'))"
RAMTOTAL=$(awk '/MemTotal:/ {printf "%.0f", $2 / 1024 / 1024}' /proc/meminfo 2>/dev/null)
VENDOR=$(dmesg 2>/dev/null | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')

echo -e "\033[1;37mDSM:\033[0m"
echo -e "Model: \033[1;37m${MODELID:-${MODEL}}\033[0m"
echo -e "Version: \033[1;37m${PRODUCTVER}\033[0m"
echo -e "LKM: \033[1;37m${LKM}\033[0m"
echo
echo -e "\033[1;37mSystem:\033[0m"
echo -e "Vendor: \033[1;37m${VENDOR}\033[0m"
echo -e "CPU: \033[1;37m${CPU}\033[0m"
echo -e "Memory: \033[1;37m${RAMTOTAL} GB (usable)\033[0m"
echo

if ! readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem; then
  HASATA=0
  for D in $(lsblk -dpno NAME); do
    [ "${D}" == "${LOADER_DISK}" ] && continue
    if [ "$(getBus "${D}")" == "sata" ] || [ "$(getBus "${D}")" == "scsi" ]; then
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
KERNELPANIC="$(readConfigKey "arc.kernelpanic" "${USER_CONFIG_FILE}")"
DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.[${PRODUCTVER}].kver" "${P_FILE}")"

declare -A CMDLINE

# Automated Cmdline
CMDLINE['syno_hw_version']="${MODELID:-${MODEL}}"
CMDLINE['vid']="${VID:-"0x46f4"}" # Sanity check
CMDLINE['pid']="${PID:-"0x0001"}" # Sanity check
CMDLINE['sn']="${SN}"

# Boot Cmdline
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

# DSM Cmdline
if [ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 5 ]; then
  if [ "${BUS}" != "usb" ]; then
    SZ=$(blockdev --getsz ${LOADER_DISK} 2>/dev/null) # SZ=$(cat /sys/block/${LOADER_DISK/\/dev\//}/size)
    SS=$(blockdev --getss ${LOADER_DISK} 2>/dev/null) # SS=$(cat /sys/block/${LOADER_DISK/\/dev\//}/queue/hw_sector_size)
    SIZE=$((${SZ:-0} * ${SS:-0} / 1024 / 1024 + 10))
    # Read SATADoM type
    SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
    CMDLINE['synoboot_satadom']="${SATADOM:-2}"
    CMDLINE['dom_szmax']="${SIZE}"
  fi
  CMDLINE["elevator"]="elevator"
fi
if [ "${DT}" == "true" ]; then
  CMDLINE["syno_ttyS0"]="serial,0x3f8"
  CMDLINE["syno_ttyS1"]="serial,0x2f8"
else
  CMDLINE["SMBusHddDynamicPower"]="1"
  CMDLINE["syno_hdd_detect"]="0"
  CMDLINE["syno_hdd_powerup_seq"]="0"
fi
CMDLINE['panic']="${KERNELPANIC:-0}"
CMDLINE['console']="ttyS0,115200n8"
# CMDLINE['no_console_suspend']="1"
CMDLINE['consoleblank']="600"
CMDLINE['earlyprintk']=""
CMDLINE['earlycon']="uart8250,io,0x3f8,115200n8"
CMDLINE['root']="/dev/md0"
CMDLINE['skip_vender_mac_interfaces']="0,1,2,3,4,5,6,7"
CMDLINE['loglevel']="15"
CMDLINE['log_buf_len']="32M"
CMDLINE["HddHotplug"]="1"
CMDLINE["vender_format_version"]="2"

#if [ -n "$(ls /dev/mmcblk* 2>/dev/null)" ] && [ "${BUS}" != "mmc" ] && [ "${EMMCBOOT}" != "true" ]; then
#  [ "${CMDLINE['modprobe.blacklist']}" != "" ] && CMDLINE['modprobe.blacklist']+=","
#  CMDLINE['modprobe.blacklist']+="sdhci,sdhci_pci,sdhci_acpi"
#fi
if [ "${DT}" == "true" ] && ! echo "epyc7002 purley broadwellnkv2" | grep -wq "${PLATFORM}"; then
  [ "${CMDLINE['modprobe.blacklist']}" != "" ] && CMDLINE['modprobe.blacklist']+=","
  CMDLINE['modprobe.blacklist']+="mpt3sas"
fi
if echo "apollolake geminilake" | grep -wq "${PLATFORM}"; then
  CMDLINE["intel_iommu"]="igfx_off"
fi
if echo "purley broadwellnkv2" | grep -wq "${PLATFORM}"; then
  CMDLINE["SASmodel"]="1"
fi

# Cmdline NIC Settings
MAC1="$(readConfigKey "mac.eth0" "${USER_CONFIG_FILE}")"
MAC2="$(readConfigKey "mac.eth1" "${USER_CONFIG_FILE}")"
CMDLINE['netif_num']="0"
[[ -z "${MAC1}" && -n "${MAC2}" ]] && MAC1=${MAC2} && MAC2="" # Sanity check
[ -n "${MAC1}" ] && CMDLINE['mac1']="${MAC1}" && CMDLINE['netif_num']="1"
[ -n "${MAC2}" ] && CMDLINE['mac2']="${MAC2}" && CMDLINE['netif_num']="2"

# Read user network settings
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["network.${KEY}"]="${VALUE}"
done < <(readConfigMap "network" "${USER_CONFIG_FILE}")

# Read user cmdline
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

# Prepare command line
CMDLINE_LINE=""
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
CMDLINE_LINE=$(echo "${CMDLINE_LINE}" | sed 's/^ //') # Remove leading space

# Boot
DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
if [ "${DIRECTBOOT}" == "true" ]; then
  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${USER_GRUBENVFILE} set dsm_cmdline="${CMDLINE_DIRECT}"
  echo -e "\033[1;34mReboot with Directboot\033[0m"
  grub-editenv ${USER_GRUBENVFILE} set next_entry="direct"
  reboot
  exit 0
elif [ "${DIRECTBOOT}" == "false" ]; then
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth)
  ETHN=$(ls /sys/class/net/ 2>/dev/null | grep eth | wc -l)
  BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=20
  echo -e "\033[1;34mDetected ${ETHN} NIC.\033[0m \033[1;37mWaiting for Connection:\033[0m"
  for ETH in ${ETHX}; do
    COUNT=0
    DRIVER=$(ls -ld /sys/class/net/${ETH}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    while true; do
      if ! ip link show ${ETH} 2>/dev/null | grep -q 'UP'; then
        echo -e "\r\033[1;37m${DRIVER}:\033[0m DOWN"
        break
      fi
      if ethtool ${ETH} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
        echo -e "\r\033[1;37m${DRIVER}:\033[0m NOT CONNECTED"
        break
      fi
      if [ ${COUNT} -ge ${BOOTIPWAIT} ]; then
        echo -e "\r\033[1;37m${DRIVER}:\033[0m TIMEOUT"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP ${ETH})"
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${ETH} 2>/dev/null | grep "Speed:" | awk '{print $2}')
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          echo -e "\r\033[1;37m${DRIVER} (${SPEED}):\033[0m LINK LOCAL (No DHCP server found.)"
        else
          echo -e "\r\033[1;37m${DRIVER} (${SPEED}):\033[0m Access \033[1;34mhttp://${IP}:5000\033[0m to connect to DSM via web."
          [ -z "${IPCON}" ] && IPCON="${IP}"
        fi
        break
      fi
      sleep 1
    done
  done
  # Exec Bootwait to check SSH/Web connection
  BOOTWAIT=5
  busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while test ${BOOTWAIT} -ge 0; do
    MSG="\033[1;33mAccess SSH/Web will interrupt boot...\033[0m"
    echo -en "\r${MSG}"
    busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
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

  DSMLOGO="$(readConfigKey "arc.dsmlogo" "${USER_CONFIG_FILE}")"
  if [ "${DSMLOGO}" == "true" ] && [ -c "/dev/fb0" ]; then
    [[ "${IPCON}" =~ ^169\.254\..* ]] && IPCON=""
    if [ -n "${IPCON}" ]; then
      URL="http://${IPCON}:5000"
      python ${ARC_PATH}/include/functions.py makeqr -d "${URL}" -l "6" -o "${TMP_PATH}/qrcode_boot.png"
      [ -f "${TMP_PATH}/qrcode_boot.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_boot.png" >/dev/null 2>/dev/null || true
    else
      URL="http://find.synology.com/"
      python ${ARC_PATH}/include/functions.py makeqr -d "${URL}" -l "6" -o "${TMP_PATH}/qrcode_boot.png"
      [ -f "${TMP_PATH}/qrcode_syno.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_syno.png" >/dev/null 2>/dev/null || true
    fi
  fi

  # Executes DSM kernel via KEXEC
  KEXECARGS=""
  if [ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 4 ] && [ ${EFI} -eq 1 ]; then
    echo -e "\033[1;33mWarning, running kexec with --noefi param, strange things will happen!!\033[0m"
    KEXECARGS="--noefi"
  fi
  kexec ${KEXECARGS} -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  echo -e "\033[1;37mBooting DSM...\033[0m"
  for T in $(busybox w 2>/dev/null | grep -v 'TTY' | awk '{print $2}'); do
    [ -w "/dev/${T}" ] && echo -e "\n\033[1;37mThis interface will not be operational. Wait a few minutes.\033[0m\nUse \033[1;34mhttp://${IPCON}:5000\033[0m or try \033[1;34mhttp://find.synology.com/ \033[0mto find DSM and proceed.\n" >"/dev/${T}" 2>/dev/null || true
  done

  # Clear logs for dbgutils addons
  rm -rf "${PART1_PATH}/logs" >/dev/null 2>&1 || true

  KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
  [ "${KERNELLOAD}" == "kexec" ] && kexec -a -e || poweroff
  exit 0
fi