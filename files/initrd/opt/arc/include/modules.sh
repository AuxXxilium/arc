#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

###############################################################################
# Unpack modules from a tgz file
# 1 - Platform
# 2 - Kernel Version
# 3 - Path
function unpackModules() {
  local PLATFORM="${1}"
  local KVERP="${2}"
  local UNPATH=${3:-"${TMP_PATH}/modules"}
  local KERNEL
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  rm -rf "${UNPATH}"
  mkdir -p "${UNPATH}"
  if [ "${KERNEL}" = "legacy" ] || [ "${KERNEL}" = "upstreamed" ]; then
    tar -zxf "${CUSTOM_PATH}/modules-${PLATFORM}-${KVERP}-${KERNEL}.tgz" -C "${UNPATH}"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz" -C "${UNPATH}"
  fi
}

###############################################################################
# Pack modules to a tgz file
# 1 - Platform
# 2 - Kernel Version
# 3 - Path
function packModules() {
  local PLATFORM=${1}
  local KVERP=${2}
  local KERNEL
  local UNPATH=${3:-"${TMP_PATH}/modules"}
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  if [ "${KERNEL}" = "legacy" ] || [ "${KERNEL}" = "upstreamed" ]; then
    tar -zcf "${CUSTOM_PATH}/modules-${PLATFORM}-${KVERP}-${KERNEL}.tgz" -C "${UNPATH}" .
  else
    tar -zcf "${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz" -C "${UNPATH}" .
  fi
}

###############################################################################
# Search order of module folders inside a modules tgz.
# "update" comes first, it takes precedence over the root folder just like
# the kernel does, so a module shipped in both is resolved to the newer one.
MODULE_DIRS=("update" "")

###############################################################################
# Resolve a module name to its file inside an unpacked modules folder
# Accepts a bare name (drm), a folder prefixed name (update/drm) and an
# optional .ko suffix. Prints the path of the first match, empty if none.
# 1 - Unpacked modules path
# 2 - Module name
function resolveModule() {
  local UNPATH="${1}"
  local KONAME="${2}"

  [ -z "${UNPATH}" ] || [ -z "${KONAME}" ] && return 0
  KONAME="$(basename "${KONAME}" .ko)"
  for D in "${MODULE_DIRS[@]}"; do
    if [ -f "${UNPATH}/${D:+${D}/}${KONAME}.ko" ]; then
      echo "${UNPATH}/${D:+${D}/}${KONAME}.ko"
      return 0
    fi
  done
  return 0
}

###############################################################################
# Resolve a module name to the name used in the module list, that is the
# name including its folder prefix (i915 -> update/i915). Falls back to the
# plain name if the module is not part of the tgz.
# 1 - Unpacked modules path
# 2 - Module name
function moduleName() {
  local UNPATH="${1}"
  local KONAME="${2}"
  local KOFILE

  [ -z "${UNPATH}" ] || [ -z "${KONAME}" ] && return 0
  KONAME="$(basename "${KONAME}" .ko)"
  KOFILE="$(resolveModule "${UNPATH}" "${KONAME}")"
  if [ -n "${KOFILE}" ]; then
    # strip the unpack path and the .ko suffix, keep a leading update/
    KOFILE="${KOFILE#${UNPATH}/}"
    echo "${KOFILE%.ko}"
  else
    echo "${KONAME}"
  fi
  return 0
}

###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
function getAllModules() {
  local PLATFORM=${1}
  local KVERP=${2}

  if [ -z "${PLATFORM}" ] || [ -z "${KVERP}" ]; then
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${KVERP}"

  for D in "${MODULE_DIRS[@]}"; do
    for F in $(LC_ALL=C printf '%s\n' ${UNPATH}/${D:+${D}/}*.ko | sort -V); do
      [ ! -e "${F}" ] && continue
      local N DESC
      N="$(basename "${F}" .ko)"
      DESC="$(modinfo -F description "${F}" 2>/dev/null)"
      DESC="$(echo "${DESC}" | tr -d '\n\r\t\\' | sed "s/\"/'/g" | sed -E 's/\(Compiled by RR for DSM\)//g')"
      echo "${D:+${D}/}${N} \"${DESC:-${D:+${D}/}${N}}\""
    done
  done
  rm -rf "${TMP_PATH}/modules"
}

