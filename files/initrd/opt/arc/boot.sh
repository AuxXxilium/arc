#!/usr/bin/env bash
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

LOCKFILE="/tmp/.bootlock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Boot is in progress. Exiting."; exit 0; }

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"

arc_mode || die "Bootmode not found!"

# Clear logs for dbgutils addons
rm -rf "${PART1_PATH}/logs" >/dev/null 2>&1 || true

# Get Loader Disk Bus
[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"
BUS=$(getBus "${LOADER_DISK}")
EFI=$([ -d /sys/firmware/efi ] && echo 1 || echo 0)

# Print Title centralized
clear
COLUMNS=$(ttysize 2>/dev/null | awk '{print $1}')
COLUMNS=${COLUMNS:-120}
BANNER="$(figlet -c -w "${COLUMNS}" "Arc Loader")"
TITLE="Version:"
TITLE+=" ${ARC_VERSION} (${ARC_BUILD} @ ${ARC_BASE})"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" ${COLUMNS} "${BANNER}"
printf "\033[1;37m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
TITLE="Boot:"
[ "${EFI}" -eq 1 ] && TITLE+=" UEFI" || TITLE+=" BIOS"
TITLE+=" | Device: ${BUS} | Mode: ${ARC_MODE}"
printf "\033[1;37m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check if DSM zImage/Ramdisk is changed, patch it if necessary, update Files if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
ZIMAGE_HASH_CUR="$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')"
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
if [ "${ZIMAGE_HASH_CUR}" != "${ZIMAGE_HASH}" ] || [ "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]; then
  echo
  livepatch
fi
echo

# Read model/system variables
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
CPU="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed -E 's/@ [0-9.]+[[:space:]]*GHz//g' | sed -E 's/ CPU//g' | sed -E 's/^[[:space:]]*//')"
CPUCNT="$(cat /sys/devices/system/cpu/cpu[0-9]*/topology/{core_cpus_list,thread_siblings_list} | sort -u | wc -l 2>/dev/null)"
CPUCHT="$(cat /proc/cpuinfo | grep -c 'core id' 2>/dev/null)"
RAMTOTAL="$(awk '/MemTotal:/ {printf "%.0f\n", $2 / 1024 / 1024 + 0.5}' /proc/meminfo 2>/dev/null)"
BOARD="$(getBoardName)"
MEV="$(virt-what 2>/dev/null | head -1)"
GOVERNOR="$(readConfigKey "governor" "${USER_CONFIG_FILE}")"
USBMOUNT="$(readConfigKey "usbmount" "${USER_CONFIG_FILE}")"
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"

# Build Sanity Check
if [ "${BUILDDONE}" = "false" ]; then
  echo "Build not completed!"
  echo "Please run the loader build script again!"
  echo "Rebooting to config mode in 10 seconds..."
  sleep 10
  rebootTo "config"
  exit 0
fi

# Show Loader Info
DSMINFO="$(readConfigKey "bootscreen.dsminfo" "${USER_CONFIG_FILE}")"
SYSTEMINFO="$(readConfigKey "bootscreen.systeminfo" "${USER_CONFIG_FILE}")"
DISKINFO="$(readConfigKey "bootscreen.diskinfo" "${USER_CONFIG_FILE}")"
HWIDINFO="$(readConfigKey "bootscreen.hwidinfo" "${USER_CONFIG_FILE}")"
if [ -f "${PART1_PATH}/GRUB_VER" ]; then
  SYS_MODEL="$(_get_conf_kv "${PART1_PATH}/GRUB_VER" "MODEL")"
fi
if [ "${DSMINFO}" = "true" ]; then
  echo -e "\033[1;34mDSM\033[0m"
  echo -e "Model: \033[1;37m${MODEL} (${SYS_MODEL})\033[0m"
  echo -e "Platform: \033[1;37m${PLATFORM}\033[0m"
  echo -e "Version: \033[1;37m${PRODUCTVER} (${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))\033[0m"
  echo -e "Kernel: \033[1;37m${KERNEL} (${KVER})\033[0m"
  echo
fi
if [ "${SYSTEMINFO}" = "true" ]; then
  echo -e "\033[1;34mSystem\033[0m"
  echo -e "CPU: \033[1;37m${CPU} (Cores: ${CPUCNT} | Threads: ${CPUCHT})\033[0m"
  echo -e "Board: \033[1;37m${BOARD}\033[0m"
  echo -e "Memory: \033[1;37m${RAMTOTAL}GB\033[0m"
  echo -e "Governor: \033[1;37m${GOVERNOR:-performance}\033[0m"
  echo -e "Type: \033[1;37m${MEV:-physical}\033[0m"
  [ "${USBMOUNT}" = "true" ] && echo -e "USB Mount: \033[1;37m${USBMOUNT}\033[0m"
  echo -e "Boottime: \033[1;37m$(date +"%Y-%m-%d %H:%M:%S")\033[0m"
  echo
fi
if [ "${DISKINFO}" = "true" ]; then
  echo -e "\033[1;34mDisks\033[0m"
  echo -e "Disks: \033[1;37m$(lsblk -dpno NAME | grep -v "${LOADER_DISK}" | wc -l)\033[0m"
  echo
fi
if [ "${HWIDINFO}" = "true" ]; then
  echo -e "\033[1;34mHardwareID\033[0m"
  echo -e "HWID: \033[1;37m$(genHWID)\033[0m"
  echo
fi

if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem; then
  [ -z "$(ls /dev/nvme* | grep -vE "${LOADER_DISK}[0-9]?$" 2>/dev/null)" ] && printf "\033[1;33m*** %s ***\033[0m\n" "Notice: Please insert at least one m.2 disk for system installation."
else
  if [ -z "$(ls /dev/sd* /dev/sg* 2>/dev/null | grep -vE "${LOADER_DISK}[0-9]?$")" ]; then
    printf "\033[1;33m*** %s ***\033[0m\n" "Notice: Please insert at least one SATA, SAS, or SCSI disk for system installation."
  fi
fi

if checkBIOS_VT_d && [ "${KVER:0:1}" -lt 5 ]; then
  echo -e "\033[1;31m*** Notice: Disable Intel(VT-d)/AMD(AMD-V) in BIOS/UEFI settings if you encounter a boot issues. ***\033[0m"
  echo
fi

# Read boot variables
VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"
DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${P_FILE}")"
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"

declare -A CMDLINE

# Automated Cmdline
CMDLINE['vid']="${VID:-"0x46f4"}"
CMDLINE['pid']="${PID:-"0x0001"}"
CMDLINE['syno_hw_version']="${MODEL}"
CMDLINE['sn']="${SN}"

# NIC Cmdline
ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
ETHNA="$(wc -w <<< "${ETHX}")"
ETHN=0
for N in ${ETHX}; do
  MAC="$(readConfigKey "${N}" "${USER_CONFIG_FILE}")"
  [ -z "${MAC}" ] && MAC="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
  CMDLINE["mac$((++ETHN))"]="${MAC}"
done
CMDLINE['netif_num']="${ETHN}"
[ "${ETHN}" -ne "${ETHNA}" ] && echo "Warning: Network interface count mismatch!" || true

NETFIX="$(readConfigKey "arc.netfix" "${USER_CONFIG_FILE}")"
if [ "${NETFIX}" = "true" ]; then
  for N in ${ETHX}; do
    RMAC="$(cat "/sys/class/net/${N}/address" 2>/dev/null || echo "00:00:00:00:00:00")"
    RBUS="$(ethtool -i "${N}" 2>/dev/null | grep "bus-info" | cut -d' ' -f2 || echo "0000:00:00.0")"
    if [ "${RMAC}" != "00:00:00:00:00:00" ] && [ "${RBUS}" != "0000:00:00.0" ]; then
      CMDLINE["R${RBUS}"]="${RMAC}"
    fi
  done
fi

# Boot Cmdline
if [ "${ARC_MODE}" = "reinstall" ]; then
  CMDLINE['force_junior']=""
elif [ "${ARC_MODE}" = "recovery" ]; then
  CMDLINE['recovery']=""
  CMDLINE['force_junior']=""
fi

if [ "${EFI}" -eq 1 ]; then
  CMDLINE['withefi']=""
else
  CMDLINE['noefi']=""
fi

# DSM Cmdline
if [ -z "${KVER}" ]; then
  echo "Error: DSM ${PRODUCTVER} on ${PLATFORM} is not supported."
  exit 1
fi
if [ "${KVER:0:1}" -lt 5 ]; then
  if [ "${BUS}" != "usb" ]; then
    SZ=$(blockdev --getsz "${LOADER_DISK}" 2>/dev/null) # SZ=$(cat /sys/block/${LOADER_DISK/\/dev\//}/size)
    SS=$(blockdev --getss "${LOADER_DISK}" 2>/dev/null) # SS=$(cat /sys/block/${LOADER_DISK/\/dev\//}/queue/hw_sector_size)
    SIZE=$((${SZ:-0} * ${SS:-0} / 1024 / 1024 + 10))
    # Read SATADoM type
    SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
    CMDLINE['synoboot_satadom']="${SATADOM:-2}"
    CMDLINE['dom_szmax']="${SIZE}"
  fi
  CMDLINE['elevator']="elevator"
else
  CMDLINE['split_lock_detect']="off"
fi

if [ "${DT}" = "true" ]; then
  CMDLINE['syno_ttyS0']="serial,0x3f8"
  CMDLINE['syno_ttyS1']="serial,0x2f8"
else
  CMDLINE['SMBusHddDynamicPower']="1"
  CMDLINE['syno_hdd_detect']="0"
  CMDLINE['syno_hdd_powerup_seq']="0"
fi

CMDLINE['HddHotplug']="1"
CMDLINE['vender_format_version']="2"
CMDLINE['skip_vender_mac_interfaces']="0,1,2,3,4,5,6,7"
CMDLINE['earlyprintk']=""
CMDLINE['earlycon']="uart8250,io,0x3f8,115200n8"
CMDLINE['console']="ttyS0,115200n8"
CONSOLEBLANK="$(readConfigKey "arc.consoleblank" "${USER_CONFIG_FILE}")"
CMDLINE['consoleblank']="${CONSOLEBLANK:-600}"
CMDLINE['root']="/dev/md0"
CMDLINE['loglevel']="15"
CMDLINE['log_buf_len']="32M"
CMDLINE['rootwait']=""
CMDLINE['panic']="${KERNELPANIC:-0}"
CMDLINE['pcie_aspm']="off"
CMDLINE['nowatchdog']=""
# CMDLINE['intel_pstate']="disable"
# CMDLINE['amd_pstate']="disable"
MODBLACKLIST="$(readConfigKey "modblacklist" "${USER_CONFIG_FILE}")"
CMDLINE['modprobe.blacklist']="${MODBLACKLIST}"
CMDLINE['mev']="${MEV:-physical}"
CMDLINE['governor']="${GOVERNOR:-performance}"

if [ "${MEV}" = "vmware" ]; then
  CMDLINE['tsc']="reliable"
  CMDLINE['pmtmr']="0x0"
fi

HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
if [ "${HDDSORT}" = "true" ]; then
  CMDLINE['hddsort']=""
fi

USBMOUNT="$(readConfigKey "usbmount" "${USER_CONFIG_FILE}")"
if [ "${USBMOUNT}" = "true" ]; then
  CMDLINE['usbinternal']=""
fi

if is_in_array "${PLATFORM}" "${XAPICRL[@]}"; then
  CMDLINE['nox2apic']=""
fi

if is_in_array "${PLATFORM}" "${IGFXRL[@]}"; then
  CMDLINE['intel_iommu']="igfx_off"
fi

if [ "${PLATFORM}" = "purley" ] || [ "${PLATFORM}" = "broadwellnkv2" ]; then
  CMDLINE['SASmodel']="1"
fi

if [ "${DT}" = "true" ] && ! is_in_array "${PLATFORM}" "${MPT3PL[@]}"; then
  if ! echo "${CMDLINE['modprobe.blacklist']}" | grep -q "mpt3sas"; then
    [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE['modprobe.blacklist']+=","
    CMDLINE['modprobe.blacklist']+="mpt3sas"
  fi
fi

# Read user network settings
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["network.${KEY}"]="${VALUE}"
done <<<"$(readConfigMap "network" "${USER_CONFIG_FILE}")"

# Read user cmdline
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done <<<"$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")"

# Prepare command line
CMDLINE_LINE=""
for KEY in "${!CMDLINE[@]}"; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
CMDLINE_LINE="$(echo "${CMDLINE_LINE}" | sed 's/^ //')"
echo "${CMDLINE_LINE}" >"${PART1_PATH}/cmdline.yml"

# Boot
DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
if [ "${DIRECTBOOT}" = "true" ] || echo "parallels xen" | grep -qw "${MEV:-physical}"; then
  grub-editenv "${USER_RSYSENVFILE}" create 2>/dev/null || true
  grub-editenv "${USER_RSYSENVFILE}" set arc_version="${ARC_VERSION} (${ARC_BUILD})"
  grub-editenv "${USER_RSYSENVFILE}" set dsm_model="${MODEL} (${PLATFORM})"
  grub-editenv "${USER_RSYSENVFILE}" set dsm_version="${PRODUCTVER} (${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))"
  grub-editenv "${USER_RSYSENVFILE}" set dsm_kernel="${KERNEL} (${KVER})"
  grub-editenv "${USER_RSYSENVFILE}" set sys_mev="${MEV:-physical}"
  grub-editenv "${USER_RSYSENVFILE}" set sys_cpu="${CPU} (Cores: ${CPUCNT} | Threads: ${CPUCHT})"
  grub-editenv "${USER_RSYSENVFILE}" set sys_board="${BOARD}"
  grub-editenv "${USER_RSYSENVFILE}" set sys_mem="${RAMTOTAL} GiB"

  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${USER_GRUBENVFILE} set dsm_cmdline="${CMDLINE_DIRECT}"
  grub-editenv ${USER_GRUBENVFILE} set next_entry="direct"

  sleep 2

  echo -e "\033[1;34mReboot with Directboot\033[0m"
  exec reboot
  exit 0
else
  grub-editenv ${USER_GRUBENVFILE} unset dsm_cmdline 2>/dev/null || true
  grub-editenv ${USER_GRUBENVFILE} unset next_entry 2>/dev/null || true

  BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=20
  echo -e "\033[1;34mNetwork (${ETHN} NIC)\033[0m"
  [ ! -f /var/run/dhcpcd/pid ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 || true
  IPCON=""
  checkNIC || true
  echo

  # Executes DSM kernel via KEXEC
  kexec -a -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE} kexecboot" >"${LOG_FILE}" 2>&1 || die "Failed to load DSM Kernel!"

  for T in $(busybox w 2>/dev/null | grep -v 'TTY' | awk '{print $2}'); do
    if [ -w "/dev/${T}" ]; then
      [ -n "${IPCON}" ] && echo -e "Use \033[1;34mhttp://${IPCON}:5000\033[0m or try \033[1;34mhttp://find.synology.com/ \033[0mto find DSM and proceed.\n\n\033[1;37mThis interface will not be operational. Network will be unreachable until DSM boot.\033[0m\n" >"/dev/${T}" 2>/dev/null \
      || echo -e "Try \033[1;34mhttp://find.synology.com/ \033[0mto find DSM and proceed.\n\n\033[1;37mThis interface will not be operational. Network will be unreachable until DSM boot.\nNo IP found - DSM will not work properly!\033[0m\n" >"/dev/${T}" 2>/dev/null
    fi
  done

  echo -e "\033[1;37mLoading DSM Kernel...\033[0m"

  sleep 2

  KERNELLOAD="$(readConfigKey "kernelload" "${USER_CONFIG_FILE}")"
  [ -z "${KERNELLOAD}" ] && KERNELLOAD="kexec"
  echo -e "\033[1;37mBooting DSM...\033[0m"
  [ "${KERNELLOAD}" = "kexec" ] && kexec -e || poweroff
  exit 0
fi
