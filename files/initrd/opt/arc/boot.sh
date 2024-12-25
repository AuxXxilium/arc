#!/usr/bin/env bash

set -e
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"

# Clear logs for dbgutils addons
rm -rf "${PART1_PATH}/logs" >/dev/null 2>&1 || true

BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
[ "${BUILDDONE}" = "false" ] && die "Loader build not completed!"
ARC_BRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"

# Get Loader Disk Bus
[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"
BUS=$(getBus "${LOADER_DISK}")
FBI=$(cat /sys/class/graphics/fb*/name 2>/dev/null | head -1)
EFI=$([ -d /sys/firmware/efi ] && echo 1 || echo 0)

# Print Title centralized
clear
COLUMNS=${COLUMNS:-50}
BANNER="$(figlet -c -w "$(((${COLUMNS})))" "Arc Loader")"
TITLE="Version:"
TITLE+=" ${ARC_VERSION} (${ARC_BUILD})"
[ -n "${ARC_BRANCH}" ] && TITLE+=" | Branch: ${ARC_BRANCH}"
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
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
CPU="$(echo $(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}'))"
RAMTOTAL="$(awk '/MemTotal:/ {printf "%.0f\n", $2 / 1024 / 1024 + 0.5}' /proc/meminfo 2>/dev/null)"
VENDOR="$(dmesg 2>/dev/null | grep -i "DMI:" | head -1 | sed 's/\[.*\] DMI: //i')"
DSMINFO="$(readConfigKey "bootscreen.dsminfo" "${USER_CONFIG_FILE}")"
SYSTEMINFO="$(readConfigKey "bootscreen.systeminfo" "${USER_CONFIG_FILE}")"
DISKINFO="$(readConfigKey "bootscreen.diskinfo" "${USER_CONFIG_FILE}")"
HWIDINFO="$(readConfigKey "bootscreen.hwidinfo" "${USER_CONFIG_FILE}")"

if [ "${DSMINFO}" = "true" ]; then
  echo -e "\033[1;37mDSM:\033[0m"
  echo -e "Model: \033[1;37m${MODELID:-${MODEL}}\033[0m"
  echo -e "Platform: \033[1;37m${PLATFORM}\033[0m"
  echo -e "Version: \033[1;37m${PRODUCTVER} (${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))\033[0m"
  echo -e "LKM: \033[1;37m${LKM}\033[0m"
  echo
fi
if [ "${SYSTEMINFO}" = "true" ]; then
  echo -e "\033[1;37mSystem:\033[0m"
  echo -e "Vendor: \033[1;37m${VENDOR}\033[0m"
  echo -e "CPU: \033[1;37m${CPU}\033[0m"
  echo -e "Memory: \033[1;37m${RAMTOTAL}GB\033[0m"
  echo
fi
if [ "${DISKINFO}" = "true" ]; then
  echo -e "\033[1;37mDisks:\033[0m"
  echo -e "Disks: \033[1;37m$(lsblk -dpno NAME | grep -v "${LOADER_DISK}" | wc -l)\033[0m"
fi
if [ "${HWIDINFO}" = "true" ]; then
  echo -e "\033[1;37mHardwareID:\033[0m"
  echo -e "HWID: \033[1;37m$(genHWID)\033[0m"
  echo
fi

if ! readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem; then
  HASATA=0
  for D in $(lsblk -dpno NAME); do
    [ "${D}" = "${LOADER_DISK}" ] && continue
    if echo "sata sas scsi" | grep -qw "$(getBus "${D}")"; then
      HASATA=1
      break
    fi
  done
  [ ${HASATA} -eq 0 ] && echo -e "\033[1;31m*** Please insert at least one Sata/SAS/SCSI Disk for System installation, except for the Bootloader Disk. ***\033[0m"
fi

# Read necessary variables
VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"
DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
MODBLACKLIST="$(readConfigKey "modblacklist" "${USER_CONFIG_FILE}")"
ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"

# HardwareID Check
if [ "${ARCPATCH}" = "true" ]; then
  HARDWAREID="$(readConfigKey "arc.hardwareid" "${USER_CONFIG_FILE}")"
  HWID="$(genHWID)"
  if [ "${HARDWAREID}" != "${HWID}" ]; then
    echo "\033[1;31m*** HardwareID does not match! - Loader can't boot to DSM! You need to reconfigure your Loader - Rebooting to Config Mode! ***\033[0m"
    writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
    sleep 5
    rebootTo "config"
  fi
fi

declare -A CMDLINE

# Automated Cmdline
CMDLINE["syno_hw_version"]="${MODELID:-${MODEL}}"
CMDLINE["vid"]="${VID:-"0x46f4"}" # Sanity check
CMDLINE["pid"]="${PID:-"0x0001"}" # Sanity check
CMDLINE["sn"]="${SN}"

# Boot Cmdline
if grep -q "force_junior" /proc/cmdline; then
  CMDLINE["force_junior"]=""
fi
if grep -q "recovery" /proc/cmdline; then
  CMDLINE["force_junior"]=""
  CMDLINE["recovery"]=""
fi
if [ ${EFI} -eq 1 ]; then
  CMDLINE["withefi"]=""
else
  CMDLINE["noefi"]=""
fi

# DSM Cmdline
if [ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 5 ]; then
  if [ "${BUS}" != "usb" ]; then
    SZ=$(blockdev --getsz ${LOADER_DISK} 2>/dev/null) # SZ=$(cat /sys/block/${LOADER_DISK/\/dev\//}/size)
    SS=$(blockdev --getss ${LOADER_DISK} 2>/dev/null) # SS=$(cat /sys/block/${LOADER_DISK/\/dev\//}/queue/hw_sector_size)
    SIZE=$((${SZ:-0} * ${SS:-0} / 1024 / 1024 + 10))
    # Read SATADoM type
    SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
    CMDLINE["synoboot_satadom"]="${SATADOM:-2}"
    CMDLINE["dom_szmax"]="${SIZE}"
  fi
  CMDLINE['elevator']="elevator"
else
  CMDLINE["split_lock_detect"]="off"
fi
if [ "${DT}" = "true" ]; then
  CMDLINE["syno_ttyS0"]="serial,0x3f8"
  CMDLINE["syno_ttyS1"]="serial,0x2f8"
else
  CMDLINE["SMBusHddDynamicPower"]="1"
  CMDLINE["syno_hdd_detect"]="0"
  CMDLINE["syno_hdd_powerup_seq"]="0"
fi
CMDLINE["HddHotplug"]="1"
CMDLINE["vender_format_version"]="2"
CMDLINE["skip_vender_mac_interfaces"]="0,1,2,3,4,5,6,7"
CMDLINE["earlyprintk"]=""
CMDLINE["earlycon"]="uart8250,io,0x3f8,115200n8"
CMDLINE["console"]="ttyS0,115200n8"
CMDLINE["consoleblank"]="600"
# CMDLINE['no_console_suspend']="1"
CMDLINE["root"]="/dev/md0"
CMDLINE["loglevel"]="15"
CMDLINE["log_buf_len"]="32M"
CMDLINE["rootwait"]=""
CMDLINE["panic"]="${KERNELPANIC:-0}"

# DSM Specific Cmdline
CMDLINE["pcie_aspm"]="off"
CMDLINE["modprobe.blacklist"]="${MODBLACKLIST}"
[ $(cat /proc/cpuinfo | grep Intel | wc -l) -gt 0 ] && CMDLINE["intel_pstate"]="disable" || true
# [ $(cat /proc/cpuinfo | grep AMD | wc -l) -gt 0 ] && CMDLINE["amd_pstate"]="disable" || true
# CMDLINE["nomodeset"]=""
if echo "apollolake geminilake purley" | grep -wq "${PLATFORM}"; then
  CMDLINE["nox2apic"]=""
fi
#if [ -n "$(ls /dev/mmcblk* 2>/dev/null)" ] && [ "${BUS}" != "mmc" ] && [ "${EMMCBOOT}" != "true" ]; then
#   if ! echo "${CMDLINE["modprobe.blacklist"]}" | grep -q "sdhci"; then
#     [ ! "${CMDLINE["modprobe.blacklist"]}" = "" ] && CMDLINE["modprobe.blacklist"]+=","
#     CMDLINE["modprobe.blacklist"]+="sdhci,sdhci_pci,sdhci_acpi"
#   fi
# fi
if [ "${DT}" = "true" ] && ! echo "epyc7002 purley broadwellnkv2" | grep -wq "${PLATFORM}"; then
  if ! echo "${CMDLINE['modprobe.blacklist']}" | grep -q "mpt3sas"; then
    [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE["modprobe.blacklist"]+=","
    CMDLINE["modprobe.blacklist"]+="mpt3sas"
  fi
fi
# CMDLINE['kvm.ignore_msrs']="1"
# CMDLINE['kvm.report_ignored_msrs']="0"
if echo "apollolake geminilake" | grep -wq "${PLATFORM}"; then
  CMDLINE["intel_iommu"]="igfx_off"
fi
if echo "purley broadwellnkv2" | grep -wq "${PLATFORM}"; then
  CMDLINE["SASmodel"]="1"
fi

# NIC Cmdline
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) || true
ETHM=$(readConfigKey "${MODEL}.ports" "${S_FILE}" 2>/dev/null)
ETHN=$(echo ${ETHX} | wc -w)
[ -z "${ETHM}" ] && ETHM="${ETHN}"
NIC=0
for N in ${ETHX}; do
  MAC="$(readConfigKey "${N}" "${USER_CONFIG_FILE}")"
  [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/${N}/address 2>/dev/null | tr '[:upper:]' '[:lower:]')" || NIC=$((NIC + 1))
  [ ${NIC} -le ${ETHM} ] && CMDLINE["mac${NIC}"]="${MAC}"
  [ ${NIC} -ge ${ETHM} ] && break
done
CMDLINE["netif_num"]="${NIC}"

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
for KEY in "${!CMDLINE[@]}"; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
CMDLINE_LINE=$(echo "${CMDLINE_LINE}" | sed 's/^ //') # Remove leading space
echo "${CMDLINE_LINE}" >"${PART1_PATH}/cmdline.yml"

# Boot
DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
if [ "${DIRECTBOOT}" = "true" ]; then
  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${USER_GRUBENVFILE} set dsm_cmdline="${CMDLINE_DIRECT}"
  grub-editenv ${USER_GRUBENVFILE} set next_entry="direct"
  if ! _bootwait; then
    exit 0
  fi
  echo -e "\033[1;34mReboot with Directboot\033[0m"
  reboot
  exit 0
elif [ "${DIRECTBOOT}" = "false" ]; then
  grub-editenv ${USER_GRUBENVFILE} unset dsm_cmdline
  grub-editenv ${USER_GRUBENVFILE} unset next_entry
  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=30
  IPCON=""
  if [ "${ARCPATCH}" = "true" ]; then
    echo -e "\033[1;37mDetected ${ETHN} NIC\033[0m | \033[1;34mUsing ${NIC} NIC for Arc Patch:\033[0m"
  else
    echo -e "\033[1;37mDetected ${ETHN} NIC:\033[0m"
  fi
  echo
  [ ! -f /var/run/dhcpcd/pid ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 || true
  sleep 3
  for N in ${ETHX}; do
    COUNT=0
    DRIVER=$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    while true; do
      if [ "0" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
        echo -e "\r${DRIVER}: \033[1;37mNOT CONNECTED\033[0m"
        break
      fi
      COUNT=$((COUNT + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        SPEED=$(ethtool ${N} 2>/dev/null | grep "Speed:" | awk '{print $2}')
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          echo -e "\r${DRIVER} (${SPEED}): \033[1;37mLINK LOCAL (No DHCP server found.)\033[0m"
        else
          echo -e "\r${DRIVER} (${SPEED}): \033[1;37m${IP}\033[0m"
          [ -z "${IPCON}" ] && IPCON="${IP}"
        fi
        break
      fi
      if [ -z "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
        echo -e "\r${DRIVER}: \033[1;37mDOWN\033[0m"
        break
      fi
      if [ ${COUNT} -ge ${BOOTIPWAIT} ]; then
        echo -e "\r${DRIVER}: \033[1;37mTIMEOUT\033[0m"
        break
      fi
      sleep 1
    done
  done
  if ! _bootwait; then
    exit 0
  fi

  DSMLOGO="$(readConfigKey "bootscreen.dsmlogo" "${USER_CONFIG_FILE}")"
  if [ "${DSMLOGO}" = "true" ] && [ -c "/dev/fb0" ]; then
    [[ "${IPCON}" =~ ^169\.254\..* ]] && IPCON=""
    [ -n "${IPCON}" ] && URL="http://${IPCON}:5000" || URL="http://find.synology.com/"
    python3 ${ARC_PATH}/include/functions.py makeqr -d "${URL}" -l "6" -o "${TMP_PATH}/qrcode_boot.png"
    [ -f "${TMP_PATH}/qrcode_boot.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_boot.png" >/dev/null 2>/dev/null || true
  fi

  for T in $(busybox w 2>/dev/null | grep -v 'TTY' | awk '{print $2}'); do
    if [ -w "/dev/${T}" ]; then
      [ -n "${IPCON}" ] && echo -e "Use \033[1;34mhttp://${IPCON}:5000\033[0m or try \033[1;34mhttp://find.synology.com/ \033[0mto find DSM and proceed.\n\n\033[1;37mThis interface will not be operational. Wait a few minutes - Network will be unreachable until DSM boot.\033[0m\n" >"/dev/${T}" 2>/dev/null \
      || echo -e "Try \033[1;34mhttp://find.synology.com/ \033[0mto find DSM and proceed.\n\n\033[1;37mThis interface will not be operational. Wait a few minutes - Network will be unreachable until DSM boot.\nNo IP found - DSM will not work properly!\033[0m\n" >"/dev/${T}" 2>/dev/null
    fi
  done

  # # Unload all network interfaces
  # for D in $(realpath /sys/class/net/*/device/driver); do rmmod -f "$(basename ${D})" 2>/dev/null || true; done

  # Unload all graphics drivers
  # for D in $(lsmod | grep -E '^(nouveau|amdgpu|radeon|i915)' | awk '{print $1}'); do rmmod -f "${D}" 2>/dev/null || true; done
  # for I in $(find /sys/devices -name uevent -exec bash -c 'cat {} 2>/dev/null | grep -Eq "PCI_CLASS=0?30[0|1|2]00" && dirname {}' \;); do
  #   [ -e ${I}/reset ] && cat ${I}/vendor >/dev/null | grep -iq 0x10de && echo 1 >${I}/reset || true # Proc open nvidia driver when booting
  # done

  echo -e "\033[1;37mLoading DSM Kernel...\033[0m"
  KEXECARGS="-a"
  if [ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 4 ] && [ ${EFI} -eq 1 ]; then
    echo -e "\033[1;33mWarning, running kexec with --noefi param, strange things will happen!!\033[0m"
    KEXECARGS+=" --noefi"
  fi
  kexec ${KEXECARGS} -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog

  echo -e "\033[1;37mBooting DSM...\033[0m"
  [ "${KERNELLOAD}" = "kexec" ] && kexec -e || poweroff
  exit 0
fi
