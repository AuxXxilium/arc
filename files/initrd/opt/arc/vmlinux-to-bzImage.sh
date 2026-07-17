#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# Based on code and ideas from @jumkey and @petersuh-q3

###############################################################################
# Initialize environment
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

read_u8() {
  dd if="${1}" bs=1 skip="$((${2}))" count=1 2>/dev/null | od -An -tu1 | tr -d '[:space:]'
}
read_u32() {
  dd if="${1}" bs=1 skip="$((${2}))" count=4 2>/dev/null | od -An -tu4 --endian=little | tr -d '[:space:]'
}

splice_bzImage() {
  local VMLINUX_MOD="${1}" ZIMAGE_MOD="${2}" ORI_ZIMAGE="${3}"

  [ -f "${ORI_ZIMAGE}" ] || {
    echo "ERROR: ${ORI_ZIMAGE} not found" >&2
    return 1
  }

  local SETUP_SECTS PAYLOAD_OFFSET PAYLOAD_LENGTH INNER_POS PAYLOAD_START
  SETUP_SECTS="$(read_u8 "${ORI_ZIMAGE}" 0x1f1)"
  [ "${SETUP_SECTS}" -eq 0 ] 2>/dev/null && SETUP_SECTS=4
  PAYLOAD_OFFSET="$(read_u32 "${ORI_ZIMAGE}" 0x248)"
  PAYLOAD_LENGTH="$(read_u32 "${ORI_ZIMAGE}" 0x24c)"
  INNER_POS=$(((SETUP_SECTS + 1) * 512))
  PAYLOAD_START=$((INNER_POS + PAYLOAD_OFFSET))

  if [ -z "${PAYLOAD_OFFSET}" ] || [ -z "${PAYLOAD_LENGTH}" ] || [ "${PAYLOAD_LENGTH}" -le 4 ]; then
    echo "ERROR: could not parse bzImage boot header of ${ORI_ZIMAGE}" >&2
    return 1
  fi

  local LZMA_TMP
  LZMA_TMP="$(mktemp "${TMP_PATH:-/tmp}/vmlinux-lzma.XXXXXX")"

  xz --format=lzma -9e -c "${VMLINUX_MOD}" >"${LZMA_TMP}" || {
    echo "ERROR: lzma compression of ${VMLINUX_MOD} failed" >&2
    rm -f "${LZMA_TMP}"
    return 1
  }

  local VMLINUX_SIZE LZMA_SIZE NEW_PAYLOAD_LENGTH
  VMLINUX_SIZE="$(stat -c%s "${VMLINUX_MOD}")"
  LZMA_SIZE="$(stat -c%s "${LZMA_TMP}")"
  NEW_PAYLOAD_LENGTH=$((LZMA_SIZE + 4))

  if [ "${NEW_PAYLOAD_LENGTH}" -gt "${PAYLOAD_LENGTH}" ]; then
    echo "ERROR: patched kernel payload (${NEW_PAYLOAD_LENGTH} bytes) does not fit" >&2
    echo "       in the original bzImage payload region (${PAYLOAD_LENGTH} bytes)." >&2
    echo "       Refusing to build a corrupt image." >&2
    rm -f "${LZMA_TMP}"
    return 1
  fi

  cp -f "${ORI_ZIMAGE}" "${ZIMAGE_MOD}" || {
    rm -f "${LZMA_TMP}"
    return 1
  }

  {
    cat "${LZMA_TMP}"
    size_le "${VMLINUX_SIZE}"
    PAD=$((PAYLOAD_LENGTH - NEW_PAYLOAD_LENGTH))
    [ "${PAD}" -gt 0 ] && dd if=/dev/zero bs=1 count="${PAD}" 2>/dev/null
  } | dd of="${ZIMAGE_MOD}" bs=1 seek="${PAYLOAD_START}" conv=notrunc 2>/dev/null || {
    rm -f "${LZMA_TMP}"
    return 1
  }

  rm -f "${LZMA_TMP}"
  return 0
}

