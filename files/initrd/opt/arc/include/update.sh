###############################################################################
# Update Loader
function updateLoader() {
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  local ARC_BRANCH="$(readConfigKey "arc.branch" "${USER_CONFIG_FILE}")"
  local ARCMODE="$(readConfigKey "arc.mode" "${USER_CONFIG_FILE}")"
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
    export URL="https://github.com/AuxXxilium/arc/releases/download/${TAG}/update-${TAG}-${ARC_BRANCH}.zip"
    export TAG="${TAG}"
    {
      curl -kL "$URL" -o ${TMP_PATH}/update.zip 2>&1 | 
      perl -C -lane '
        BEGIN {$header = "Downloading $ENV{TAG}...\n\n"; $| = 1}
        $pcent = $F[0];
        $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
        s/ /\xa0/g;
        if ($. <= 3) {
          $header .= "$_\n";
          $/ = "\r" if $. == 2
        } else {
          print "XXX\n$pcent\n$header$_\nXXX"
        }' |
      dialog --backtitle "$(backtitle)" --title "Update Loader" \
       --gauge "Download Loader: $TAG ..." 14 72
    }
    if [ -f "${TMP_PATH}/update.zip" ] && [ $(ls -s "${TMP_PATH}/update.zip" | cut -d' ' -f1) -gt 300000 ]; then
      dialog --backtitle "$(backtitle)" --title "Update Loader" \
        --infobox "Updating Loader..." 3 50
      if unzip -oq "${TMP_PATH}/update.zip" -d "/mnt"; then
        dialog --backtitle "$(backtitle)" --title "Update Loader" \
        --infobox "Update successful!" 3 50
        sleep 2
      else
        if [ "${ARCMODE}" == "update" ]; then
          dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
            --infobox "Update failed!\nTry again later." 0 0
          sleep 3
          exec reboot
        else
          return 1
        fi
      fi
    else
      if [ "${ARCMODE}" == "update" ]; then
        dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
          --infobox "Update failed!\nTry again later." 0 0
        sleep 3
        exec reboot
      else
        return 1
      fi
    fi
  fi
  if [ "${ARCMODE}" == "update" ] && [ "${CONFDONE}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "Update successful! -> Reboot to automated Build Mode..." 5 80
    sleep 3
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    rebootTo "automated"
  else
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "Update successful! -> Reboot to Config Mode..." 5 80
    sleep 3
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    rebootTo "config"
  fi
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
    export URL="https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons-${TAG}.zip"
    export TAG="${TAG}"
    {
      curl -kL "$URL" -o ${TMP_PATH}/addons.zip 2>&1 | 
      perl -C -lane '
        BEGIN {$header = "Downloading $ENV{TAG}...\n\n"; $| = 1}
        $pcent = $F[0];
        $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
        s/ /\xa0/g;
        if ($. <= 3) {
          $header .= "$_\n";
          $/ = "\r" if $. == 2
        } else {
          print "XXX\n$pcent\n$header$_\nXXX"
        }' |
      dialog --backtitle "$(backtitle)" --title "Update Addons" \
      --gauge "Download Addons: $TAG ..." 14 72
    }
    if [ -f "${TMP_PATH}/addons.zip" ]; then
      rm -rf "${ADDONS_PATH}"
      mkdir -p "${ADDONS_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Addons" \
      --infobox "Updating Addons..." 3 50
      if unzip -oq "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}"; then
        rm -f "${TMP_PATH}/addons.zip"
        for F in $(ls ${ADDONS_PATH}/*.addon 2>/dev/null); do
          ADDON=$(basename "${F}" | sed 's|.addon||')
          rm -rf "${ADDONS_PATH}/${ADDON}"
          mkdir -p "${ADDONS_PATH}/${ADDON}"
          tar -xaf "${F}" -C "${ADDONS_PATH}/${ADDON}"
          rm -f "${F}"
        done
        dialog --backtitle "$(backtitle)" --title "Update Addons" \
          --infobox "Update successful!" 3 50
        sleep 2
      else
        return 1
      fi
    else
      return 1
    fi
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
    export URL="https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches-${TAG}.zip"
    export TAG="${TAG}"
    {
      curl -kL "$URL" -o ${TMP_PATH}/patches.zip 2>&1 | 
      perl -C -lane '
        BEGIN {$header = "Downloading $ENV{TAG}...\n\n"; $| = 1}
        $pcent = $F[0];
        $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
        s/ /\xa0/g;
        if ($. <= 3) {
          $header .= "$_\n";
          $/ = "\r" if $. == 2
        } else {
          print "XXX\n$pcent\n$header$_\nXXX"
        }' |
      dialog --backtitle "$(backtitle)" --title "Update Patches" \
      --gauge "Download Patches: $TAG ..." 14 72
    }
    if [ -f "${TMP_PATH}/patches.zip" ]; then
      rm -rf "${PATCH_PATH}"
      mkdir -p "${PATCH_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Patches" \
      --infobox "Updating Patches..." 3 50
      if unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}"; then
        rm -f "${TMP_PATH}/patches.zip"
        dialog --backtitle "$(backtitle)" --title "Update Patches" \
          --infobox "Update successful!" 3 50
        sleep 2
      else
        return 1
      fi
    else
      return 1
    fi
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
    export URL="https://github.com/AuxXxilium/arc-custom/releases/download/${TAG}/custom-${TAG}.zip"
    export TAG="${TAG}"
    {
      curl -kL "$URL" -o ${TMP_PATH}/custom.zip 2>&1 | 
      perl -C -lane '
        BEGIN {$header = "Downloading $ENV{TAG}...\n\n"; $| = 1}
        $pcent = $F[0];
        $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
        s/ /\xa0/g;
        if ($. <= 3) {
          $header .= "$_\n";
          $/ = "\r" if $. == 2
        } else {
          print "XXX\n$pcent\n$header$_\nXXX"
        }' |
      dialog --backtitle "$(backtitle)" --title "Update Custom Kernel" \
      --gauge "Download Custom Kernel: $TAG ..." 14 72
    }
    if [ -f "${TMP_PATH}/custom.zip" ]; then
      rm -rf "${CUSTOM_PATH}"
      mkdir -p "${CUSTOM_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Custom Kernel" \
        --infobox "Updating Custom Kernel..." 3 50
      if unzip -oq "${TMP_PATH}/custom.zip" -d "${CUSTOM_PATH}"; then
        rm -f "${TMP_PATH}/custom.zip"
        dialog --backtitle "$(backtitle)" --title "Update Custom Kernel" \
          --infobox "Update successful!" 3 50
        sleep 2
      else
        return 1
      fi
    else
      return 1
    fi
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
    rm -rf "${MODULES_PATH}"
    mkdir -p "${MODULES_PATH}"
    export URL="https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules-${TAG}.zip"
    export TAG="${TAG}"
    {
      curl -kL "$URL" -o ${TMP_PATH}/modules.zip 2>&1 | 
      perl -C -lane '
        BEGIN {$header = "Downloading $ENV{TAG}...\n\n"; $| = 1}
        $pcent = $F[0];
        $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
        s/ /\xa0/g;
        if ($. <= 3) {
          $header .= "$_\n";
          $/ = "\r" if $. == 2
        } else {
          print "XXX\n$pcent\n$header$_\nXXX"
        }' |
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
      --gauge "Download Modules: $TAG ..." 14 72
    }
    if [ -f "${TMP_PATH}/modules.zip" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
        --infobox "Updating Modules..." 3 50
      if unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}"; then
        rm -f "${TMP_PATH}/modules.zip"
        dialog --backtitle "$(backtitle)" --title "Update Modules" \
          --infobox "Update successful!" 3 50
        sleep 2
      else
        return 1
      fi
    else
      return 1
    fi
    if [ -f "${MODULES_PATH}/${PLATFORM}-${KVERP}.tgz" ] && [ -f "${MODULES_PATH}/firmware.tgz" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
        --infobox "Rewrite Modules..." 3 50
      sleep 2
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read -r ID DESC; do
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done < <(getAllModules "${PLATFORM}" "${KVERP}")
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
        --infobox "Rewrite successful!" 3 50
      sleep 2
    fi
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
    export URL="https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs-${TAG}.zip"
    export TAG="${TAG}"
    {
      curl -kL "$URL" -o ${TMP_PATH}/configs.zip 2>&1 | 
      perl -C -lane '
        BEGIN {$header = "Downloading $ENV{TAG}...\n\n"; $| = 1}
        $pcent = $F[0];
        $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
        s/ /\xa0/g;
        if ($. <= 3) {
          $header .= "$_\n";
          $/ = "\r" if $. == 2
        } else {
          print "XXX\n$pcent\n$header$_\nXXX"
        }' |
      dialog --backtitle "$(backtitle)" --title "Update Configs" \
      --gauge "Download Configs: $TAG ..." 14 72
    }
    if [ -f "${TMP_PATH}/configs.zip" ]; then
      mkdir -p "${MODEL_CONFIG_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Configs" \
        --infobox "Updating Configs..." 3 50
      if unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}"; then
        rm -f "${TMP_PATH}/configs.zip"
        dialog --backtitle "$(backtitle)" --title "Update Configs" \
          --infobox "Update successful!" 3 50
        sleep 2
      else
        return 1
      fi
    else
      return 1
    fi
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
    export URL="https://github.com/AuxXxilium/arc-lkm/releases/download/${TAG}/rp-lkms.zip"
    export TAG="${TAG}"
    {
      curl -kL "$URL" -o ${TMP_PATH}/rp-lkms.zip 2>&1 | 
      perl -C -lane '
        BEGIN {$header = "Downloading $ENV{TAG}...\n\n"; $| = 1}
        $pcent = $F[0];
        $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
        s/ /\xa0/g;
        if ($. <= 3) {
          $header .= "$_\n";
          $/ = "\r" if $. == 2
        } else {
          print "XXX\n$pcent\n$header$_\nXXX"
        }' |
      dialog --backtitle "$(backtitle)" --title "Update LKMs" \
      --gauge "Download LKMs: $TAG ..." 14 72
    }
    if [ -f "${TMP_PATH}/rp-lkms.zip" ]; then
      rm -rf "${LKMS_PATH}"
      mkdir -p "${LKMS_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update LKMs" \
        --infobox "Updating LKMs..." 3 50
      if unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKMS_PATH}"; then
        rm -f "${TMP_PATH}/rp-lkms.zip"
        dialog --backtitle "$(backtitle)" --title "Update LKMs" \
          --infobox "Update successful!" 3 50
        sleep 2
      else
        return 1
      fi
    else
      return 1
    fi
  fi
  return 0
}

###############################################################################
# Update Offline
function updateOffline() {
  local ARCOFFLINE="$(readConfigKey "arc.offline" "${USER_CONFIG_FILE}")"
  if [ "${ARCOFFLINE}" != "true" ]; then
    rm -f "${CONFIGS_PATH}/offline.json"
    curl -skL "https://autoupdate.synology.com/os/v2" -o "${CONFIGS_PATH}/offline.json"
  fi
  return 0
}

###############################################################################
# Loading Update Mode
function dependenciesUpdate() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  FAILED="false"
  dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
    --infobox "Updating Dependencies..." 0 0
  sleep 2
  updateAddons
  [ $? -ne 0 ] && FAILED="true"
  updateModules
  [ $? -ne 0 ] && FAILED="true"
  updateCustom
  [ $? -ne 0 ] && FAILED="true"
  updatePatches
  [ $? -ne 0 ] && FAILED="true"
  updateConfigs
  [ $? -ne 0 ] && FAILED="true"
  updateLKMs
  [ $? -ne 0 ] && FAILED="true"
  updateOffline
  [ $? -ne 0 ] && FAILED="true"
  if [ "${FAILED}" == "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Dependencies" --aspect 18 \
      --infobox "Update failed!\nTry again later." 0 0
    sleep 3
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