[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" 2>/dev/null && pwd)"

. ${ARC_PATH}/include/consts.sh

###############################################################################
# Update Loader
function updateLoader() {
  (
    local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
    local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl  --interface ${ARCNIC} -m 5 -skL https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ -n "${TAG}" ]; then
          echo "New Version: ${TAG}"
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
      if [ -z "${TAG}" ]; then
        echo "Error checking new Version!"
        sleep 5
        updateFailed
      fi
    else
      TAG="${1}"
    fi
    # Download update file
    echo "Downloading ${TAG}"
    curl --interface ${ARCNIC} -#kL "https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip" -o "${TMP_PATH}/update.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "Download:$progress" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
    done
    curl --interface ${ARCNIC} -skL "https://github.com/AuxXxilium/arc/releases/download/${TAG}/checksum.sha256" -o "${TMP_PATH}/checksum.sha256"
    if [ "$(sha256sum "${TMP_PATH}/update.zip" | awk '{print $1}')" = "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
      echo "Download successful!"
      unzip -oq "${TMP_PATH}/update.zip" -d "${TMP_PATH}"
      echo "Installing new Loader Image..."
      cp -f "${TMP_PATH}/grub.cfg" "${USER_GRUB_CONFIG}"
      cp -f "${TMP_PATH}/bzImage-arc" "${ARC_BZIMAGE_FILE}"
      cp -f "${TMP_PATH}/initrd-arc" "${ARC_RAMDISK_FILE}"
      rm -f "${TMP_PATH}/grub.cfg" "${TMP_PATH}/bzImage-arc" "${TMP_PATH}/initrd-arc"
      rm -f "${TMP_PATH}/update.zip"
    else
      echo "Error getting new Version!"
      sleep 5
      updateFailed
    fi
    [ -f "${TMP_PATH}/update.zip" ] && rm -f "${TMP_PATH}/update.zip"
    echo "Update done!"
    sleep 2
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Loader" \
    --progressbox "Updating Loader..." 20 70
  return 0
}

###############################################################################
# Update Addons
function updateAddons() {
  (
    local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
    local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --interface ${ARCNIC} -m 5 -skL https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ -n "${TAG}" ]; then
          echo "New Version: ${TAG}"
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
      if [ -z "${TAG}" ]; then
        echo "Error checking new Version!"
        sleep 5
        updateFailed
      fi
    else
      TAG="${1}"
    fi
    # Download update file
    echo "Downloading ${TAG}"
    curl --interface ${ARCNIC} -#kL "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o "${TMP_PATH}/addons.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "Download:$progress" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
    done
    curl --interface ${ARCNIC} -skL "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/checksum.sha256" -o "${TMP_PATH}/checksum.sha256"
    if [ "$(sha256sum "${TMP_PATH}/addons.zip" | awk '{print $1}')" = "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
      echo "Download successful!"
      rm -rf "${ADDONS_PATH}"
      mkdir -p "${ADDONS_PATH}"
      echo "Installing new Addons..."
      unzip -oq "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}"
      rm -f "${TMP_PATH}/addons.zip"
      for F in $(ls ${ADDONS_PATH}/*.addon 2>/dev/null); do
        ADDON=$(basename "${F}" | sed 's|.addon||')
        rm -rf "${ADDONS_PATH}/${ADDON}"
        mkdir -p "${ADDONS_PATH}/${ADDON}"
        echo "Installing ${F} to ${ADDONS_PATH}/${ADDON}"
        tar -xaf "${F}" -C "${ADDONS_PATH}/${ADDON}"
        rm -f "${F}"
      done
    else
      echo "Error getting new Version!"
      sleep 5
      updateFailed
    fi
    echo "Update done!"
    sleep 2
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Addons" \
    --progressbox "Updating Addons..." 20 70
  return 0
}

###############################################################################
# Update Patches
function updatePatches() {
  (
    local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
    local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --interface ${ARCNIC} -m 5 -skL https://api.github.com/repos/AuxXxilium/arc-patches/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ -n "${TAG}" ]; then
          echo "New Version: ${TAG}"
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
      if [ -z "${TAG}" ]; then
        echo "Error checking new Version!"
        sleep 5
        updateFailed
      fi
    else
      TAG="${1}"
    fi
    # Download update file
    echo "Downloading ${TAG}"
    curl --interface ${ARCNIC} -#kL "https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches.zip" -o "${TMP_PATH}/patches.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "Download:$progress" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
    done
    curl --interface ${ARCNIC} -skL "https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/checksum.sha256" -o "${TMP_PATH}/checksum.sha256"
    if [ "$(sha256sum "${TMP_PATH}/patches.zip" | awk '{print $1}')" = "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
      echo "Download successful!"
      rm -rf "${PATCH_PATH}"
      mkdir -p "${PATCH_PATH}"
      echo "Installing new Patches..."
      unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}"
      rm -f "${TMP_PATH}/patches.zip"
    else
      echo "Error extracting new Version!"
      sleep 5
      updateFailed
    fi
    echo "Update done!"
    sleep 2
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Patches" \
    --progressbox "Updating Patches..." 20 70
  return 0
}

###############################################################################
# Update Modules
function updateModules() {
  (
    local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
    local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --interface ${ARCNIC} -m 5 -skL https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ -n "${TAG}" ]; then
          echo "New Version: ${TAG}"
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
      if [ -z "${TAG}" ]; then
        echo "Error checking new Version!"
        sleep 5
        updateFailed
      fi
    else
      TAG="${1}"
    fi
    # Download update file
    echo "Downloading ${TAG}"
    curl --interface ${ARCNIC} -#kL "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "${TMP_PATH}/modules.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "Download:$progress" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
    done
    curl --interface ${ARCNIC} -skL "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/checksum.sha256" -o "${TMP_PATH}/checksum.sha256"
    if [ "$(sha256sum "${TMP_PATH}/modules.zip" | awk '{print $1}')" = "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
      echo "Download successful!"
      rm -rf "${MODULES_PATH}"
      mkdir -p "${MODULES_PATH}"
      echo "Installing new Modules..."
      unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}"
      rm -f "${TMP_PATH}/modules.zip"
      # Rebuild modules if model/build is selected
      local PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
      if [ -n "${PRODUCTVER}" ]; then
        local PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
        local KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.[${PRODUCTVER}].kver" "${P_FILE}")"
        # Modify KVER for Epyc7002
        if [ "${PLATFORM}" = "epyc7002" ]; then
          KVERP="${PRODUCTVER}-${KVER}"
        else
          KVERP="${KVER}"
        fi
      fi
      if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        echo "Rebuilding Modules..."
        while read -r ID DESC; do
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done < <(getAllModules "${PLATFORM}" "${KVERP}")
      fi
    else
      echo "Error getting new Version!"
      sleep 5
      updateFailed
    fi
    echo "Update done!"
    sleep 2
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Modules" \
    --progressbox "Updating Modules..." 20 70
  return 0
}

###############################################################################
# Update Configs
function updateConfigs() {
  (
    local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
    local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --interface ${ARCNIC} -m 5 -skL https://api.github.com/repos/AuxXxilium/arc-configs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ -n "${TAG}" ]; then
          echo "New Version: ${TAG}"
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
      if [ -z "${TAG}" ]; then
        echo "Error checking new Version!"
        sleep 5
        updateFailed
      fi
    else
      TAG="${1}"
    fi
    # Download update file
    echo "Downloading ${TAG}"
    curl --interface ${ARCNIC} -#kL "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip" -o "${TMP_PATH}/configs.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "Download:$progress" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
    done
    curl --interface ${ARCNIC} -skL "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/checksum.sha256" -o "${TMP_PATH}/checksum.sha256"
    if [ "$(sha256sum "${TMP_PATH}/configs.zip" | awk '{print $1}')" = "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
      echo "Download successful!"
      rm -rf "${MODEL_CONFIG_PATH}"
      mkdir -p "${MODEL_CONFIG_PATH}"
      echo "Installing new Configs..."
      unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}"
      rm -f "${TMP_PATH}/configs.zip"
    else
      echo "Error getting new Version!"
      sleep 5
      updateFailed
    fi
    echo "Update done!"
    sleep 2
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Configs" \
    --progressbox "Updating Configs..." 20 70
  return 0
}

###############################################################################
# Update LKMs
function updateLKMs() {
  (
    local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
    local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --interface ${ARCNIC} -m 5 -skL https://api.github.com/repos/AuxXxilium/arc-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
        if [ -n "${TAG}" ]; then
          echo "New Version: ${TAG}"
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
      if [ -z "${TAG}" ]; then
        echo "Error checking new Version!"
        sleep 5
        updateFailed
      fi
    else
      TAG="${1}"
    fi
    # Download update file
    echo "Downloading ${TAG}"
    curl --interface ${ARCNIC} -#kL "https://github.com/AuxXxilium/arc-lkm/releases/download/${TAG}/rp-lkms.zip" -o "${TMP_PATH}/rp-lkms.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "Download:$progress" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
    done
    if [ -f "${TMP_PATH}/rp-lkms.zip" ]; then
      echo "Download successful!"
      rm -rf "${LKMS_PATH}"
      mkdir -p "${LKMS_PATH}"
      echo "Installing new LKMs..."
      unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKMS_PATH}"
      rm -f "${TMP_PATH}/rp-lkms.zip"
    else
      echo "Error getting new Version!"
      sleep 5
      updateFailed
    fi
    echo "Update done!"
    sleep 2
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update LKMs" \
    --progressbox "Updating LKMs..." 20 70
  return 0
}

###############################################################################
# Update Failed
function updateFailed() {
  local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
  if [ "${CUSTOM}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Failed" \
      --infobox "Update failed!" 0 0
    sleep 5
    exec reboot
  else
    dialog --backtitle "$(backtitle)" --title "Update Failed" \
      --msgbox "Update failed!" 0 0
    exit 1
  fi
}