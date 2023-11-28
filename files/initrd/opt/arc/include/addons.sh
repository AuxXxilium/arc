###############################################################################
# Return list of available addons
# 1 - Platform
# 2 - Kernel Version
function availableAddons() {
  while read -r D; do
    [ ! -f "${D}/manifest.yml" ] && continue
    ADDON=$(basename ${D})
    checkAddonExist "${ADDON}" "${1}" "${2}" || continue
    SYSTEM=$(readConfigKey "system" "${D}/manifest.yml")
    [ "${SYSTEM}" = "true" ] && continue
    while IFS=': ' read -r AVAILABLE; do
    [ "${AVAILABLE}" = "${1}-${2}" ] && ACTIVATE="true" && break || ACTIVATE="false"
    done < <(readConfigEntriesArray "available-for" "${D}/manifest.yml")
    [ "${ACTIVATE}" = "false" ] && continue
    DESC="$(readConfigKey "description" "${D}/manifest.yml")"
    BETA="$(readConfigKey "beta" "${D}/manifest.yml")"
    [ "${BETA}" = "true" ] && BETA="(Beta) " || BETA=""
    echo -e "${ADDON}\t${BETA}${DESC}"
  done < <(find "${ADDONS_PATH}" -maxdepth 1 -type d | sort)
}

###############################################################################
# Check if addon exist
# 1 - Addon id
# 2 - Platform
# 3 - Kernel Version
# Return ERROR if not exists
function checkAddonExist() {
  # First check generic files
  if [ -f "${ADDONS_PATH}/${1}/all.tgz" ]; then
    return 0 # OK
  fi
  # Now check specific platform file
  if [ -f "${ADDONS_PATH}/${1}/${2}-${3}.tgz" ]; then
    return 0 # OK
  fi
  return 1 # ERROR
}

###############################################################################
# Install Addon into ramdisk image
# 1 - Addon id
function installAddon() {
  ADDON="${1}"
  mkdir -p "${TMP_PATH}/${ADDON}"
  HAS_FILES=0
  # First check generic files
  if [ -f "${ADDONS_PATH}/${ADDON}/all.tgz" ]; then
    tar -zxf "${ADDONS_PATH}/${ADDON}/all.tgz" -C "${TMP_PATH}/${ADDON}"
    HAS_FILES=1
  fi
  # Now check specific platform files
  if [ -f "${ADDONS_PATH}/${ADDON}/${PLATFORM}-${KVER}.tgz" ]; then
    tar -zxf "${ADDONS_PATH}/${ADDON}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/${ADDON}"
    HAS_FILES=1
  fi
  # Check if addon is available for this platform
  while IFS=': ' read -r AVAILABLE; do
    [ "${AVAILABLE}" = "${PLATFORM}-${KVER}" ] && ACTIVATE="true" && break || ACTIVATE="false"
  done < <(readConfigEntriesArray "available-for" "${ADDONS_PATH}/${ADDON}/manifest.yml")
  # If has files to copy, copy it, else return error
  [[ ${HAS_FILES} -ne 1 || ${ACTIVATE} = "false" ]] && return 1
  cp -f "${TMP_PATH}/${ADDON}/install.sh" "${RAMDISK_PATH}/addons/${ADDON}.sh" 2>"${LOG_FILE}" || dieLog
  chmod +x "${RAMDISK_PATH}/addons/${ADDON}.sh"
  [ -d ${TMP_PATH}/${ADDON}/root ] && (cp -rnf "${TMP_PATH}/${ADDON}/root/"* "${RAMDISK_PATH}/" 2>"${LOG_FILE}" || dieLog)
  rm -rf "${TMP_PATH}/${ADDON:?}"
  return 0
}

###############################################################################
# Untar an addon to correct path
# 1 - Addon file path
# Return name of addon on sucess or empty on error
function untarAddon() {
  rm -rf "${TMP_PATH}/${ADDON:?}"
  mkdir -p "${TMP_PATH}/${ADDON}"
  tar -xaf "${1}" -C "${TMP_PATH}/${ADDON}" || return
  ADDON=$(readConfigKey "name" "${TMP_PATH}/${ADDON}/manifest.yml")
  [ -z "${ADDON}" ] && return
  rm -rf "${ADDONS_PATH}/${ADDON:?}"
  mv -f "${TMP_PATH}/${ADDON}" "${ADDONS_PATH}/${ADDON}"
  echo "${ADDON}"
}

###############################################################################
# Detect if has new local plugins to install/reinstall
function updateAddons() {
  for F in $(ls ${PART3_PATH}/*.addon 2>/dev/null); do
    ADDON=$(basename "${F}" | sed 's|.addon||')
    rm -rf "${ADDONS_PATH}/${ADDON:?}"
    mkdir -p "${ADDONS_PATH}/${ADDON}"
    echo "Installing ${F} to ${ADDONS_PATH}/${ADDON}"
    tar -xaf "${F}" -C "${ADDONS_PATH}/${ADDON}"
    rm -f "${F}"
  done
}