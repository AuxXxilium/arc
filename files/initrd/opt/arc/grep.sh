#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh

if findAndMountDSMRoot; then
  if [ -f "${DSMROOT_PATH}/usr/log/dmesg.txt" ]; then
    cp -f "${DSMROOT_PATH}/usr/log/dmesg.txt" "/tmp/dmesg.txt"
    LOG="$(cat /tmp/dmesg.txt)"
    echo -e "${LOG}"
    echo
    echo "Logfile can be found at /tmp/dmesg.txt"
  else
    echo "Can't find Logfile"
  fi
else
  echo "Can't find DSM Partition"
fi
