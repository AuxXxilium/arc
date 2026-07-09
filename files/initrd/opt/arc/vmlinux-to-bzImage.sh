#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# Rebuilds a bzImage from a patched vmlinux by swapping only the compressed
# kernel payload inside a copy of the genuine, original bzImage - preserving
# its real setup code, decompressor stub and boot header verbatim.
#
# This replaces the old approach of splicing a raw (uncompressed) vmlinux
# into a fixed-size prebuilt template at hardcoded byte offsets. That method
# has no way to know whether the patched vmlinux actually fits inside the
# template's payload region: if it doesn't, the write silently overflows
# into the template's trailing fields, producing a bzImage that triple-faults
# at kexec with no output (see https://github.com/RROrg/rr/issues/32166).
# Operating on the real, current bzImage instead removes the fixed capacity
# ceiling entirely, and the size check below turns any remaining mismatch
# into a loud build-time failure instead of silent corruption.
#
# Based on code and ideas from @jumkey and @petersuh-q3

###############################################################################
# Initialize environment
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Read u8/u32 little-endian integers from the Linux x86 boot header.
# 1 - file
# 2 - byte offset
read_u8() {
  dd if="${1}" bs=1 skip="$((${2}))" count=1 2>/dev/null | od -An -tu1 | tr -d '[:space:]'
}
read_u32() {
  dd if="${1}" bs=1 skip="$((${2}))" count=4 2>/dev/null | od -An -tu4 --endian=little | tr -d '[:space:]'
}

# Write a u32 as 4 little-endian bytes to stdout.
size_le() {
  printf '%08x' "${1}" | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/' | xxd -r -p
}

VMLINUX_MOD="${1}"
ZIMAGE_MOD="${2}"
ORI_ZIMAGE="${3}"

[ -f "${VMLINUX_MOD}" ] || {
  echo "ERROR: ${VMLINUX_MOD} not found" >&2
  exit 1
}
[ -f "${ORI_ZIMAGE}" ] || {
  echo "ERROR: ${ORI_ZIMAGE} not found" >&2
  exit 1
}

# Linux x86 Boot Protocol header fields (boot protocol >= 2.08, universal
# since ~2009 and used by every DSM kernel arc supports):
#   0x1f1 setup_sects (u8)   - size of real-mode setup code, in 512B sectors
#   0x248 payload_offset (u32) - LZMA payload offset, relative to end of setup
#   0x24c payload_length (u32) - LZMA payload length, including its trailing
#                                4-byte little-endian uncompressed-size field
SETUP_SECTS="$(read_u8 "${ORI_ZIMAGE}" 0x1f1)"
[ "${SETUP_SECTS}" -eq 0 ] 2>/dev/null && SETUP_SECTS=4
PAYLOAD_OFFSET="$(read_u32 "${ORI_ZIMAGE}" 0x248)"
PAYLOAD_LENGTH="$(read_u32 "${ORI_ZIMAGE}" 0x24c)"
INNER_POS=$(((SETUP_SECTS + 1) * 512))
PAYLOAD_START=$((INNER_POS + PAYLOAD_OFFSET))

if [ -z "${PAYLOAD_OFFSET}" ] || [ -z "${PAYLOAD_LENGTH}" ] || [ "${PAYLOAD_LENGTH}" -le 4 ]; then
  echo "ERROR: could not parse bzImage boot header of ${ORI_ZIMAGE}" >&2
  exit 1
fi

# Recompress the patched vmlinux the same way the kernel build does for its
# own bzImage payload: raw LZMA stream, followed by the uncompressed size as
# a little-endian u32 trailer.
LZMA_TMP="$(mktemp "${TMP_PATH:-/tmp}/vmlinux-lzma.XXXXXX")"
trap 'rm -f "${LZMA_TMP}"' EXIT

xz --format=lzma -9e -c "${VMLINUX_MOD}" >"${LZMA_TMP}" || {
  echo "ERROR: lzma compression of ${VMLINUX_MOD} failed" >&2
  exit 1
}

VMLINUX_SIZE="$(stat -c%s "${VMLINUX_MOD}")"
LZMA_SIZE="$(stat -c%s "${LZMA_TMP}")"
NEW_PAYLOAD_LENGTH=$((LZMA_SIZE + 4))

# Hard capacity check: fail loudly instead of silently overflowing into
# adjacent bzImage structures, which is exactly what produced the
# triple-fault-with-no-output symptom in RROrg/rr#32166.
if [ "${NEW_PAYLOAD_LENGTH}" -gt "${PAYLOAD_LENGTH}" ]; then
  echo "ERROR: patched kernel payload (${NEW_PAYLOAD_LENGTH} bytes) does not fit" >&2
  echo "       in the original bzImage payload region (${PAYLOAD_LENGTH} bytes)." >&2
  echo "       Refusing to build a corrupt image." >&2
  exit 1
fi

# Start from a byte-for-byte copy of the genuine bzImage: setup code,
# decompressor stub and all other header fields are preserved untouched.
cp -f "${ORI_ZIMAGE}" "${ZIMAGE_MOD}" || exit 1

# Zero-pad the compressed payload out to the original region's length so
# every byte of the payload region is deterministically overwritten (no
# stale bytes left over from the previous, larger or smaller, payload).
{
  cat "${LZMA_TMP}"
  size_le "${VMLINUX_SIZE}"
  PAD=$((PAYLOAD_LENGTH - NEW_PAYLOAD_LENGTH))
  [ "${PAD}" -gt 0 ] && dd if=/dev/zero bs=1 count="${PAD}" 2>/dev/null
} | dd of="${ZIMAGE_MOD}" bs=1 seek="${PAYLOAD_START}" conv=notrunc 2>/dev/null || exit 1

rm -f "${LZMA_TMP}"
trap - EXIT

# ZIMAGE_MOD is a byte-for-byte copy of the genuine ORI_ZIMAGE with only the
# payload region overwritten - same total length, everything outside that
# region (setup code, decompressor stub, boot header, and any trailing
# container checksum the original image ships) is left exactly as shipped.
# kexec only reads the standard boot header, so nothing further to fix up.
