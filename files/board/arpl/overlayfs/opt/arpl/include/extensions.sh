###############################################################################
# Return list of available Extensions
# 1 - Platform
# 2 - Kernel Version
function availableExtensions() {
  while read -r D; do
    [ ! -f "${D}/manifest.yml" ] && continue
    EXTENSION=$(basename ${D})
    checkExtensionExist "${EXTENSION}" "${1}" "${2}" || continue
    while IFS=': ' read -r AVAILABLE; do
    [ "${AVAILABLE}" = "${1}-${2}" ] && ACTIVATE="true" && break || ACTIVATE="false"
    done < <(readConfigEntriesArray "available-for" "${D}/manifest.yml")
    [ "${ACTIVATE}" = "false" ] && continue
    DESC="$(readConfigKey "description" "${D}/manifest.yml")"
    echo -e "${EXTENSION}\t${DESC}"
  done < <(find "${EXTENSIONS_PATH}" -maxdepth 1 -type d | sort)
}

###############################################################################
# Check if extension exist
# 1 - Extension id
# 2 - Platform
# 3 - Kernel Version
# Return ERROR if not exists
function checkExtensionExist() {
  # First check generic files
  if [ -f "${EXTENSIONS_PATH}/${1}/all.tgz" ]; then
    return 0 # OK
  fi
  # Now check specific platform file
  if [ -f "${EXTENSIONS_PATH}/${1}/${2}-${3}.tgz" ]; then
    return 0 # OK
  fi
  return 1 # ERROR
}

###############################################################################
# Install Extension into ramdisk image
# 1 - Extension id
function installExtension() {
  EXTENSION="${1}"
  mkdir -p "${TMP_PATH}/${EXTENSION}"
  HAS_FILES=0
  # First check generic files
  if [ -f "${EXTENSIONS_PATH}/${EXTENSION}/all.tgz" ]; then
    tar -zxf "${EXTENSIONS_PATH}/${EXTENSION}/all.tgz" -C "${TMP_PATH}/${EXTENSION}"
    HAS_FILES=1
  fi
  # Now check specific platform files
  if [ -f "${EXTENSIONS_PATH}/${EXTENSION}/${PLATFORM}-${KVER}.tgz" ]; then
    tar -zxf "${EXTENSIONS_PATH}/${EXTENSION}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/${EXTENSION}"
    HAS_FILES=1
  fi
  # Check if extension is available for this platform
  while IFS=': ' read -r AVAILABLE; do
    [ "${AVAILABLE}" = "${PLATFORM}-${KVER}" ] && ACTIVATE="true" && break || ACTIVATE="false"
  done < <(readConfigEntriesArray "available-for" "${EXTENSIONS_PATH}/${EXTENSION}/manifest.yml")
  # If has files to copy, copy it, else return error
  [ ${HAS_FILES} -ne 1 ] || [ ${ACTIVATE} = "false" ] && return 1
  cp "${TMP_PATH}/${EXTENSION}/install.sh" "${RAMDISK_PATH}/addons/${EXTENSION}.sh" 2>"${LOG_FILE}" || dieLog
  chmod +x "${RAMDISK_PATH}/addons/${EXTENSION}.sh"
  [ -d ${TMP_PATH}/${EXTENSION}/root ] && (cp -R "${TMP_PATH}/${EXTENSION}/root/"* "${RAMDISK_PATH}/" 2>"${LOG_FILE}" || dieLog)
  #rm -rf "${TMP_PATH}/${EXTENSION}"
  return 0
}

###############################################################################
# Untar an extension to correct path
# 1 - Extension file path
# Return name of extension on sucess or empty on error
function untarExtension() {
  rm -rf "${TMP_PATH}/extension"
  mkdir -p "${TMP_PATH}/extension"
  tar -xaf "${1}" -C "${TMP_PATH}/extension" || return
  EXTENSION=$(readConfigKey "name" "${TMP_PATH}/extension/manifest.yml")
  [ -z "${EXTENSION}" ] && return
  rm -rf "${EXTENSIONS_PATH}/${EXTENSION}"
  mv "${TMP_PATH}/extension" "${EXTENSIONS_PATH}/${EXTENSION}"
  echo "${EXTENSION}"
}