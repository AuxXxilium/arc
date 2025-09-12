#!/usr/bin/env bash
# Based on code and ideas from @jumkey

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

. "${ARC_PATH}/include/functions.sh"

calc_run_size() {
  NUM='\([0-9a-fA-F]*[ \t]*\)'
  OUT=$(sed -n 's/^[ \t0-9]*.b[sr][sk][ \t]*'"${NUM}${NUM}${NUM}${NUM}"'.*/0x\1 0x\4/p')

  if [ -z "${OUT}" ]; then
    echo "Never found .bss or .brk file offset" >&2
    return 1
  fi

  read -r sizeA offsetA sizeB offsetB <<<$(echo ${OUT} | awk '{printf "%d %d %d %d", strtonum($1), strtonum($2), strtonum($3), strtonum($4)}')

  runSize=$((offsetA + sizeA + sizeB))

  # BFD linker shows the same file offset in ELF.
  if [ "${offsetA}" -ne "${offsetB}" ]; then
    # Gold linker shows them as consecutive.
    endSize=$((offsetB + sizeB))
    if [ "${endSize}" -ne "${runSize}" ]; then
      printf "sizeA: 0x%x\n" ${sizeA} >&2
      printf "offsetA: 0x%x\n" ${offsetA} >&2
      printf "sizeB: 0x%x\n" ${sizeB} >&2
      printf "offsetB: 0x%x\n" ${offsetB} >&2
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
  printf $(
    local dec_size=0
    for F in "$@"; do dec_size=$((dec_size + $(stat -c "%s" "${F}"))); done
    printf "%08x\n" "${dec_size}" | sed 's/\(..\)/\1 /g' | {
      read -r ch0 ch1 ch2 ch3
      for ch in "${ch3}" "${ch2}" "${ch1}" "${ch0}"; do printf '%s%03o' '\' "$((0x${ch}))"; done
    }
  )
}

size_le() {
  printf $(
    printf "%08x\n" "${@}" | sed 's/\(..\)/\1 /g' | {
      read -r ch0 ch1 ch2 ch3
      for ch in "${ch3}" "${ch2}" "${ch1}" "${ch0}"; do printf '%s%03o' '\' "$((0x${ch}))"; done
    }
  )
}

VMLINUX_MOD=${1}
ZIMAGE_MOD=${2}

KVER=$(strings "${VMLINUX_MOD}" | grep -Eo "Linux version [0-9]+\.[0-9]+\.[0-9]+" | head -1 | awk '{print $3}')
if [ "${KVER:0:1}" = "4" ]; then
  echo -e ">> patching Kernel 4.x"
  gzip -dc "${ARC_PATH}/bzImage-template-v4.gz" >"${ZIMAGE_MOD}" 2>/dev/null || exit 1

  dd if="${VMLINUX_MOD}" of="${ZIMAGE_MOD}" bs=16494 seek=1 conv=notrunc 2>/dev/null || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=15745134 seek=1 conv=notrunc 2>/dev/null || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=15745244 seek=1 conv=notrunc 2>/dev/null || exit 1

  RUN_SIZE=$(objdump -h "${VMLINUX_MOD}" | calc_run_size 2>/dev/null)
  size_le "${RUN_SIZE}" | dd of="${ZIMAGE_MOD}" bs=15745210 seek=1 conv=notrunc 2>/dev/null || exit 1
  size_le "$((16#$(crc32 "${ZIMAGE_MOD}" | awk '{print $1}') ^ 0xFFFFFFFF))" | dd of="${ZIMAGE_MOD}" conv=notrunc oflag=append 2>/dev/null || exit 1
elif [ "${KVER:0:1}" = "5" ]; then
  echo -e ">> patching Kernel 5.x"
  gzip -dc "${ARC_PATH}/bzImage-template-v5.gz" >"${ZIMAGE_MOD}" 2>/dev/null || exit 1

  dd if="${VMLINUX_MOD}" of="${ZIMAGE_MOD}" bs=14561 seek=1 conv=notrunc 2>/dev/null || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=34463421 seek=1 conv=notrunc 2>/dev/null || exit 1
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=34479132 seek=1 conv=notrunc 2>/dev/null || exit 1
  #  RUN_SIZE=$(objdump -h "${VMLINUX_MOD}" | calc_run_size 2>/dev/null)
  #  size_le "${RUN_SIZE}" | dd of="${ZIMAGE_MOD}" bs=34626904 seek=1 conv=notrunc 2>/dev/null || exit 1
  size_le "$((16#$(crc32 "${ZIMAGE_MOD}" | awk '{print $1}') ^ 0xFFFFFFFF))" | dd of="${ZIMAGE_MOD}" conv=notrunc oflag=append 2>/dev/null || exit 1
else
  die "Kernel version ${KVER} not supported!"
  exit 1
fi