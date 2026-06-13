#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

function githubApiJsonRetry() {
  local URL="${1}"
  local MAX_RETRIES="${2:-6}"
  local SLEEP_SECONDS="${3:-3}"
  local RESPONSE=""
  local IDX=0

  while [ "${IDX}" -lt "${MAX_RETRIES}" ]; do
    RESPONSE="$(curl -m 10 -skL "${URL}" 2>/dev/null || true)"
    if [ -n "${RESPONSE}" ] && echo "${RESPONSE}" | jq -e . >/dev/null 2>&1; then
      printf '%s\n' "${RESPONSE}"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
    IDX=$((IDX + 1))
  done

  return 1
}

function githubLatestTagRetry() {
  local RELEASES_API_URL="${1}"
  local EXCLUDE_DEV="${2:-false}"
  local RESPONSE=""
  local TAG=""

  RESPONSE="$(githubApiJsonRetry "${RELEASES_API_URL}")" || return 1
  TAG="$(echo "${RESPONSE}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' | sort -rV | head -1)"
  if [ "${EXCLUDE_DEV}" = "true" ]; then
    TAG="$(echo "${RESPONSE}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' | grep -v "dev" | sort -rV | head -1)"
  fi

  TAG="$(echo "${TAG}" | sed 's/^[v|V]//g')"
  [ -n "${TAG}" ] || return 1
  printf '%s\n' "${TAG}"
}

