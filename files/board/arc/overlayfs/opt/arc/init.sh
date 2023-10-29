#!/usr/bin/env bash

set -e
[ -z "${ARC_PATH}" ] || [ ! -d "${ARC_PATH}/include" ] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh

# Wait kernel enumerate the disks
CNT=3
while true; do
  [ ${CNT} -eq 0 ] && break
  LOADER_DISK="$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1)"
  [ -n "${LOADER_DISK}" ] && break
  CNT=$((${CNT} - 1))
  sleep 1
done

[ -z "${LOADER_DISK}" ] && die "Loader disk not found!"
NUM_PARTITIONS=$(blkid | grep "${LOADER_DISK}[0-9]\+" | cut -d: -f1 | wc -l)
[ ${NUM_PARTITIONS} -lt 3 ] && die "Loader disk seems to be damaged!"
[ ${NUM_PARTITIONS} -gt 3 ] && die "There are multiple loader disks, please insert only one loader disk!"

# Check partitions and ignore errors
fsck.vfat -aw ${LOADER_DISK}1 >/dev/null 2>&1 || true
fsck.ext2 -p ${LOADER_DISK}2 >/dev/null 2>&1 || true
fsck.ext4 -p ${LOADER_DISK}3 >/dev/null 2>&1 || true
# Make folders to mount partitions
mkdir -p ${BOOTLOADER_PATH}
mkdir -p ${SLPART_PATH}
mkdir -p ${CACHE_PATH}
mkdir -p ${DSMROOT_PATH}
# Mount the partitions
mount ${LOADER_DISK}1 ${BOOTLOADER_PATH} || die "Can't mount ${BOOTLOADER_PATH}"
mount ${LOADER_DISK}2 ${SLPART_PATH} || die "Can't mount ${SLPART_PATH}"
mount ${LOADER_DISK}3 ${CACHE_PATH} || die "Can't mount ${CACHE_PATH}"

# Shows title
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="${ARC_TITLE}"
printf "\033[1;30m%*s\n" ${COLUMNS} ""
printf "\033[1;30m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;30m%*s\033[0m\n" ${COLUMNS} ""

# Move/link SSH machine keys to/from cache volume
[ ! -d "${PART3_PATH}/ssh" ] && cp -R "/etc/ssh" "${PART3_PATH}/ssh"
rm -rf "/etc/ssh"
ln -s "${PART3_PATH}/ssh" "/etc/ssh"

# Link bash history to cache volume
rm -rf ~/.bash_history
ln -s "${PART3_PATH}/.bash_history" ~/.bash_history
touch ~/.bash_history
if ! grep -q "arc.sh" ~/.bash_history; then
  echo "arc.sh " >>~/.bash_history
fi

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
fi
initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "qwertz" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "de" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
initConfigKey "extensions" "{}" "${USER_CONFIG_FILE}"
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc" "{}" "${USER_CONFIG_FILE}"
initConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.mac1" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.staticip" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.directboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.patch" "random" "${USER_CONFIG_FILE}"
initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "arc.bootipwait" "20" "${USER_CONFIG_FILE}"
initConfigKey "arc.bootwait" "5" "${USER_CONFIG_FILE}"
initConfigKey "arc.kernelload" "power" "${USER_CONFIG_FILE}"
initConfigKey "arc.kernelpanic" "5" "${USER_CONFIG_FILE}"
initConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
initConfigKey "arc.bootcount" "0" "${USER_CONFIG_FILE}"
initConfigKey "arc.odp" "false" "${USER_CONFIG_FILE}"
initConfigKey "arc.hddsort" "true" "${USER_CONFIG_FILE}"
initConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
initConfigKey "device" "{}" "${USER_CONFIG_FILE}"

