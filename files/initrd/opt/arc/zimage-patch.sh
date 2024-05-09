#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh

set -o pipefail # Get exit code from process piped

# Sanity check
[ -f "${ORI_ZIMAGE_FILE}" ] || (die "${ORI_ZIMAGE_FILE} not found!" | tee -a "${LOG_FILE}")

rm -f "${MOD_ZIMAGE_FILE}"

KERNEL="$(readConfigKey "arc.kernel" "${USER_CONFIG_FILE}")"
if [ "${KERNEL}" = "custom" ]; then
  echo -e "Using customized zImage"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.[${PRODUCTVER}].kver" "${P_FILE}")"
  # Modify KVER for Epyc7002
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVERP="${PRODUCTVER}-${KVER}"
  else
    KVERP="${KVER}"
  fi
  # Extract bzImage
  gzip -dc "${CUSTOM_PATH}/bzImage-${PLATFORM}-${KVERP}.gz" >"${MOD_ZIMAGE_FILE}"
else
  echo -e "Patching zImage"
  # Extract vmlinux
  ${ARC_PATH}/bzImage-to-vmlinux.sh "${ORI_ZIMAGE_FILE}" "${TMP_PATH}/vmlinux" >"${LOG_FILE}" 2>&1 || dieLog
  # Patch boot params and ramdisk check
  ${ARC_PATH}/kpatch "${TMP_PATH}/vmlinux" "${TMP_PATH}/vmlinux-mod" >"${LOG_FILE}" 2>&1 || dieLog
  # rebuild zImage
  ${ARC_PATH}/vmlinux-to-bzImage.sh "${TMP_PATH}/vmlinux-mod" "${MOD_ZIMAGE_FILE}" >"${LOG_FILE}" 2>&1 || dieLog
fi

sync