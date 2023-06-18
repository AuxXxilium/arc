#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Wait kernel enumerate the disks
CNT=3
while true; do
  [ ${CNT} -eq 0 ] && break
  LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
  [ -n "${LOADER_DISK}" ] && break
  CNT=$((${CNT}-1))
  sleep 1
done

[ -z "${LOADER_DISK}" ] && die "Loader disk not found!"
NUM_PARTITIONS=$(blkid | grep "${LOADER_DISK}[0-9]\+" | cut -d: -f1 | wc -l)
[ $NUM_PARTITIONS -lt 3 ] && die "Loader disk seems to be damaged!"
[ $NUM_PARTITIONS -gt 3 ] && die "There are multiple loader disks, please insert only one loader disk!"

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
mount ${LOADER_DISK}1 ${BOOTLOADER_PATH} || die "`printf "Can't mount %s" "${BOOTLOADER_PATH}"`"
mount ${LOADER_DISK}2 ${SLPART_PATH}     || die "`printf "Can't mount %s" "${SLPART_PATH}"`"
mount ${LOADER_DISK}3 ${CACHE_PATH}      || die "`printf "Can't mount %s" "${CACHE_PATH}"`"

# Shows title
clear
TITLE="${ARPL_TITLE}"
printf "\033[1;30m%*s\n" $COLUMNS ""
printf "\033[1;30m%*s\033[A\n" $COLUMNS ""
printf "\033[1;34m%*s\033[0m\n" $(((${#TITLE}+$COLUMNS)/2)) "${TITLE}"
printf "\033[1;30m%*s\033[0m\n" $COLUMNS ""

# Move/link SSH machine keys to/from cache volume
[ ! -d "${CACHE_PATH}/ssh" ] && cp -R "/etc/ssh" "${CACHE_PATH}/ssh"
rm -rf "/etc/ssh"
ln -s "${CACHE_PATH}/ssh" "/etc/ssh"
# Link bash history to cache volume
rm -rf ~/.bash_history
ln -s ${CACHE_PATH}/.bash_history ~/.bash_history
touch ~/.bash_history
if ! grep -q "arc.sh" ~/.bash_history; then
  echo "arc.sh " >> ~/.bash_history
fi
# Check if exists directories into P3 partition, if yes remove and link it
if [ -d "${CACHE_PATH}/model-configs" ]; then
  rm -rf "${MODEL_CONFIG_PATH}"
  ln -s "${CACHE_PATH}/model-configs" "${MODEL_CONFIG_PATH}"
fi

if [ -d "${CACHE_PATH}/patch" ]; then
  rm -rf "${PATCH_PATH}"
  ln -s "${CACHE_PATH}/patch" "${PATCH_PATH}"
fi

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
  writeConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
  writeConfigKey "model" "" "${USER_CONFIG_FILE}"
  writeConfigKey "build" "" "${USER_CONFIG_FILE}"
  writeConfigKey "sn" "" "${USER_CONFIG_FILE}"
  # writeConfigKey "maxdisks" "" "${USER_CONFIG_FILE}"
  writeConfigKey "layout" "qwertz" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "de" "${USER_CONFIG_FILE}"
  writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.acpid" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "arc" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.directboot" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "device" "{}" "${USER_CONFIG_FILE}"
  # When the user has not customized, Use 1 to maintain normal startup parameters.
  # writeConfigKey "cmdline.netif_num" "1" "${USER_CONFIG_FILE}"
  # writeConfigKey "cmdline.mac1" "`cat /sys/class/net/${ETHX[0]}/address | sed 's/://g'`" "${USER_CONFIG_FILE}"
fi

# Get MAC address
ETHX=(`ls /sys/class/net/ | grep eth`)  # real network cards list
for N in $(seq 1 ${#ETHX[@]}); do
  MACR="`cat /sys/class/net/${ETHX[$(expr ${N} - 1)]}/address | sed 's/://g'`"
  # Initialize with real MAC
  writeConfigKey "device.mac${N}" "${MACR}" "${USER_CONFIG_FILE}"
  # Write real Mac to cmdline config
  writeConfigKey "cmdline.mac${N}" "${MACR}" "${USER_CONFIG_FILE}"
  # Enable Wake on Lan, ignore errors
  ethtool -s ${ETHX[$(expr ${N} - 1)]} wol g 2>/dev/null
done


# Get the VID/PID if we are in USB
VID="0x0000"
PID="0x0000"
BUS=`udevadm info --query property --name ${LOADER_DISK} | grep BUS | cut -d= -f2`
if [ "${BUS}" = "usb" ]; then
  VID="0x`udevadm info --query property --name ${LOADER_DISK} | grep ID_VENDOR_ID | cut -d= -f2`"
  PID="0x`udevadm info --query property --name ${LOADER_DISK} | grep ID_MODEL_ID | cut -d= -f2`"
elif [ "${BUS}" != "ata" ]; then
  die "Loader disk neither USB or DoM"
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -en "Loader disk: \033[1;34m${LOADER_DISK}\033[0m ("
if [ "${BUS}" = "usb" ]; then
  echo -en "\033[1;34mUSB flashdisk\033[0m"
else
  echo -en "\033[1;34mSATA DoM\033[0m"
fi
echo ")"

# Check if partition 3 occupies all free space, resize if needed
LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
SIZEOFDISK=`cat /sys/block/${LOADER_DEVICE_NAME}/size`
ENDSECTOR=$((`fdisk -l ${LOADER_DISK} | awk '/'${LOADER_DEVICE_NAME}3'/{print$3}'`+1))
if [ ${SIZEOFDISK} -ne ${ENDSECTOR} ]; then
  echo -e "\033[1;36m`printf "Resizing %s" "${LOADER_DISK}3"`\033[0m"
  echo -e "d\n\nn\n\n\n\n\nn\nw" | fdisk "${LOADER_DISK}" >"${LOG_FILE}" 2>&1 || dieLog
  resize2fs ${LOADER_DISK}3 >"${LOG_FILE}" 2>&1 || dieLog
fi

# Load keymap name
LAYOUT="`readConfigKey "layout" "${USER_CONFIG_FILE}"`"
KEYMAP="`readConfigKey "keymap" "${USER_CONFIG_FILE}"`"

# Loads a keymap if is valid
if [ -f /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz ]; then
  echo -e "Loading keymap \033[1;34m${LAYOUT}/${KEYMAP}\033[0m"
  zcat /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz | loadkeys
fi

# Decide if boot automatically
BOOT=1
if ! loaderIsConfigured; then
  echo -e "\033[1;31mLoader is not configured!\033[0m"
  BOOT=0
elif grep -q "IWANTTOCHANGETHECONFIG" /proc/cmdline; then
  echo -e "\033[1;31mUser requested edit settings.\033[0m"
  BOOT=0
fi

# If is to boot automatically, do it
if [ ${BOOT} -eq 1 ]; then 
  boot.sh && exit 0
fi

# Wait for an IP
echo "`printf "Detected %s NIC, Waiting IP." "${#ETHX[@]}"`"
for N in $(seq 0 $(expr ${#ETHX[@]} - 1)); do
  COUNT=0
  echo -en "${ETHX[${N}]}: "
  while true; do
    if [ -z "`ip link show ${ETHX[${N}]} | grep 'UP'`" ]; then
      echo -en "\r${ETHX[${N}]}: DOWN\n"
      break
    fi
    if [ ${COUNT} -eq 20 ]; then
      echo -en "\r${ETHX[${N}]}: ERROR - Timeout\n"
      break
    fi
    COUNT=$((${COUNT}+5))
    IP=`ip route show dev ${ETHX[${N}]} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p'`
    if [ -n "${IP}" ]; then
      echo -en "\r${ETHX[${N}]}: `printf "Access \033[1;34mhttp://%s:7681\033[0m to connect via web terminal." "${IP}"`\n"
      break
    fi
    echo -n "."
    sleep 5
  done
done

# Inform user
echo
echo -e "Call \033[1;34marc.sh\033[0m to configure loader"
echo
echo -e "User config is on \033[1;34m${USER_CONFIG_FILE}\033[0m"
echo -e "Default SSH Root password is \033[1;34mRedp1ll\033[0m"
echo

# Check memory
RAM=`free -m | awk '/Mem:/{print$2}'`
if [ ${RAM} -le 3500 ]; then
  echo -e "\033[1;31mYou have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of memory.\033[0m\n"
fi

mkdir -p "${ADDONS_PATH}"
mkdir -p "${LKM_PATH}"
mkdir -p "${MODULES_PATH}"

install-addons.sh
sleep 3
arc.sh