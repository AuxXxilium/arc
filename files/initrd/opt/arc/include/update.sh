
###############################################################################
# Update Loader
function updateLoader() {
  (
    local CUSTOM="$(readConfigKey "arc.custom" "${USER_CONFIG_FILE}")"
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
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
    STATUS="$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip" -o "${TMP_PATH}/update.zip")"
    echo "Extract Updatefile..."
    unzip -oq "${TMP_PATH}/update.zip" -d "${TMP_PATH}"
    rm -f "${TMP_PATH}/update.zip"
    echo "Installing new Loader Image..."
    if [ -f "${TMP_PATH}/bzImage-arc" ] && [ -f "${TMP_PATH}/initrd-arc" ]; then
      # Process complete update
      cp -f "${TMP_PATH}/grub.cfg" "${GRUB_PATH}/grub.cfg"
      cp -f "${TMP_PATH}/bzImage-arc" "${ARC_BZIMAGE_FILE}"
      cp -f "${TMP_PATH}/initrd-arc" "${ARC_RAMDISK_FILE}"
    else
      echo "Error extracting new Version!"
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
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
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
    STATUS="$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o "${TMP_PATH}/addons.zip")"
    rm -rf "${ADDONS_PATH}"
    mkdir -p "${ADDONS_PATH}"
    echo "Installing new Addons..."
    unzip -oq "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}"
    if [ -f "${TMP_PATH}/addons.zip" ]; then
      rm -f "${TMP_PATH}/addons.zip"
    else
      echo "Error extracting new Version!"
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
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-patches/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
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
    STATUS="$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches.zip" -o "${TMP_PATH}/patches.zip")"
    rm -rf "${PATCH_PATH}"
    mkdir -p "${PATCH_PATH}"
    echo "Installing new Patches..."
    unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}"
    if [ -f "${TMP_PATH}/patches.zip" ]; then
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
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
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
    STATUS="$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "${TMP_PATH}/modules.zip")"
    rm -rf "${MODULES_PATH}"
    mkdir -p "${MODULES_PATH}"
    echo "Installing new Modules..."
    unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}"
    if [ -f "${TMP_PATH}/modules.zip" ]; then
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
      echo "Error extracting new Version!"
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
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-configs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
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
    STATUS="$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip" -o "${TMP_PATH}/configs.zip")"
    rm -rf "${MODEL_CONFIG_PATH}"
    mkdir -p "${MODEL_CONFIG_PATH}"
    echo "Installing new Configs..."
    unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}"
    if [ -f "${TMP_PATH}/configs.zip" ]; then
      rm -f "${TMP_PATH}/configs.zip"
    else
      echo "Error extracting new Version!"
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
    if [ -z "${1}" ]; then
      # Check for new Version
      idx=0
      while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
        TAG="$(curl --insecure -m 5 -s https://api.github.com/repos/AuxXxilium/arc-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
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
    STATUS="$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-lkm/releases/download/${TAG}/rp-lkms-${TAG}.zip" -o "${TMP_PATH}/rp-lkms.zip")"
    rm -rf "${LKM_PATH}"
    mkdir -p "${LKM_PATH}"
    echo "Installing new LKMs..."
    unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKM_PATH}"
    if [ -f "${TMP_PATH}/rp-lkms.zip" ]; then
      rm -f "${TMP_PATH}/rp-lkms.zip"
    else
      echo "Error extracting new Version!"
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
  dialog --backtitle "$(backtitle)" --title "Update Failed" \
    --infobox "Update failed!" 0 0
  sleep 10
  exec reboot
}