###############################################################################
# Update Loader
function updateLoader() {
  local ARC_BRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
  local TAG="${1}"
  if [ -z "${TAG}" ]; then
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARC_BRANCH}" == "dev" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | grep "dev" | sort -rV | head -1)"
      else
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  fi
  if [ -n "${TAG}" ]; then
    (
      echo "Downloading ${TAG}"
      local URL="https://github.com/AuxXxilium/arc/releases/download/${TAG}/update-${TAG}-${ARC_BRANCH}.zip"
      curl -#kL "${URL}" -o "${TMP_PATH}/update.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/update.zip" ]; then
        echo -e "Downloading ${TAG}-${ARC_BRANCH} Loader successful!\nUpdating ${ARC_BRANCH} Loader..."
        if unzip -oq "${TMP_PATH}/update.zip" -d "/mnt"; then
          echo "Successful!"
          echo "${TAG}" > "${PART1_PATH}/VERSION"
          sleep 2
        else
          updateFailed
        fi
      else
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "System" \
      --progressbox "Update ${ARC_BRANCH} Loader..." 20 70
  fi
  return 0
}

###############################################################################
# Update Addons
function updateAddons() {
  [ -f "${ADDONS_PATH}/VERSION" ] && local ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")" || ADDONSVERSION="0.0.0"
  idx=0
  while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
    local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ] && [ "${ADDONSVERSION}" != "${TAG}" ]; then
    (
      echo "Downloading ${TAG}"
      local URL="https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons-${TAG}.zip"
      curl -#kL "${URL}" -o "${TMP_PATH}/addons.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/addons.zip" ]; then
        rm -rf "${ADDONS_PATH}"
        mkdir -p "${ADDONS_PATH}"
        echo "Installing new Addons..."
        if unzip -oq "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}"; then
          rm -f "${TMP_PATH}/addons.zip"
          for F in $(ls ${ADDONS_PATH}/*.addon 2>/dev/null); do
            ADDON=$(basename "${F}" | sed 's|.addon||')
            rm -rf "${ADDONS_PATH}/${ADDON}"
            mkdir -p "${ADDONS_PATH}/${ADDON}"
            tar -xaf "${F}" -C "${ADDONS_PATH}/${ADDON}"
            rm -f "${F}"
          done
          echo "Successful!"
        else
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Addons" \
      --progressbox "Update Addons..." 20 70
  fi
  return 0
}

###############################################################################
# Update Patches
function updatePatches() {
  [ -f "${PATCH_PATH}/VERSION" ] && local PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")" || PATCHESVERSION="0.0.0"
  idx=0
  while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
    local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ] && [ "${PATCHESVERSION}" != "${TAG}" ]; then
    (
      local URL="https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches-${TAG}.zip"
      echo "Downloading ${TAG}"
      curl -#kL "${URL}" -o "${TMP_PATH}/patches.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/patches.zip" ]; then
        rm -rf "${PATCH_PATH}"
        mkdir -p "${PATCH_PATH}"
        echo "Installing new Patches..."
        if unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}"; then
          rm -f "${TMP_PATH}/patches.zip"
          echo "Successful!"
        else
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Patches" \
      --progressbox "Update Patches..." 20 70
  fi
  return 0
}

###############################################################################
# Update Custom
function updateCustom() {
  [ -f "${CUSTOM_PATH}/VERSION" ] && local CUSTOMVERSION="$(cat "${CUSTOM_PATH}/VERSION")" || CUSTOMVERSION="0.0.0"
  idx=0
  while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
    local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ] && [ "${CUSTOMVERSION}" != "${TAG}" ]; then
    (
      local URL="https://github.com/AuxXxilium/arc-custom/releases/download/${TAG}/custom-${TAG}.zip"
      echo "Downloading ${TAG}"
      curl -#kL "${URL}" -o "${TMP_PATH}/custom.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/custom.zip" ]; then
        rm -rf "${CUSTOM_PATH}"
        mkdir -p "${CUSTOM_PATH}"
        echo "Installing new Custom Kernel..."
        if unzip -oq "${TMP_PATH}/custom.zip" -d "${CUSTOM_PATH}"; then
          rm -f "${TMP_PATH}/custom.zip"
          echo "Successful!"
        else
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Custom" \
      --progressbox "Update Custom..." 20 70
  fi
  return 0
}

###############################################################################
# Update Modules
function updateModules() {
  [ -f "${MODULES_PATH}/VERSION" ] && local MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")" || MODULESVERSION="0.0.0"
  local PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  local PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  local KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  [ "${PLATFORM}" == "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
  idx=0
  while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
    local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ] && [[ "${MODULESVERSION}" != "${TAG}" || ! -f "${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz" ]]; then
    (
      rm -rf "${MODULES_PATH}"
      mkdir -p "${MODULES_PATH}"
      local URL="https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules-${TAG}.zip"
      echo "Downloading Modules ${TAG}"
      curl -#kL "${URL}" -o "${TMP_PATH}/modules.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/modules.zip" ]; then
        echo "Installing new Modules..."
        if unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}"; then
          rm -f "${TMP_PATH}/modules.zip"
          echo "Successful!"
        else
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
      if [ -f "${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz" ] && [ -f "${MODULES_PATH}/firmware.tgz" ]; then
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        echo "Rebuilding Modules..."
        while read -r ID DESC; do
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done < <(getAllModules "${PLATFORM}" "${KVERP}")
        echo "Successful!"
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Modules" \
      --progressbox "Update Modules..." 20 70
  fi
  return 0
}

###############################################################################
# Update Configs
function updateConfigs() {
  local ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
  [ -f "${MODEL_CONFIGS_PATH}/VERSION" ] && local CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")" || CONFIGSVERSION="0.0.0"
  if [ -z "${1}" ]; then
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ] && [ "${CONFIGSVERSION}" != "${TAG}" ]; then
    (
      local URL="https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs-${TAG}.zip"
      echo "Downloading ${TAG}"
      curl -#kL "${URL}" -o "${TMP_PATH}/configs.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/configs.zip" ]; then
        mkdir -p "${MODEL_CONFIG_PATH}"
        echo "Installing new Configs..."
        if unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}"; then
          rm -f "${TMP_PATH}/configs.zip"
          echo "Successful!"
        else
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Configs" \
      --progressbox "Installing Configs..." 20 70
  fi
  return 0
}

###############################################################################
# Update LKMs
function updateLKMs() {
  [ -f "${LKMS_PATH}/VERSION" ] && local LKMVERSION="$(cat "${LKMS_PATH}/VERSION")" || LKMVERSION="0.0.0"
  if [ -z "${1}" ]; then
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ] && [ "${LKMVERSION}" != "${TAG}" ]; then
    (
      local URL="https://github.com/AuxXxilium/arc-lkm/releases/download/${TAG}/rp-lkms.zip"
      echo "Downloading ${TAG}"
      curl -#kL "${URL}" -o "${TMP_PATH}/rp-lkms.zip" 2>&1 | while IFS= read -r -n1 char; do
        [[ $char =~ [0-9] ]] && keep=1 ;
        [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
        [[ $keep == 1 ]] && progress="$progress$char" ;
      done
      if [ -f "${TMP_PATH}/rp-lkms.zip" ]; then
        rm -rf "${LKMS_PATH}"
        mkdir -p "${LKMS_PATH}"
        echo "Installing new LKMs..."
        if unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKMS_PATH}"; then
          rm -f "${TMP_PATH}/rp-lkms.zip"
          echo "Successful!"
        else
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "LKMs" \
      --progressbox "Installing LKMs..." 20 70
  fi
  return 0
}

###############################################################################
# Loading Update Mode
function arcUpdate() {
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  FAILED="false"
  dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
    --infobox "Updating Dependencies..." 0 0
  sleep 3
  updateAddons
  [ $? -ne 0 ] && FAILED="true"
  updateModules
  [ $? -ne 0 ] && FAILED="true"
  updateLKMs
  [ $? -ne 0 ] && FAILED="true"
  updatePatches
  [ $? -ne 0 ] && FAILED="true"
  if [ "${KERNEL}" == "custom" ]; then
    updateCustom
    [ $? -ne 0 ] && FAILED="true"
  fi
  if [ "${FAILED}" == "true" ] && [ "${UPDATEMODE}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
      --infobox "Update failed!\nTry again later." 0 0
    sleep 3
    exec reboot
  elif [ "${FAILED}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
      --infobox "Update failed!\nTry again later." 0 0
    sleep 3
  elif [ "${FAILED}" == "false" ] && [ "${UPDATEMODE}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
      --infobox "Update successful! -> Reboot to automated build..." 0 0
    sleep 3
    rebootTo "automated"
  elif [ "${FAILED}" == "false" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
      --infobox "Update successful!" 0 0
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    sleep 3
    clear
    exec arc.sh
  fi
}

###############################################################################
# Update Offline
function updateOffline() {
  local ARCMODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  if [ "${ARCMODE}" != "automated" ]; then
    rm -f "${SYSTEM_PATH}/include/offline.json"
    curl -skL "https://autoupdate.synology.com/os/v2" -o "${SYSTEM_PATH}/include/offline.json"
  fi
  return 0
}

###############################################################################
# Update Failed
function updateFailed() {
  local MODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  if [ "${ARCMODE}" == "automated" ]; then
    echo "Installation failed!"
    sleep 5
    exec reboot
    exit 1
  else
    echo "Installation failed!"
    return 1
  fi
}

function updateFaileddialog() {
  local MODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  if [ "${ARCMODE}" == "automated" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Failed" \
      --infobox "Installation failed!" 0 0
    sleep 5
    exec reboot
    exit 1
  else
    dialog --backtitle "$(backtitle)" --title "Update Failed" \
      --msgbox "Installation failed!" 0 0
    return 1
  fi
}