#!/usr/bin/env bash
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"

# VMware time sync
if type vmware-toolbox-cmd >/dev/null 2>&1; then
  if [ "Disable" = "$(vmware-toolbox-cmd timesync status 2>/dev/null)" ]; then
    vmware-toolbox-cmd timesync enable >/dev/null 2>&1 || true
  fi
  if [ "Enabled" = "$(vmware-toolbox-cmd timesync status 2>/dev/null)" ]; then
    vmware-toolbox-cmd timesync disable >/dev/null 2>&1 || true
  fi
fi

# Get Loader Disk Bus
[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"
checkBootLoader || die "The loader is corrupted, please rewrite it!"
arc_mode || die "No bootmode found!"

[ -f "${HOME}/.initialized" ] && arc.sh && exit 0 || true

BUS=$(getBus "${LOADER_DISK}")
EFI=$([ -d /sys/firmware/efi ] && echo 1 || echo 0)

# Print Title centralized
clear
COLUMNS=$(ttysize 2>/dev/null | awk '{print $1}')
COLUMNS=${COLUMNS:-120}
BANNER="$(figlet -c -w "${COLUMNS}" "Arc Loader")"
TITLE="Version:"
TITLE+=" ${ARC_VERSION} (${ARC_BUILD})"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" ${COLUMNS} "${BANNER}"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
TITLE="Boot:"
[ "${EFI}" -eq 1 ] && TITLE+=" UEFI" || TITLE+=" BIOS"
TITLE+=" | Device: ${BUS} | Mode: ${ARC_MODE}"
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check for Config File
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
fi
initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc.backup" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.dev" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.discordnotify" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.hardwareid" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.offline" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.remoteassistance" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.userid" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
initConfigKey "arc.webhooknotify" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.webhookurl" "" "${USER_CONFIG_FILE}"
initConfigKey "bootscreen" "{}" "${USER_CONFIG_FILE}"
initConfigKey "bootscreen.dsminfo" "true" "${USER_CONFIG_FILE}"
initConfigKey "bootscreen.systeminfo" "true" "${USER_CONFIG_FILE}"
initConfigKey "bootscreen.diskinfo" "false" "${USER_CONFIG_FILE}"
initConfigKey "bootscreen.hwidinfo" "false" "${USER_CONFIG_FILE}"
initConfigKey "bootscreen.dsmlogo" "true" "${USER_CONFIG_FILE}"
initConfigKey "bootipwait" "20" "${USER_CONFIG_FILE}"
initConfigKey "device" "{}" "${USER_CONFIG_FILE}"
initConfigKey "directboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "governor" "performance" "${USER_CONFIG_FILE}"
initConfigKey "hddsort" "false" "${USER_CONFIG_FILE}"
initConfigKey "kernel" "official" "${USER_CONFIG_FILE}"
initConfigKey "kernelload" "power" "${USER_CONFIG_FILE}"
initConfigKey "kernelpanic" "5" "${USER_CONFIG_FILE}"
initConfigKey "odp" "false" "${USER_CONFIG_FILE}"
initConfigKey "pathash" "" "${USER_CONFIG_FILE}"
initConfigKey "paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "sn" "" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "" "${USER_CONFIG_FILE}"
initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
initConfigKey "modblacklist" "evbug,cdc_ether" "${USER_CONFIG_FILE}"
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "network" "{}" "${USER_CONFIG_FILE}"
initConfigKey "platform" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
initConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "rd-compressed" "false" "${USER_CONFIG_FILE}"
initConfigKey "satadom" "2" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "time" "{}" "${USER_CONFIG_FILE}"
initConfigKey "usbmount" "false" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"

# Sort network interfaces
if [ ! -f "/.dockerenv" ]; then
  if arrayExistItem "sortnetif:" $(readConfigMap "addons" "${USER_CONFIG_FILE}"); then
    echo -e "NIC sorting: \033[1;34menabled\033[0m"
    _sort_netif "$(readConfigKey "addons.sortnetif" "${USER_CONFIG_FILE}")"
    echo
  fi
fi

# Read/Write IP/Mac to config
ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
for N in ${ETHX}; do
  MACR="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g')"
  IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
  if [ -n "${IPR}" ]; then
    if [ ! "1" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
      ip link set "${N}" up 2>/dev/null || true
    fi
    IFS='/' read -r -a IPRA <<<"${IPR}"
    ip addr flush dev "${N}" 2>/dev/null || true
    ip addr add "${IPRA[0]}/${IPRA[1]:-"255.255.255.0"}" dev "${N}" 2>/dev/null || true
    if [ -n "${IPRA[2]}" ]; then
      ip route add default via "${IPRA[2]}" dev "${N}" 2>/dev/null || true
    fi
    if [ -n "${IPRA[3]:-${IPRA[2]}}" ]; then
      sed -i '/^nameserver /d' /etc/resolv.conf
      echo "nameserver ${IPRA[3]:-${IPRA[2]}}" >>/etc/resolv.conf
    fi
    sleep 1
  fi
  [ "${N::3}" = "eth" ] && ethtool -s "${N}" wol g 2>/dev/null || true
  # [ "${N::3}" = "eth" ] && ethtool -K ${N} rxhash off 2>/dev/null || true
  initConfigKey "${N}" "${MACR}" "${USER_CONFIG_FILE}"
done
ETHN=$(echo ${ETHX} | wc -w)
writeConfigKey "device.nic" "${ETHN}" "${USER_CONFIG_FILE}"
# No network devices
echo
[ "${ETHN}" -le 0 ] && die "No NIC found! - Loader does not work without Network connection."

BUSLIST="usb sata sas scsi nvme mmc ide virtio vmbus xen docker"
if [ "${BUS}" = "usb" ]; then
  VID="0x$(udevadm info --query property --name "${LOADER_DISK}" 2>/dev/null | grep "ID_VENDOR_ID" | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name "${LOADER_DISK}" 2>/dev/null | grep "ID_MODEL_ID" | cut -d= -f2)"
  [ "${VID}" = "0x" ] || [ "${PID}" = "0x" ] && die "The loader disk does not support the current USB Portable Hard Disk."
elif [ "${BUS}" = "docker" ]; then
  TYPE="PC"
elif ! (echo "${BUSLIST}" | grep -wq "${BUS}"); then
  die "$(printf "The loader disk does not support the current %s, only %s are supported." "${BUS}" "${BUSLIST// /\/}")"
fi

# Save variables to user config file
writeConfigKey "vid" "${VID:-"0x46f4"}" "${USER_CONFIG_FILE}"
writeConfigKey "pid" "${PID:-"0x0001"}" "${USER_CONFIG_FILE}"

# Inform user and check bus
echo -e "Loader Disk: \033[1;34m${LOADER_DISK}\033[0m"
echo -e "Loader Disk Type: \033[1;34m${BUS}\033[0m"
echo

# Decide if boot automatically
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"

case "${ARC_MODE}" in
  config)
    echo -e "\033[1;34mStarting Config Mode...\033[0m"
    ;;
  automated)
    echo -e "\033[1;34mStarting automated Build Mode...\033[0m"
    ;;
  update)
    echo -e "\033[1;34mStarting Update Mode...\033[0m"
    ;;
  dsm|reinstall|recovery)
    if [ "${BUILDDONE}" = "true" ]; then
      echo -e "\033[1;34mStarting DSM Mode...\033[0m"
      boot.sh && exit 0
    else
      echo -e "\033[1;34mRebooting to Config Mode...\033[0m"
      rebootTo "config" || die "Reboot to Config Mode failed!"
      exit 0
    fi
    ;;
  *)
    echo -e "\033[1;34mStarting Config Mode...\033[0m"
    ;;
