#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"

set -o pipefail # Get exit code from process piped

# Sanity check
[ -f "${ORI_ZIMAGE_FILE}" ] || (die "${ORI_ZIMAGE_FILE} not found!" | tee -a "${LOG_FILE}")

rm -f "${MOD_ZIMAGE_FILE}"

KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
is_in_array "${PLATFORM}" "${KVER5L[@]}" && KVERP="${PRODUCTVER}-${KVER}" || true
if [ "${KERNEL}" = "custom" ]; then
  echo -e ">> using customized Kernel for ${PLATFORM} (${KVER})"
  # Extract bzImage
  gzip -dc "${CUSTOM_PATH}/bzImage-${PLATFORM}-${KVERP}.gz" >"${MOD_ZIMAGE_FILE}"
else
  echo -e ">> using official Kernel for ${PLATFORM} (${KVER})"
  # Extract vmlinux
  "${ARC_PATH}/bzImage-to-vmlinux.sh" "${ORI_ZIMAGE_FILE}" "${TMP_PATH}/vmlinux" >"${LOG_FILE}" 2>&1 || dieLog
  # Patch boot params and ramdisk check
  "${ARC_PATH}/kpatch" "${TMP_PATH}/vmlinux" "${TMP_PATH}/vmlinux-mod" >"${LOG_FILE}" 2>&1 || dieLog
  # rebuild zImage
  "${ARC_PATH}/vmlinux-to-bzImage.sh" "${TMP_PATH}/vmlinux-mod" "${MOD_ZIMAGE_FILE}" || dieLog
fi

sync