# Init Network
ETHX=($(ls /sys/class/net/ | grep eth))  # real network cards list
# No network devices
[ ${#ETHX[@]} -le 0 ] && die "No NIC found! - Loader does not work without Network connection."
MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
if [ "${MACSYS}" = "custom" ]; then
  MACR="$(cat /sys/class/net/eth0/address | sed 's/://g')"
  MACA="$(readConfigKey "arc.mac1" "${USER_CONFIG_FILE}")"
  if [ -n "${MACA}" ] && [ "${MACA}" != "${MACR}" ]; then
    MAC="${MACA:0:2}:${MACA:2:2}:${MACA:4:2}:${MACA:6:2}:${MACA:8:2}:${MACA:10:2}"
    echo "Setting eth0 MAC to ${MAC}"
    ip link set dev eth0 address "${MAC}" >/dev/null 2>&1 &&
    (/etc/init.d/S41dhcpcd restart >/dev/null 2>&1 &) || true
    sleep 2
  elif [ -z "${MACA}" ]; then
    # Write real Mac to cmdline config
    writeConfigKey "arc.mac1" "${MACR}" "${USER_CONFIG_FILE}"
  fi
  echo
fi

# Get the VID/PID if we are in USB
VID="0x46f4"
PID="0x0001"
BUS=$(getBus "${LOADER_DISK}")

if [ "${BUS}" = "usb" ]; then
  VID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_VENDOR_ID | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name "${LOADER_DISK}" | grep ID_MODEL_ID | cut -d= -f2)"
elif [ "${BUS}" != "sata" -a "${BUS}" != "scsi" -a "${BUS}" != "nvme" ]; then
  die "Loader disk is not USB or SATA/SCSI/NVME DoM"
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -e "Loader Disk: \033[1;34m${LOADER_DISK}\033[0m"
echo -e "Loader Disk Type: \033[1;34m${BUS^^}\033[0m"

# Load keymap name
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"

# Loads a keymap if is valid
if [ -f "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" ]; then
  echo -e "Loading Keymap \033[1;34m${LAYOUT}/${KEYMAP}\033[0m"
  zcat "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" | loadkeys
fi
echo

# Grep Config Values
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"

# Decide if boot automatically
if grep -q "IWANTTOCHANGETHECONFIG" /proc/cmdline; then
  echo -e "\033[1;34mUser requested edit settings.\033[0m"
elif [ "${BUILDDONE}" = "true" ]; then
  echo -e "\033[1;34mLoader is configured!\033[0m"
  boot.sh && exit 0
else
  echo -e "\033[1;34mUser requested edit settings.\033[0m"
fi
echo

# Read Bootcount
BOOTCOUNT="$(readConfigKey "arc.bootcount" "${USER_CONFIG_FILE}")"
[ -z "${BOOTCOUNT}" ] && BOOTCOUNT=0
# Read Staticip/DHCP
STATICIP="$(readConfigKey "arc.staticip" "${USER_CONFIG_FILE}")"
# Wait for an IP
BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
[ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=20
echo -e "\033[1;34mDetected ${#ETHX[@]} NIC.\033[0m \033[1;37mWaiting for Connection:\033[0m"
for N in $(seq 0 $((${#ETHX[@]} - 1))); do
  DRIVER=$(ls -ld /sys/class/net/${ETHX[${N}]}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  COUNT=0
  sleep 3
  while true; do
    if ethtool ${ETHX[${N}]} | grep 'Link detected' | grep -q 'no'; then
      echo -e "\r${DRIVER}: NOT CONNECTED"
      break
    fi
    IP="$(getIP ${ETHX[${N}]})"
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
      echo -e "\r${DRIVER} (${SPEED} | ${MSG}): Access \033[1;34mhttp://${IP}:7681\033[0m to connect to Arc via web."
      break
    fi
    COUNT=$((${COUNT} + 1))
    if [ ${COUNT} -eq ${BOOTIPWAIT} ]; then
      echo -e "\r${DRIVER}: TIMEOUT"
      break
    fi
    sleep 1
  done
done

# Inform user
echo
echo -e "Call \033[1;34marc.sh\033[0m to configure loader"
echo
echo -e "User config is on \033[1;34m${USER_CONFIG_FILE}\033[0m"
echo -e "Default SSH Root password is \033[1;34marc\033[0m"
echo

mkdir -p "${ADDONS_PATH}"
mkdir -p "${EXTENSIONS_PATH}"
mkdir -p "${LKM_PATH}"
mkdir -p "${MODULES_PATH}"
mkdir -p "${MODEL_CONFIG_PATH}"
mkdir -p "${PATCH_PATH}"

# Load arc
updateAddons
updateExtensions
echo -e "\033[1;34mLoading Arc Loader Overlay...\033[0m"
sleep 2

# Check memory and load Arc
RAM=$(free -m | grep -i mem | awk '{print$2}')
if [ ${RAM} -le 3500 ]; then
  echo -e "\033[1;34mYou have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of RAM.\033[0m\n"
  echo -e "\033[1;34mUse arc.sh to proceed. Not recommended!\033[0m\n"
else
  arc.sh
fi