###############################################################################
# Upgrade Loader
function upgradeLoader () {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  local ARCBRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
  rm -f "${TMP_PATH}/check.update"
  rm -f "${TMP_PATH}/arc.img.zip"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl  --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    curl -skL "https://github.com/AuxXxilium/arc/releases/download/${TAG}/check.update" -o "${TMP_PATH}/check.update"
    if [ -f "${TMP_PATH}/check.update" ]; then
      local UPDATE=$(cat "${TMP_PATH}/check.update" | sed -e 's/\.//g' )
      local ARC_VERSION=$(cat "${PART1_PATH}/ARC-VERSION" | sed -e 's/\.//g' )
      if [ ${ARC_VERSION} -lt ${UPDATE} ]; then
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --yesno "Current Config not compatible to new Version!\nDo not restore Config!\nDo you want to upgrade?" 0 0
        if [ $? -eq 0 ]; then
          rm -f "${TMP_PATH}/check.update"
        else
          return 1
        fi
      fi
    else
      updateFaileddialog
    fi
    (
      # Download update file
      echo "Downloading ${TAG}"
      if [ "${ARCBRANCH}" != "stable" ]; then
        local URL="https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}-${ARCBRANCH}.img.zip"
      else
        local URL="https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip"
      fi
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/arc.img.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/arc.img.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
      fi
      if [ -f "${TMP_PATH}/arc.img.zip" ]; then
        echo "Downloading Upgradefile successful!"
      else
        updateFailed
      fi
      unzip -oq "${TMP_PATH}/arc.img.zip" -d "${TMP_PATH}"
      rm -f "${TMP_PATH}/arc.img.zip" >/dev/null
      echo "Installing new Loader Image..."
      # Process complete update
      umount "${PART1_PATH}" "${PART2_PATH}" "${PART3_PATH}"
      if [ "${ARCBRANCH}" != "stable" ]; then
        if dd if="${TMP_PATH}/arc-${ARCBRANCH}.img" of=$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1) bs=1M conv=fsync; then
          rm -f "${TMP_PATH}/arc-${ARCBRANCH}.img" >/dev/null
        else
          updateFailed
        fi
      else
        if dd if="${TMP_PATH}/arc.img" of=$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1) bs=1M conv=fsync; then
          rm -f "${TMP_PATH}/arc.img" >/dev/null
        else
          updateFailed
        fi
      fi
      echo "Upgrade done! -> Rebooting..."
      sleep 2
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
      --progressbox "Upgrading Loader..." 20 70
  fi
  return 0
}

