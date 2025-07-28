###################################################################################
# Check if addon is available for platform
# 1 - Addon
# 2 - Platform
function isAddonAvailable() {
  local ADDON="${1:-}"
  local PLATFORM="${2:-}"
  local MANIFEST="${ADDONS_PATH}/${ADDON}/manifest.yml"
  [ ! -f "${MANIFEST}" ] && return 1
  local AVAILABLE="$(readConfigKey "${PLATFORM}" "${MANIFEST}")"
  [ "${AVAILABLE}" = "true" ]
}

#################################################################################
# List available addons for a platform
# 1 - Platform
function availableAddons() {
  local PLATFORM="${1:-}"
  [ -z "${PLATFORM}" ] && return 1
  local MACHINE="$(virt-what 2>/dev/null | head -1)"
  [ -z "${MACHINE}" ] && MACHINE="physical"
  find "${ADDONS_PATH}" -maxdepth 1 -type d 2>/dev/null | sort | while read -r D; do
    [ ! -f "${D}/manifest.yml" ] && continue
    local ADDON="$(basename "${D}")"
    local SYSTEM="$(readConfigKey "system" "${D}/manifest.yml")"
    [ "${SYSTEM}" = "true" ] && continue
    isAddonAvailable "${ADDON}" "${PLATFORM}" || continue

    # Special platform/hardware checks
    if [ "${MACHINE}" != "physical" ] && [[ "${ADDON}" =~ ^(cpufreqscaling|fancontrol|ledcontrol)$ ]]; then
      continue
    fi

    local DESC="$(readConfigKey "description" "${D}/manifest.yml")"
    local BETA="$(readConfigKey "beta" "${D}/manifest.yml")"
    local TARGET="$(readConfigKey "target" "${D}/manifest.yml")"
    [ "${BETA}" = "true" ] && BETA="(Beta) " || BETA=""
    case "${TARGET}" in
      app)    echo -e "${ADDON}\t\Z4${BETA}${DESC}\Zn" ;;
      system) echo -e "${ADDON}\t\Z1${BETA}${DESC}\Zn" ;;
      *)      echo -e "${ADDON}\t${BETA}${DESC}" ;;
    esac
  done
}

#################################################################################
# Install Addon into ramdisk image
# 1 - Addon
# 2 - Platform
# 3 - Kernel version
function installAddon() {
  local ADDON="${1:-}"
  local PLATFORM="${2:-}"
  local KVER="${3:-}"
  [ -z "${ADDON}" ] && echo "ERROR: Addon not defined" && return 1
  isAddonAvailable "${ADDON}" "${PLATFORM}" || {
    deleteConfigKey "addon.${ADDON}" "${USER_CONFIG_FILE}"
    return 0
  }
  local TMP_ADDON="${TMP_PATH}/${ADDON}"
  mkdir -p "${TMP_ADDON}"
  local HAS_FILES=0
  for TGZ in "${ADDONS_PATH}/${ADDON}/all.tgz" "${ADDONS_PATH}/${ADDON}/${PLATFORM}-${KVER}.tgz"; do
    [ -f "${TGZ}" ] && tar -zxf "${TGZ}" -C "${TMP_ADDON}" 2>>"${LOG_FILE}" && HAS_FILES=1
  done
  [ "${HAS_FILES}" -ne 1 ] && deleteConfigKey "addon.${ADDON}" "${USER_CONFIG_FILE}" && rm -rf "${TMP_ADDON}" && return 0
  [ -f "${TMP_ADDON}/install.sh" ] && cp -f "${TMP_ADDON}/install.sh" "${RAMDISK_PATH}/addons/${ADDON}.sh" 2>>"${LOG_FILE}" && chmod +x "${RAMDISK_PATH}/addons/${ADDON}.sh"
  [ -d "${TMP_ADDON}/root" ] && cp -rnf "${TMP_ADDON}/root/"* "${RAMDISK_PATH}/" 2>>"${LOG_FILE}"
  rm -rf "${TMP_ADDON}"
  return 0
}

###############################################################################
# Detect if has new local plugins to install/reinstall
function updateAddon() {
  for F in $(ls ${ADDONS_PATH}/*.addon 2>/dev/null); do
    local ADDON=$(basename "${F}" | sed 's|.addon||')
    rm -rf "${ADDONS_PATH}/${ADDON}"
    mkdir -p "${ADDONS_PATH}/${ADDON}"
    tar -zxf "${F}" -C "${ADDONS_PATH}/${ADDON}"
    rm -f "${F}"
  done
}

###############################################################################
# Read Addon Key
# 1 - Addon
# 2 - key
function readAddonKey() {
  if [ -z "${1}" ] || [ -z "${2}" ]; then
    echo ""
    return 1
  fi
  if [ ! -f "${ADDONS_PATH}/${1}/manifest.yml" ]; then
    echo ""
    return 1
  fi
  readConfigKey "${2}" "${ADDONS_PATH}/${1}/manifest.yml"
}