function githubAssetSizeRetry() {
  local RELEASES_API_URL="${1}"
  local TAG="${2}"
  local ASSET_NAME="${3}"
  local RESPONSE=""
  local FILE_SIZE=""

  RESPONSE="$(githubApiJsonRetry "${RELEASES_API_URL}/tags/${TAG}")" || return 1
  FILE_SIZE="$(echo "${RESPONSE}" | jq -r --arg asset "${ASSET_NAME}" '.assets[]? | select(.name == $asset) | .size' | head -1)"

  if ! [[ "${FILE_SIZE}" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  [ "${FILE_SIZE}" -gt 0 ] || return 1
  printf '%s\n' "${FILE_SIZE}"
}

function downloadWithGauge() {
  local DOWNLOAD_URL="${1}"
  local OUTPUT_PATH="${2}"
  local GAUGE_TITLE="${3}"
  local TMP_OUTPUT_PATH="${OUTPUT_PATH}.part"

  rm -f "${OUTPUT_PATH}" "${TMP_OUTPUT_PATH}"

  {
    {
      curl -kL --retry 3 --retry-delay 2 --retry-all-errors "${DOWNLOAD_URL}" -o "${TMP_OUTPUT_PATH}" 2>&3 3>&-
    } 3>&1 >&4 4>&- |
    DOWNLOAD_URL="${DOWNLOAD_URL}" perl -C -lane '
      BEGIN {$header = "Downloading $ENV{DOWNLOAD_URL}...\n\n"; $| = 1}
      $pcent = $F[0];
      $_ = join "", unpack("x3 a7 x4 a9 x8 a9 x7 a*") if length > 20;
      s/ /\xa0/g; # replacing space with nbsp as dialog squashes spaces
      if ($. <= 3) {
        $header .= "$_\n";
        $/ = "\r" if $. == 2
      } else {
        print "XXX\n$pcent\n$header$_\nXXX"
      }' 4>&- |
    dialog --gauge "${GAUGE_TITLE}" 14 72 4>&-
  } 4>&1

  if [ ! -s "${TMP_OUTPUT_PATH}" ]; then
    rm -f "${TMP_OUTPUT_PATH}" "${OUTPUT_PATH}"
    return 1
  fi

  mv -f "${TMP_OUTPUT_PATH}" "${OUTPUT_PATH}"
}

function validateZipFile() {
  local ZIP_PATH="${1}"
  local MIN_SIZE_BYTES="${2:-1024}"
  local ZIP_SIZE="0"

  [ -f "${ZIP_PATH}" ] || return 1
  ZIP_SIZE=$(stat -c%s "${ZIP_PATH}" 2>/dev/null || echo 0)
  [ "${ZIP_SIZE}" -ge "${MIN_SIZE_BYTES}" ] || return 1
  unzip -tqq "${ZIP_PATH}" >/dev/null 2>&1 || return 1
  return 0
}

###############################################################################
# Update Loader
function updateLoader() {
  local BETA="${1:-false}"
  local TAG="${2}"

  if [ "${BETA}" = "true" ]; then
    API_URL="${BETA_API_URL}"
  fi

  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"

  if [ "${TAG}" != "zip" ]; then
    if [ -z "${TAG}" ]; then
      TAG="$(githubLatestTagRetry "${API_URL}" "true" || true)"
    fi
    if [ -n "${TAG}" ]; then
      export TAG="${TAG}"
      export URL="${UPDATE_URL}/${TAG}/update-${TAG}.zip"
      if [ "${BETA}" = "true" ]; then
        URL="${BETA_URL}/${TAG}/update-${TAG}.zip"
      fi

      local TMP_AVAILABLE=$(df --output=avail "${TMP_PATH}" | tail -1)
      TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

      local FILE_SIZE
      FILE_SIZE="$(githubAssetSizeRetry "${API_URL}" "${TAG}" "update-${TAG}.zip" || true)"

      if [ -z "${FILE_SIZE}" ] || [ "${FILE_SIZE}" -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --infobox "Failed to retrieve file size. Aborting update." 3 50
        sleep 3
        return 1
      fi

      if [ "${TMP_AVAILABLE}" -lt "${FILE_SIZE}" ]; then
        dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --infobox "Not enough space or RAM.\nRequired: $((FILE_SIZE / 1024 / 1024)) MB\nAvailable: $((TMP_AVAILABLE / 1024 / 1024)) MB." 5 50
        sleep 3
        return 1
      fi

      if ! downloadWithGauge "${URL}" "${TMP_PATH}/update.zip" "Download Update: ${TAG}..."; then
        dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --infobox "Download failed! Check network and try again." 3 50
        sleep 3
        return 1
      fi
    fi
  fi

  if validateZipFile "${TMP_PATH}/update.zip" 1048576; then
    if [ "${TAG}" != "zip" ]; then
      HASH="$(curl -skL "${UPDATE_URL}/${TAG}/update-${TAG}.hash" | awk '{print $1}')"
      if [ "${BETA}" = "true" ]; then
        HASH="$(curl -skL "${BETA_URL}/${TAG}/update-${TAG}.hash" | awk '{print $1}')"
      fi

      if [ "${HASH}" != "$(sha256sum "${TMP_PATH}/update.zip" | awk '{print $1}')" ]; then
        dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
          --infobox "Update failed - Hash mismatch!\nTry again later." 0 0
        sleep 3
        rm -f "${TMP_PATH}/update.zip"
        return 1
      fi
    fi

    LOG_FILE="${TMP_PATH}/updatelog"
    rm -f "${LOG_FILE}"
    touch "${LOG_FILE}"

    (
      echo "Cleanup old files..."
      rm -rf "${ADDONS_PATH}" "${CONFIGS_PATH}" "${CUSTOM_PATH}" "${LKMS_PATH}" "${MODULES_PATH}" "${PATCH_PATH}"
      rm -f "${ARC_RAMDISK_FILE}" "${ARC_BZIMAGE_FILE}"
      mkdir -p "${ADDONS_PATH}" "${CONFIGS_PATH}" "${CUSTOM_PATH}" "${LKMS_PATH}" "${MODULES_PATH}" "${PATCH_PATH}"

      echo "Extracting files from update.zip..."
      if unzip -o "${TMP_PATH}/update.zip" -d "/mnt" >> "${LOG_FILE}" 2>&1; then
        echo "Extraction completed successfully."
        sleep 3
        return 0
      else
        echo "Error: Failed to extract files."
        sleep 3
        return 1
      fi
    ) 2>&1 | tee -a "${LOG_FILE}" | dialog --backtitle "$(backtitle)" --title "Processing Update" \
      --progressbox "Processing update..." 10 70
    sleep 2

    if [ $? -ne 0 ]; then
      dialog --backtitle "$(backtitle)" --title "Update Failed" \
        --infobox "Update failed! The system will now reboot." 5 50
      sleep 3
      exec reboot
    fi

    # Cleanup
    rm -f "${TMP_PATH}/update.zip"
    rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"

    if [ "$(cat "${PART1_PATH}/ARC-VERSION")" = "${TAG}" ] || [ "${TAG}" = "zip" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Loader" \
      --infobox "Update Loader successful!" 3 50
      sleep 2
    else
      if [ "${ARC_MODE}" = "update" ]; then
        dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
          --infobox "Update failed!\nTry again later." 0 0
        sleep 3
        exec reboot
      else
        return 1
      fi
    fi
  else
    if [ "${ARC_MODE}" = "update" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
        --infobox "Update failed!\nTry again later." 0 0
      sleep 3
      exec reboot
    else
      return 1
    fi
  fi

  resetBuild

  if [ "${ARC_MODE}" = "update" ] && [ "${CONFDONE}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "Update Loader successful! -> Reboot to automated Build Mode..." 3 60
    sleep 3
    rebootTo automated
  else
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "Update Loader successful! -> Reboot to Config Mode..." 3 50
    sleep 3
    rebootTo config
  fi
}

###############################################################################
# Upgrade Loader
function upgradeLoader() {
  local BETA="${1:-false}"
  local TAG="${2}"

  if [ "${BETA}" = "true" ]; then
    API_URL="${BETA_API_URL}"
  fi

  if [ "${TAG}" != "zip" ]; then
    if [ -z "${TAG}" ]; then
      idx=0
      while [ "${idx}" -le 5 ]; do
        TAG="$(curl -m 10 -skL "${API_URL}" | jq -r ".[].tag_name" | grep -v "dev" | sort -rV | head -1 | sed 's/^[v|V]//g')"
        if [ -n "${TAG}" ]; then
          break
        fi
        sleep 3
        idx=$((${idx} + 1))
      done
    fi
    if [ -n "${TAG}" ]; then
      export TAG="${TAG}"
      export URL="${UPDATE_URL}/${TAG}/arc-${TAG}.img.zip"
      if [ "${BETA}" = "true" ]; then
        URL="${BETA_URL}/${TAG}/arc-${TAG}.img.zip"
      fi

      local TMP_AVAILABLE=$(df --output=avail "${TMP_PATH}" | tail -1)
      TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

      local FILE_SIZE
      FILE_SIZE=$(curl -skL "${API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"arc-${TAG}.img.zip\") | .size")

      if [ -z "${FILE_SIZE}" ] || [ "${FILE_SIZE}" -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --infobox "Failed to retrieve file size. Aborting update." 3 50
        sleep 3
        return 1
      fi

      if [ "${TMP_AVAILABLE}" -lt "${FILE_SIZE}" ]; then
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --infobox "Not enough space or RAM. Required: $((FILE_SIZE / 1024 / 1024)) MB, Available: $((TMP_AVAILABLE / 1024 / 1024)) MB." 5 60
        sleep 3
        return 1
      fi

      if ! downloadWithGauge "${URL}" "${TMP_PATH}/arc.img.zip" "Download Loader: ${TAG}..."; then
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --infobox "Download failed! Check network and try again." 3 50
        sleep 3
        return 1
      fi
    fi
  fi
  if validateZipFile "${TMP_PATH}/arc.img.zip" 1048576; then
    local TMP_AVAILABLE=$(df --output=avail "${TMP_PATH}" | tail -1)
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))
    local FILE_SIZE=$(stat -c%s "${TMP_PATH}/arc.img.zip")
    local REQUIRED_SPACE=$((FILE_SIZE * 2))

    if [ "${TMP_AVAILABLE}" -lt "${REQUIRED_SPACE}" ]; then
      dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
        --infobox "Not enough space or RAM.\nRequired: $((REQUIRED_SPACE / 1024 / 1024)) MB\nAvailable: $((TMP_AVAILABLE / 1024 / 1024)) MB." 5 50
      sleep 3
      return 1
    fi

    unzip -oq "${TMP_PATH}/arc.img.zip" -d "${TMP_PATH}"
    rm -f "${TMP_PATH}/arc.img.zip"
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
      --infobox "Installing new Loader Image..." 3 50
    umount "${PART1_PATH}" "${PART2_PATH}" "${PART3_PATH}"

    local IMG_FILE="${TMP_PATH}/arc.img"
    local DEV1 DEV2 DEV3 DEV
    DEV1=$(blkid | grep 'LABEL="ARC1"' | cut -d: -f1)
    DEV2=$(blkid | grep 'LABEL="ARC2"' | cut -d: -f1)
    DEV3=$(blkid | grep 'LABEL="ARC3"' | cut -d: -f1)
    DEV=$(echo "${DEV1}" | sed 's/[0-9]*$//')

    if [ -b "${DEV}" ] && [ -f "${IMG_FILE}" ]; then
      if dd if="${IMG_FILE}" of="${DEV}" bs=1M conv=fsync; then
        rm -f "${IMG_FILE}"
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --infobox "Upgrade done! -> Rebooting..." 3 50
        sleep 2
        exec reboot
      else
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "Upgrade failed!\nTry again later." 0 0
        sleep 3
        exec reboot
      fi
    else
      dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
        --infobox "Device not found!\nTry again later." 0 0
      sleep 3
      exec reboot
    fi
  else
    rm -f "${TMP_PATH}/arc.img.zip"
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
      --infobox "Upgrade failed!\nTry again later." 0 0
    sleep 3
  fi
  return 0
}

###############################################################################
# Update Addons
function updateAddons() {
  [ -f "${ADDONS_PATH}/VERSION" ] && local ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")" || ADDONSVERSION="0.0.0"
  local TAG=""
  idx=0
  while [ "${idx}" -le 5 ]; do
    TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1 | sed 's/^[v|V]//g')"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons-${TAG}.zip"

    local TMP_AVAILABLE=$(df --output=avail "${TMP_PATH}" | tail -1)
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

    local FILE_SIZE
    FILE_SIZE=$(curl -skL "${ADDONS_API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"addons-${TAG}.zip\") | .size")

    if [ -z "${FILE_SIZE}" ] || [ "${FILE_SIZE}" -eq 0 ]; then
      dialog --backtitle "$(backtitle)" --title "Update Addons" \
        --infobox "Failed to retrieve file size. Aborting update." 3 50
      sleep 3
      return 1
    fi

    if [ "${TMP_AVAILABLE}" -lt "${FILE_SIZE}" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Addons" \
        --infobox "Not enough space (RAM) in tmp folder. Required: $((FILE_SIZE / 1024 / 1024)) MB, Available: $((TMP_AVAILABLE / 1024 / 1024)) MB." 5 60
      sleep 3
      return 1
    fi

    if ! downloadWithGauge "${URL}" "${TMP_PATH}/addons.zip" "Download Addons: ${TAG}..."; then
      return 1
    fi
    if validateZipFile "${TMP_PATH}/addons.zip" 1024; then
      rm -rf "${ADDONS_PATH}"
      mkdir -p "${ADDONS_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Addons" \
      --infobox "Updating Addons..." 3 50
      if unzip -oq "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}"; then
        rm -f "${TMP_PATH}/addons.zip"
        updateAddon
        dialog --backtitle "$(backtitle)" --title "Update Addons" \
          --infobox "Update Addons successful!" 3 50
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
  local TAG=""
    idx=0
    while [ "${idx}" -le 5 ]; do
      TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r ".[].tag_name" | sort -rV | head -1 | sed 's/^[v|V]//g')"
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches-${TAG}.zip"

    if ! downloadWithGauge "${URL}" "${TMP_PATH}/patches.zip" "Download Patches: ${TAG}..."; then
      return 1
    fi
    if validateZipFile "${TMP_PATH}/patches.zip" 1024; then
      rm -rf "${PATCH_PATH}"
      mkdir -p "${PATCH_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Patches" \
      --infobox "Updating Patches..." 3 50
      if unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}"; then
        rm -f "${TMP_PATH}/patches.zip"
        dialog --backtitle "$(backtitle)" --title "Update Patches" \
          --infobox "Update Patches successful!" 3 50
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
  local TAG=""
  idx=0
  while [ "${idx}" -le 5 ]; do
    TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r ".[].tag_name" | sort -rV | head -1 | sed 's/^[v|V]//g')"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-custom/releases/download/${TAG}/custom-${TAG}.zip"

    local TMP_AVAILABLE=$(df --output=avail "${TMP_PATH}" | tail -1)
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

    local FILE_SIZE
    FILE_SIZE=$(curl -skL "${CUSTOM_API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"custom-${TAG}.zip\") | .size")

    if [ -z "${FILE_SIZE}" ] || [ "${FILE_SIZE}" -eq 0 ]; then
      dialog --backtitle "$(backtitle)" --title "Update Custom" \
        --infobox "Failed to retrieve file size. Aborting update." 3 50
      sleep 3
      return 1
    fi

    if [ "${TMP_AVAILABLE}" -lt "${FILE_SIZE}" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Custom" \
        --infobox "Not enough space (RAM) in tmp folder. Required: $((FILE_SIZE / 1024 / 1024)) MB, Available: $((TMP_AVAILABLE / 1024 / 1024)) MB." 5 60
      sleep 3
      return 1
    fi

    if ! downloadWithGauge "${URL}" "${TMP_PATH}/custom.zip" "Download Custom: ${TAG}..."; then
      return 1
    fi
    if validateZipFile "${TMP_PATH}/custom.zip" 1024; then
      rm -rf "${CUSTOM_PATH}"
      mkdir -p "${CUSTOM_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Custom Kernel" \
        --infobox "Updating Custom Kernel..." 3 50
      if unzip -oq "${TMP_PATH}/custom.zip" -d "${CUSTOM_PATH}"; then
        rm -f "${TMP_PATH}/custom.zip"
        # Symlink Custom for DSM 7.3
        if [ -d "${CUSTOM_PATH}/" ]; then
          while IFS= read -r -d '' CSRC; do
            CSRCB="$(basename "$CSRC")"
            CTARB="${CSRCB/-7.2-/-7.3-}"
            CTAR="${CUSTOM_PATH}/${CTARB}"
            if [ "$CTAR" != "$CSRC" ] && [ ! -e "$CTAR" ]; then
              ln -sf "$CSRC" "$CTAR" || true
            fi
          done < <(find "${CUSTOM_PATH}" -maxdepth 1 -type f \( -name '*-7.2-*.tgz' \) -print0)
        fi
        dialog --backtitle "$(backtitle)" --title "Update Custom Kernel" \
          --infobox "Update Custom successful!" 3 50
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
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${P_FILE}")"
  local TAG=""
  idx=0
  while [ "${idx}" -le 5 ]; do
    TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1 | sed 's/^[v|V]//g')"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules-${TAG}.zip"

    local TMP_AVAILABLE=$(df --output=avail "${TMP_PATH}" | tail -1)
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

    local FILE_SIZE
    FILE_SIZE=$(curl -skL "${MODULES_API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"modules-${TAG}.zip\") | .size")

    if [ -z "${FILE_SIZE}" ] || [ "${FILE_SIZE}" -eq 0 ]; then
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
        --infobox "Failed to retrieve file size. Aborting update." 3 50
      sleep 3
      return 1
    fi

    if [ "${TMP_AVAILABLE}" -lt "${FILE_SIZE}" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
        --infobox "Not enough space (RAM) in tmp folder. Required: $((FILE_SIZE / 1024 / 1024)) MB, Available: $((TMP_AVAILABLE / 1024 / 1024)) MB." 5 60
      sleep 3
      return 1
    fi

    rm -rf "${MODULES_PATH}"
    mkdir -p "${MODULES_PATH}"
    if ! downloadWithGauge "${URL}" "${TMP_PATH}/modules.zip" "Download Modules: ${TAG}..."; then
      return 1
    fi
    if validateZipFile "${TMP_PATH}/modules.zip" 1024; then
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
        --infobox "Updating Modules..." 3 50
      if unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}"; then
        rm -f "${TMP_PATH}/modules.zip"
        dialog --backtitle "$(backtitle)" --title "Update Modules" \
          --infobox "Update Modules successful!" 3 50
        sleep 2
      else
        return 1
      fi
    else
      return 1
    fi
    if [ -f "${MODULES_PATH}/${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.tgz" ] && [ -f "${MODULES_PATH}/firmware.tgz" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Modules" \
        --infobox "Rewrite Modules..." 3 50
      sleep 2
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read -r ID DESC; do
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done <<<"$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}")"
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
  [ -f "${CONFIGS_PATH}/VERSION" ] && local CONFIGSVERSION="$(cat "${CONFIGS_PATH}/VERSION")" || CONFIGSVERSION="0.0.0"
  local TAG=""
  if [ -z "${1}" ]; then
    idx=0
    while [ "${idx}" -le 5 ]; do
      TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r ".[].tag_name" | sort -rV | head -1 | sed 's/^[v|V]//g')"
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs-${TAG}.zip"

    if ! downloadWithGauge "${URL}" "${TMP_PATH}/configs.zip" "Download Configs: ${TAG}..."; then
      return 1
    fi
    if validateZipFile "${TMP_PATH}/configs.zip" 1024; then
      mkdir -p "${CONFIGS_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update Configs" \
        --infobox "Updating Configs..." 3 50
      if unzip -oq "${TMP_PATH}/configs.zip" -d "${CONFIGS_PATH}"; then
        rm -f "${TMP_PATH}/configs.zip"
        dialog --backtitle "$(backtitle)" --title "Update Configs" \
          --infobox "Update Configs successful!" 3 50
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
  local TAG=""
  if [ -z "${1}" ]; then
    idx=0
    while [ "${idx}" -le 5 ]; do
      TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r ".[].tag_name" | sort -rV | head -1 | sed 's/^[v|V]//g')"
      if [ -n "${TAG}" ]; then
        break
      fi
      sleep 3
      idx=$((${idx} + 1))
    done
  else
    TAG="${1}"
  fi
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-lkm/releases/download/${TAG}/rp-lkms.zip"

    if ! downloadWithGauge "${URL}" "${TMP_PATH}/rp-lkms.zip" "Download LKMs: ${TAG}..."; then
      return 1
    fi
    if validateZipFile "${TMP_PATH}/rp-lkms.zip" 1024; then
      rm -rf "${LKMS_PATH}"
      mkdir -p "${LKMS_PATH}"
      dialog --backtitle "$(backtitle)" --title "Update LKMs" \
        --infobox "Updating LKMs..." 3 50
      if unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKMS_PATH}"; then
        rm -f "${TMP_PATH}/rp-lkms.zip"
        dialog --backtitle "$(backtitle)" --title "Update LKMs" \
          --infobox "Update LKMs successful!" 3 50
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