###############################################################################
# Return list of loaded modules
# 1 - Platform
# 2 - Kernel Version
function getLoadedModules() {
  local PLATFORM=${1}
  local PKVER=${2}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ]; then
    return 1
  fi

  UNPATH="${TMP_PATH}/lib/modules/$(uname -r)"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"
  depmod -a -b "${TMP_PATH}" >/dev/null 2>&1

  ALL_KO=$(
    find /sys/devices -name modalias -exec cat {} \; | while read -r modalias; do
      modprobe -d "${TMP_PATH}" --resolve-alias "${modalias}" 2>/dev/null
    done | sort -u
  )
  rm -rf "${UNPATH}"

  ALL_DEPS=""
  for M in ${ALL_KO}; do
    ALL_DEPS="${ALL_DEPS} $(getdepends "${PLATFORM}" "${PKVER}" "${M}")"
  done

  echo "${ALL_DEPS}" | tr ' ' '\n' | grep -v '^$' | sort -u
  return 0
}

###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
# 3 - Module list
function installModules() {
  local PLATFORM=${1}
  local KVERP=${2}

  if [ -z "${PLATFORM}" ] || [ -z "${KVERP}" ]; then
    echo "ERROR: Platform or Kernel Version not defined" >"${LOG_FILE}"
    return 1
  fi
  local MLIST ODP
  shift 2
  MLIST="${*}"

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${KVERP}"

  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  for D in "${MODULE_DIRS[@]}"; do
    for F in $(LC_ALL=C printf '%s\n' ${UNPATH}/${D:+${D}/}*.ko | sort -V); do
      [ ! -e "${F}" ] && continue
      M=$(basename "${F}")
      [ "${ODP}" = "true" ] && [ -f "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}${M}" ] && continue
      # exact token match, a selected update/drm must not also pull in the
      # older root drm ("grep -w" would treat the slash as a word boundary)
      if [[ " ${MLIST} " == *" ${D:+${D}/}$(basename "${M}" .ko) "* ]]; then
        mkdir -p "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}"
        cp -f "${F}" "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}${M}" 2>>"${LOG_FILE}"
      else
        rm -f "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}${M}" 2>>"${LOG_FILE}"
      fi
    done
  done

  mkdir -p "${RAMDISK_PATH}/usr/lib/firmware"
  tar -zxf "${MODULES_PATH}/firmware.tgz" -C "${RAMDISK_PATH}/usr/lib/firmware" 2>"${LOG_FILE}"
  if [ $? -ne 0 ]; then
    return 1
  fi

  rm -rf "${TMP_PATH}/modules"
  return 0
}

###############################################################################
# add a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko file
function addToModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local KOFILE=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ] || [ -z "${KOFILE}" ]; then
    echo ""
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  # replace in place if the module already exists, so a ko shipped in
  # update/ keeps its precedence instead of being shadowed by a root copy
  local TARGET
  TARGET="$(resolveModule "${UNPATH}" "$(basename "${KOFILE}")")"
  if [ -n "${TARGET}" ]; then
    cp -f "${KOFILE}" "${TARGET}"
  else
    cp -f "${KOFILE}" "${UNPATH}"
  fi

  packModules "${PLATFORM}" "${PKVER}" "${UNPATH}"
}

###############################################################################
# del a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function delToModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  # drop every copy, removing only the update/ one would bring the older
  # root module back into play
  KONAME="$(basename "${KONAME}" .ko)"
  for D in "${MODULE_DIRS[@]}"; do
    rm -f "${UNPATH}/${D:+${D}/}${KONAME}.ko"
  done

  packModules "${PLATFORM}" "${PKVER}" "${UNPATH}"
}

###############################################################################
# get depends of ko
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function getdepends() {
  # resolves each module through MODULE_DIRS, so dependencies living in
  # update/ are followed and shadowed ones are read from the newer copy.
  # Names are printed with the folder prefix they were resolved to, that is
  # what getAllModules stores and what installModules matches against.
  function _getdepends() {
    local KOFILE NAME depends k
    KOFILE="$(resolveModule "${UNPATH}" "${1}")"
    [ -z "${KOFILE}" ] && return 0
    NAME="$(basename "${1}" .ko)"
    # guard against dependency cycles
    case " ${_SEEN_KO} " in
      *" ${NAME} "*) return 0 ;;
    esac
    _SEEN_KO="${_SEEN_KO} ${NAME}"
    depends="$(modinfo -F depends "${KOFILE}" 2>/dev/null | sed 's/,/\n/g')"
    if [ "$(echo "${depends}" | wc -w)" -gt 0 ]; then
      for k in ${depends}; do
        moduleName "${UNPATH}" "${k}"
        _getdepends "${k}"
      done
    fi
  }

  local PLATFORM=${1}
  local PKVER=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  _SEEN_KO=""
  _getdepends "${KONAME}" | sort -u
  moduleName "${UNPATH}" "${KONAME}"
  rm -rf "${UNPATH}"
}