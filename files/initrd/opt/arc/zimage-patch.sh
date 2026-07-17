#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

###############################################################################
# Initialize environment
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"

arc_mode

set -o pipefail # Get exit code from process piped

# Sanity check
[ -f "${ORI_ZIMAGE_FILE}" ] || (die "${ORI_ZIMAGE_FILE} not found!" | tee -a "${LOG_FILE}")
[ -f "${MOD_ZIMAGE_FILE}" ] && rm -f "${MOD_ZIMAGE_FILE}"

KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${P_FILE}")"
if [ "${KERNEL}" = "custom" ]; then
  [ "${ARC_MODE}" != "dsm" ] && echo -e ">> Kernel: ${KERNEL} ${PLATFORM} (${KVER})"
  # Extract bzImage
  gzip -dc "${CUSTOM_PATH}/bzImage-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.gz" >"${MOD_ZIMAGE_FILE}" || die
else
  [ "${ARC_MODE}" != "dsm" ] && echo -e ">> Kernel: official ${PLATFORM} (${KVER})"
  # Extract vmlinux
  "${ARC_PATH}/extract-vmlinux" "${ORI_ZIMAGE_FILE}" >"${TMP_PATH}/vmlinux" 2>"${LOG_FILE}" || die
  # Patch boot params and ramdisk check
  "${ARC_PATH}/kpatch" "${TMP_PATH}/vmlinux" "${TMP_PATH}/vmlinux-mod" >"${LOG_FILE}" 2>&1 || die
  # Rebuild zImage
  "${ARC_PATH}/vmlinux-to-bzImage.sh" "${TMP_PATH}/vmlinux-mod" "${MOD_ZIMAGE_FILE}" "${ORI_ZIMAGE_FILE}" "${PLATFORM}" >"${LOG_FILE}" 2>&1 || die
fi

# Sanity check: rebuilt zImage must exist and be reasonably sized
[ -s "${MOD_ZIMAGE_FILE}" ] || die "${MOD_ZIMAGE_FILE} was not created!"
MOD_ZIMAGE_SIZE="$(stat -c%s "${MOD_ZIMAGE_FILE}" 2>/dev/null || echo 0)"
ORI_ZIMAGE_SIZE="$(stat -c%s "${ORI_ZIMAGE_FILE}" 2>/dev/null || echo 0)"
if [ "${MOD_ZIMAGE_SIZE}" -lt $((ORI_ZIMAGE_SIZE / 2)) ]; then
  die "${MOD_ZIMAGE_FILE} looks truncated (${MOD_ZIMAGE_SIZE} bytes vs original ${ORI_ZIMAGE_SIZE} bytes)!"
fi

sync