###############################################################################
# Update Loader
function updateLoader() {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  local ARCMODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  local ARCBRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
  rm -f "${TMP_PATH}/check.update"
  rm -f "${TMP_PATH}/checksum.sha256"
  rm -f "${TMP_PATH}/update.zip"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl  --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    curl -skL "https://github.com/AuxXxilium/arc/releases/download/${TAG}/check.update" -o "${TMP_PATH}/check.update"
    if [ -f "${TMP_PATH}/check.update" ]; then
      local UPDATE_VERSION=$(cat "${TMP_PATH}/check.update" | sed -e 's/\.//g' )
      local ARC_VERSION=$(cat "${PART1_PATH}/ARC-VERSION" | sed -e 's/\.//g' )
      if [ ${ARC_VERSION} -lt ${UPDATE_VERSION} ] && [ "${ARCMODE}" == "config" ]; then
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --yesno "Config is not compatible to new Version!\nPlease reconfigure Loader after Update!\nDo you want to update?" 0 0
        if [ $? -eq 0 ]; then
          rm -f "${TMP_PATH}/check.update"
        else
          return 1
        fi
      elif [ ${ARC_VERSION} -lt ${UPDATE_VERSION} ] && [ "${ARCMODE}" == "automated" ]; then
        dialog --backtitle "$(backtitle)" --title "Full-Update Loader" \
          --infobox "Config is not compatible to new Version!\nUpdate not possible!\nPlease reflash Loader." 0 0
        sleep 5
        updateFaileddialog
      fi
    else
      updateFaileddialog
    fi
    (
      # Download update file
      echo "Downloading ${TAG}"
      if [ "${ARCBRANCH}" != "stable" ]; then
        local URL="https://github.com/AuxXxilium/arc/releases/download/${TAG}/update-${ARCBRANCH}.zip"
        local SHA="https://github.com/AuxXxilium/arc/releases/download/${TAG}/checksum-${ARCBRANCH}.sha256"
      else
        local URL="https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip"
        local SHA="https://github.com/AuxXxilium/arc/releases/download/${TAG}/checksum.sha256"
      fi
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/update.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/update.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl --interface ${ARCNIC} -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      fi
      if [ -f "${TMP_PATH}/update.zip" ]; then
        echo "Download successful!"
        if [ "$(sha256sum "${TMP_PATH}/update.zip" | awk '{print $1}')" == "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
          echo "Download successful!"
          echo "Backup Arc Config File..."
          cp -f "${S_FILE_ARC}" "/tmp/arc_serials.yml"
          echo "Cleaning up..."
          rm -rf "${ADDONS_PATH}"
          mkdir -p "${ADDONS_PATH}"
          rm -rf "${MODULES_PATH}"
          mkdir -p "${MODULES_PATH}"
          echo "Installing new Loader Image..."
          unzip -oq "${TMP_PATH}/update.zip" -d "${PART3_PATH}"
          mv -f "${PART3_PATH}/grub.cfg" "${USER_GRUB_CONFIG}"
          mv -f "${PART3_PATH}/ARC-VERSION" "${PART1_PATH}/ARC-VERSION"
          mv -f "${PART3_PATH}/ARC-BRANCH" "${PART1_PATH}/ARC-BRANCH"
          rm -f "${TMP_PATH}/update.zip"
          # Rebuild modules if model/build is selected
          local PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          if [ -n "${PRODUCTVER}" ]; then
            local PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
            local KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
            # Modify KVER for Epyc7002
            [ "${PLATFORM}" == "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
          fi
          if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
            writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
            while read -r ID DESC; do
              writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
            done < <(getAllModules "${PLATFORM}" "${KVERP}")
          fi
          echo "Restore Arc Config File..."
          cp -f "/tmp/arc_serials.yml" "${S_FILE_ARC}"
          echo "Update done!"
          sleep 2
        else
          echo "Checksum mismatch!"
          sleep 5
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Full-Update Loader" \
      --progressbox "Updating Loader..." 20 70
  fi
  return 0
}

###############################################################################
# Update Addons
function updateAddons() {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    (
      # Download update file
      echo "Downloading ${TAG}"
      local URL="https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip"
      local SHA="https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/checksum.sha256"
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/addons.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/addons.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl --interface ${ARCNIC} -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      fi
      if [ -f "${TMP_PATH}/addons.zip" ]; then
        echo "Download successful!"
        if [ "$(sha256sum "${TMP_PATH}/addons.zip" | awk '{print $1}')" == "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
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
          echo "Update done!"
          sleep 2
        else
          echo "Checksum mismatch!"
          sleep 5
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Addons" \
      --progressbox "Updating Addons..." 20 70
  fi
  return 0
}

###############################################################################
# Update Patches
function updatePatches() {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    (
      # Download update file
      local URL="https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches.zip"
      local SHA="https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/checksum.sha256"
      echo "Downloading ${TAG}"
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/patches.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/patches.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl --interface ${ARCNIC} -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      fi
      if [ -f "${TMP_PATH}/patches.zip" ]; then
        echo "Download successful!"
        if [ "$(sha256sum "${TMP_PATH}/patches.zip" | awk '{print $1}')" == "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
          echo "Download successful!"
          rm -rf "${PATCH_PATH}"
          mkdir -p "${PATCH_PATH}"
          echo "Installing new Patches..."
          unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}"
          rm -f "${TMP_PATH}/patches.zip"
          echo "Update done!"
          sleep 2
        else
          echo "Checksum mismatch!"
          sleep 5
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Patches" \
      --progressbox "Updating Patches..." 20 70
  fi
  return 0
}

###############################################################################
# Update Custom
function updateCustom() {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    (
      # Download update file
      local URL="https://github.com/AuxXxilium/arc-custom/releases/download/${TAG}/custom.zip"
      local SHA="https://github.com/AuxXxilium/arc-custom/releases/download/${TAG}/checksum.sha256"
      echo "Downloading ${TAG}"
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/custom.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/custom.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl --interface ${ARCNIC} -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      fi
      if [ -f "${TMP_PATH}/custom.zip" ]; then
        echo "Download successful!"
        if [ "$(sha256sum "${TMP_PATH}/custom.zip" | awk '{print $1}')" == "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
          echo "Download successful!"
          rm -rf "${CUSTOM_PATH}"
          mkdir -p "${CUSTOM_PATH}"
          echo "Installing new Custom Kernel..."
          unzip -oq "${TMP_PATH}/custom.zip" -d "${CUSTOM_PATH}"
          rm -f "${TMP_PATH}/custom.zip"
          echo "Update done!"
          sleep 2
        else
          echo "Checksum mismatch!"
          sleep 5
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Custom" \
      --progressbox "Updating Custom..." 20 70
  fi
  return 0
}

###############################################################################
# Update Modules
function updateModules() {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    (
      # Download update file
      local URL="https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip"
      local SHA="https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/checksum.sha256"
      echo "Downloading ${TAG}"
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/modules.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/modules.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
        curl --interface ${ARCNIC} -skL "${SHA}" -o "${TMP_PATH}/checksum.sha256"
      fi
      if [ -f "${TMP_PATH}/modules.zip" ]; then
        echo "Download successful!"
        if [ "$(sha256sum "${TMP_PATH}/modules.zip" | awk '{print $1}')" == "$(cat ${TMP_PATH}/checksum.sha256 | awk '{print $1}')" ]; then
          echo "Download successful!"
          rm -rf "${MODULES_PATH}"
          mkdir -p "${MODULES_PATH}"
          echo "Installing new Modules..."
          unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}"
          rm -f "${TMP_PATH}/modules.zip"
          # Rebuild modules if model/build is selected
          PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          if [ -n "${PRODUCTVER}" ]; then
            PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
            KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
            # Modify KVER for Epyc7002
            [ "${PLATFORM}" == "epyc7002" ] && KVERP="${PRODUCTVER}-${KVER}" || KVERP="${KVER}"
          fi
          if [ -n "${PLATFORM}" ] && [ -n "${KVERP}" ]; then
            writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
            echo "Rebuilding Modules..."
            while read -r ID DESC; do
              writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
            done < <(getAllModules "${PLATFORM}" "${KVERP}")
          fi
          echo "Update done!"
          sleep 2
        else
          echo "Checksum mismatch!"
          sleep 5
          updateFailed
        fi
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Modules" \
      --progressbox "Updating Modules..." 20 70
  fi
  return 0
}

###############################################################################
# Update Configs
function updateConfigs() {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  local ARCKEY="$(readConfigKey "arc.key" "${USER_CONFIG_FILE}")"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    (
      # Download update file
      local URL="https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip"
      echo "Downloading ${TAG}"
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/configs.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/configs.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
      fi
      if [ -f "${TMP_PATH}/configs.zip" ]; then
        echo "Download successful!"
        mkdir -p "${MODEL_CONFIG_PATH}"
        echo "Installing new Configs..."
        [ -n "${ARCKEY}" ] && cp -f "${S_FILE}" "${TMP_PATH}/serials.yml"
        unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}"
        rm -f "${TMP_PATH}/configs.zip"
        [ -n "${ARCKEY}" ] && cp -f "${TMP_PATH}/serials.yml" "${S_FILE}"
        echo "Update done!"
        sleep 2
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update Configs" \
      --progressbox "Updating Configs..." 20 70
  fi
  return 0
}

###############################################################################
# Update LKMs
function updateLKMs() {
  local ARCNIC="$(readConfigKey "arc.nic" "${USER_CONFIG_FILE}")"
  if [ -z "${1}" ]; then
    # Check for new Version
    idx=0
    while [ ${idx} -le 5 ]; do # Loop 5 times, if successful, break
      if [ "${ARCNIC}" == "auto" ]; then
        local TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      else
        local TAG="$(curl --interface ${ARCNIC} -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r ".[].tag_name" | sort -rV | head -1)"
      fi
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    local TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    (
      # Download update file
      local URL="https://github.com/AuxXxilium/arc-lkm/releases/download/${TAG}/rp-lkms.zip"
      echo "Downloading ${TAG}"
      if [ "${ARCNIC}" == "auto" ]; then
        curl -#kL "${URL}" -o "${TMP_PATH}/rp-lkms.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
      else
        curl --interface ${ARCNIC} -#kL "${URL}" -o "${TMP_PATH}/rp-lkms.zip" 2>&1 | while IFS= read -r -n1 char; do
          [[ $char =~ [0-9] ]] && keep=1 ;
          [[ $char == % ]] && echo "$progress%" && progress="" && keep=0 ;
          [[ $keep == 1 ]] && progress="$progress$char" ;
        done
      fi
      if [ -f "${TMP_PATH}/rp-lkms.zip" ]; then
        echo "Download successful!"
        rm -rf "${LKMS_PATH}"
        mkdir -p "${LKMS_PATH}"
        echo "Installing new LKMs..."
        unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKMS_PATH}"
        rm -f "${TMP_PATH}/rp-lkms.zip"
        echo "Update done!"
        sleep 2
      else
        echo "Error downloading new Version!"
        sleep 5
        updateFailed
      fi
    ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Update LKMs" \
      --progressbox "Updating LKMs..." 20 70
  fi
  return 0
}

###############################################################################
# Update Failed
function updateFailed() {
  local MODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  if [ "${ARCMODE}" == "automated" ]; then
    echo "Update failed!"
    sleep 5
    exec reboot
    exit 1
  else
    echo "Update failed!"
    return 1
  fi
}

function updateFaileddialog() {
  local MODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
  if [ "${ARCMODE}" == "automated" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Failed" \
      --infobox "Update failed!" 0 0
    sleep 5
    exec reboot
    exit 1
  else
    dialog --backtitle "$(backtitle)" --title "Update Failed" \
      --msgbox "Update failed!" 0 0
    return 1
  fi
}