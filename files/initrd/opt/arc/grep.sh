#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh

if findAndMountDSMRoot; then
  if [ -f "${DSMROOT_PATH}/usr/log/dmesg.txt" ]; then
    LOG="$(cat ${DSMROOT_PATH}/usr/log/dmesg.txt)"
    echo -e "${LOG}"
  else
    echo "Can't find Logfile"
  fi
else
  echo "Can't find DSM Partition"
fi