DEPENDENCY_NAMES=(
  "Addons"
  "Modules"
  "Custom Kernel"
  "Configs"
  "Patches"
  "LKMs"
)
DEPENDENCY_VERSION_FILES=(
  "${ADDONS_PATH}/VERSION"
  "${MODULES_PATH}/VERSION"
  "${CUSTOM_PATH}/VERSION"
  "${CONFIGS_PATH}/VERSION"
  "${PATCH_PATH}/VERSION"
  "${LKMS_PATH}/VERSION"
)
DEPENDENCY_REPOS=(
  "AuxXxilium/arc-addons"
  "AuxXxilium/arc-modules"
  "AuxXxilium/arc-custom"
  "AuxXxilium/arc-configs"
  "AuxXxilium/arc-patches"
  "AuxXxilium/arc-lkm"
)
DEPENDENCY_FUNCTIONS=(
  "updateAddons"
  "updateModules"
  "updateCustom"
  "updateConfigs"
  "updatePatches"
  "updateLKMs"
)

function dependenciesUpdate() {
  dialog --backtitle "$(backtitle)" --title "Select Dependencies to Update" \
    --infobox "Fetching latest versions..." 3 35
  CHECKLIST_OPTS=()
  for i in "${!DEPENDENCY_NAMES[@]}"; do
    local VERFILE="${DEPENDENCY_VERSION_FILES[$i]}"
    local LOCAL="n/a"
    [ -n "${VERFILE}" ] && [ -f "${VERFILE}" ] && LOCAL="$(cat "${VERFILE}")"
    local REPO="${DEPENDENCY_REPOS[$i]}"
    local REMOTE="n/a"
    [ -n "${REPO}" ] && REMOTE="$(curl -m 10 -skL "https://api.github.com/repos/${REPO}/releases" | jq -r ".[].tag_name" | sort -rV | head -1 | sed 's/^[v|V]//g')"
    [ -z "${REMOTE}" ] && REMOTE="n/a"
    CHECKLIST_OPTS+=("$i" "${DEPENDENCY_NAMES[$i]} (${LOCAL} -> ${REMOTE})" "off")
  done

  CHOICES=$(dialog --backtitle "$(backtitle)" --title "Select Dependencies to Update" \
    --checklist "Use SPACE to select and ENTER to confirm:" 15 70 6 \
    "${CHECKLIST_OPTS[@]}" 3>&1 1>&2 2>&3)

  [ $? -ne 0 ] && return

  FAILED=false
  for idx in $CHOICES; do
    idx=${idx//\"/}
    ${DEPENDENCY_FUNCTIONS[$idx]} || FAILED=true
  done

  if $FAILED; then
    dialog --infobox "Some updates failed! Try again later." 3 40
  else
    dialog --infobox "All selected updates completed successfully!" 3 40
    resetBuildstatus
  fi

  sleep 3
  clear
  exec arc.sh
}