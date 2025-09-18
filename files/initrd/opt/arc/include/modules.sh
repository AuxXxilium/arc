###############################################################################
# Unpack modules from a tgz file
# 1 - Platform
# 2 - Kernel Version
function unpackModules() {
  local PLATFORM=${1}
  local KVERP=${2}
  local KERNEL
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CUSTOM_PATH}/modules-${PLATFORM}-${KVERP}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz" -C "${TMP_PATH}/modules"
  fi
}

###############################################################################
# Packag modules to a tgz file
# 1 - Platform
# 2 - Kernel Version
function packModules() {
  local PLATFORM=${1}
  local KVERP=${2}
  local KERNEL
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  if [ "${KERNEL}" = "custom" ]; then
    tar -zcf "${CUSTOM_PATH}/modules-${PLATFORM}-${KVERP}.tgz" -C "${TMP_PATH}/modules" .
  else
    tar -zcf "${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz" -C "${TMP_PATH}/modules" .
  fi
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

  unpackModules "${PLATFORM}" "${KVERP}"

  # Get list of all modules
  for F in $(ls ${TMP_PATH}/modules/*.ko 2>/dev/null); do
    [ ! -e "${F}" ] && continue
    local N DESC
    N="$(basename "${F}" .ko)"
    DESC="$(modinfo -F description "${F}" 2>/dev/null)"
    DESC="$(echo "${DESC}" | sed -E 's/[\n]/ /g' | sed -E 's/\(Compiled by RR for DSM\)//g')"
    echo "${N} \"${DESC:-${N}}\""
  done
  rm -rf "${TMP_PATH}/modules"
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
  local MLIST ODP KERNEL
  shift 2
  MLIST="${*}"

  unpackModules "${PLATFORM}" "${KVERP}"

  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  for F in ${TMP_PATH}/modules/*.ko; do
    [ ! -e "${F}" ] && continue
    M=$(basename "${F}")
    [ "${ODP}" = "true" ] && [ -f "${RAMDISK_PATH}/usr/lib/modules/${M}" ] && continue
    if echo "${MLIST}" | grep -wq "$(basename "${M}" .ko)"; then
      cp -f "${F}" "${RAMDISK_PATH}/usr/lib/modules/${M}" 2>"${LOG_FILE}"
    else
      rm -f "${RAMDISK_PATH}/usr/lib/modules/${M}" 2>"${LOG_FILE}"
    fi
  done

  mkdir -p "${RAMDISK_PATH}/usr/lib/firmware"
  KERNEL=$(readConfigKey "kernel" "${USER_CONFIG_FILE}")
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CUSTOM_PATH}/firmware.tgz" -C "${RAMDISK_PATH}/usr/lib/firmware" 2>"${LOG_FILE}"
  else
    tar -zxf "${MODULES_PATH}/firmware.tgz" -C "${RAMDISK_PATH}/usr/lib/firmware" 2>"${LOG_FILE}"
  fi
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
  local KVERP=${2}
  local KOFILE=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${KVERP}" ] || [ -z "${KOFILE}" ]; then
    echo ""
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVERP}"

  cp -f "${KOFILE}" "${TMP_PATH}/modules"

  packModules "${PLATFORM}" "${KVERP}"
}

###############################################################################
# del a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function delToModules() {
  local PLATFORM=${1}
  local KVERP=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${KVERP}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVERP}"

  rm -f "${TMP_PATH}/modules/${KONAME}"

  packModules "${PLATFORM}" "${KVERP}"
}

###############################################################################
# get depends of ko
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function getdepends() {
  function _getdepends() {
    if [ -f "${TMP_PATH}/modules/${1}.ko" ]; then
      local depends
      depends="$(modinfo -F depends "${TMP_PATH}/modules/${1}.ko" 2>/dev/null | sed 's/,/\n/g')"
      if [ "$(echo "${depends}" | wc -w)" -gt 0 ]; then
        for k in ${depends}; do
          echo "${k}"
          _getdepends "${k}"
        done
      fi
    fi
  }

  local PLATFORM=${1}
  local KVERP=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${KVERP}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVERP}"

  _getdepends "${KONAME}" | sort -u
  echo "${KONAME}"
  rm -rf "${TMP_PATH}/modules"
}