calc_run_size() {
  NUM='\([0-9a-fA-F]*[ \t]*\)'
  OUT=$(sed -n 's/^[ \t0-9]*.b[sr][sk][ \t]*'"${NUM}${NUM}${NUM}${NUM}"'.*/0x\1 0x\4/p')

  if [ -z "${OUT}" ]; then
    echo "Never found .bss or .brk file offset" >&2
    return 1
  fi

  read -r sizeA offsetA sizeB offsetB <<<"$(echo "${OUT}" | awk '{printf "%d %d %d %d", strtonum($1), strtonum($2), strtonum($3), strtonum($4)}')"

  runSize=$((offsetA + sizeA + sizeB))

  # BFD linker shows the same file offset in ELF.
  if [ "${offsetA}" -ne "${offsetB}" ]; then
    # Gold linker shows them as consecutive.
    endSize=$((offsetB + sizeB))
    if [ "${endSize}" -ne "${runSize}" ]; then
      printf "sizeA: 0x%x\n" "${sizeA}" >&2
      printf "offsetA: 0x%x\n" "${offsetA}" >&2
      printf "sizeB: 0x%x\n" "${sizeB}" >&2
      printf "offsetB: 0x%x\n" "${offsetB}" >&2
      echo ".bss and .brk are non-contiguous" >&2
      return 1
    fi
  fi

  printf "%d\n" ${runSize}
  return 0
}

# Adapted from: scripts/Makefile.lib
# Usage: size_append FILE [FILE2] [FILEn]...
# Output: LE HEX with size of file in bytes (to STDOUT)
file_size_le() {
  printf "$(
    local dec_size=0
    for F in "$@"; do dec_size=$((dec_size + $(stat -c "%s" "${F}"))); done
    printf "%08x\n" "${dec_size}" | sed 's/\(..\)/\1 /g' | {
      read -r ch0 ch1 ch2 ch3
      for ch in "${ch3}" "${ch2}" "${ch1}" "${ch0}"; do printf '%s%03o' '\' "$((0x${ch}))"; done
    }
  )"
}

size_le() {
  printf "$(
    printf "%08x\n" "${@}" | sed 's/\(..\)/\1 /g' | {
      read -r ch0 ch1 ch2 ch3
      for ch in "${ch3}" "${ch2}" "${ch1}" "${ch0}"; do printf '%s%03o' '\' "$((0x${ch}))"; done
    }
  )"
}

VMLINUX_MOD=${1}
ZIMAGE_MOD=${2}
ORI_ZIMAGE=${3}
PLATFORM=${4}

if [ "${PLATFORM}" = "epyc7003ntb" ]; then
  splice_bzImage "${VMLINUX_MOD}" "${ZIMAGE_MOD}" "${ORI_ZIMAGE}" || exit 1
  exit 0
fi

KVER=$(strings "${VMLINUX_MOD}" | grep -Eo "Linux version [0-9]+\.[0-9]+\.[0-9]+" | head -1 | awk '{print $3}')
if [ "${KVER:0:1}" -lt 5 ]; then
  # Kernel version 4.x or 3.x (bromolow)
  # zImage_head           16494
  # payload(
  #   vmlinux.bin         x
  #   padding             0xf00000-x
  #   vmlinux.bin size    4
  # )                     0xf00004
  # zImage_tail(
  #   unknown             72
  #   run_size            4
  #   unknown             30
  #   vmlinux.bin size    4
  #   unknown             114460
  # )                     114570
  # crc32                 4
  gzip -dc "${ARC_PATH}/bzImage-template-v4.gz" >"${ZIMAGE_MOD}" || exit 1

  dd if="${VMLINUX_MOD}" of="${ZIMAGE_MOD}" bs=16494 seek=1 conv=notrunc || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=15745134 seek=1 conv=notrunc || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=15745244 seek=1 conv=notrunc || exit 1

  RUN_SIZE=$(objdump -h "${VMLINUX_MOD}" | calc_run_size)
  size_le "${RUN_SIZE}" | dd of="${ZIMAGE_MOD}" bs=15745210 seek=1 conv=notrunc || exit 1
  size_le "$((16#$(crc32 "${ZIMAGE_MOD}" | awk '{print $1}') ^ 0xFFFFFFFF))" | dd of="${ZIMAGE_MOD}" conv=notrunc oflag=append || exit 1
else
  # Kernel version 5.x
  gzip -dc "${ARC_PATH}/bzImage-template-v5.gz" >"${ZIMAGE_MOD}" || exit 1

  dd if="${VMLINUX_MOD}" of="${ZIMAGE_MOD}" bs=14561 seek=1 conv=notrunc || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=34463421 seek=1 conv=notrunc || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=34479132 seek=1 conv=notrunc || exit 1
  #  RUN_SIZE=$(objdump -h "${VMLINUX_MOD}" | calc_run_size)
  #  size_le "${RUN_SIZE}" | dd of="${ZIMAGE_MOD}" bs=34626904 seek=1 conv=notrunc || exit 1
  size_le "$((16#$(crc32 "${ZIMAGE_MOD}" | awk '{print $1}') ^ 0xFFFFFFFF))" | dd of="${ZIMAGE_MOD}" conv=notrunc oflag=append || exit 1
fi