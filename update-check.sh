#!/usr/bin/env bash

# 23.5.0
[ ! -f /mnt/p1/boot/grub/grub.cfg ] && exit 1

# 23.7.0
. /opt/arpl/include/functions.sh
if loaderIsConfigured; then
  if [ -f "${ORI_RDGZ_FILE}" ]; then
    rm -rf "${RAMDISK_PATH}"
    mkdir -p "${RAMDISK_PATH}"
    (
      cd "${RAMDISK_PATH}"
      xz -dc <"${ORI_RDGZ_FILE}" | cpio -idm
    ) >/dev/null 2>&1
    . "${RAMDISK_PATH}/etc/VERSION"
    [ -n "$(readConfigKey "build" "${USER_CONFIG_FILE}")" ] && deleteConfigKey "build" "${USER_CONFIG_FILE}"
    [ -z "$(readConfigKey "productver" "${USER_CONFIG_FILE}")" ] && writeConfigKey "productver" "${majorversion}.${minorversion}" "${USER_CONFIG_FILE}"
  fi
fi

exit 0