esac
echo

BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
[ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=30
IPCON=""
echo -e "\033[1;37mDetected ${ETHN} NIC:\033[0m"
echo

[ ! -f /var/run/dhcpcd/pid ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 && sleep 3 || true
[ ! -f /var/run/dhttpd/pid ] && /etc/init.d/S90thttpd restart >/dev/null 2>&1 && sleep 3 || true
checkNIC
echo

# Tell webterminal that the loader is ready
touch "${HOME}/.initialized"

mkdir -p "${ADDONS_PATH}"
mkdir -p "${CUSTOM_PATH}"
mkdir -p "${LKMS_PATH}"
mkdir -p "${CONFIGS_PATH}"
mkdir -p "${MODULES_PATH}"
mkdir -p "${PATCH_PATH}"
mkdir -p "${USER_UP_PATH}"

DEVELOPMENT_MODE="$(readConfigKey "arc.dev" "${USER_CONFIG_FILE}")"
if [ "${DEVELOPMENT_MODE}" = "true" ]; then
  echo -e "\033[1;34mDevelopment Mode is enabled.\033[0m"
  curl -skL https://github.com/AuxXxilium/arc/archive/refs/heads/dev.zip -o /tmp/arc-dev.zip 2>/dev/null || true
  unzip -q /tmp/arc-dev.zip -d /tmp 2>/dev/null || true
  cp -rf /tmp/arc-dev/files/initrd/opt/arc /opt/arc 2>/dev/null || true
fi

# Load Arc Overlay
echo -e "\033[1;34mLoading Arc Overlay...\033[0m"
echo
echo -e "Use \033[1;34mDisplay Output\033[0m or \033[1;34mhttp://${IPCON}:${HTTPPORT:-7080}\033[0m to configure Loader."
echo

# Notification System
WEBHOOKNOTIFY="$(readConfigKey "arc.webhooknotify" "${USER_CONFIG_FILE}")"
if [ "${WEBHOOKNOTIFY}" = "true" ]; then
  WEBHOOKURL="$(readConfigKey "arc.webhookurl" "${USER_CONFIG_FILE}")"
  sendWebhook "${WEBHOOKURL}" "${ARC_MODE} is running @ ${IPCON}" || true
  echo -e "\033[1;34mWebhook Notification enabled.\033[0m"
  echo
fi
DISCORDNOTIFY="$(readConfigKey "arc.discordnotify" "${USER_CONFIG_FILE}")"
if [ "${DISCORDNOTIFY}" = "true" ]; then
  DISCORDUSER="$(readConfigKey "arc.userid" "${USER_CONFIG_FILE}")"
  if [ -n "${DISCORDUSER}" ]; then
    sendDiscord "${DISCORDUSER}" "${ARC_MODE} is running @ ${IPCON}" || true
    echo -e "\033[1;34mDiscord Notification enabled.\033[0m"
    echo
  fi
fi

# Check memory and load Arc
RAM=$(awk '/MemTotal:/ {printf "%.0f", $2 / 1024}' /proc/meminfo 2>/dev/null)
if [ "${RAM:-0}" -le 3500 ]; then
  echo -e "\033[1;31mYou have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of RAM.\033[0m"
  read -rp "Press Enter to continue..."
  if [ $? -eq 0 ]; then
    arc.sh
  fi
else
  arc.sh
fi