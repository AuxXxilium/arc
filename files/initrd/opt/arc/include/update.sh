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
  TAG="$(echo "${RESPONSE}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1)"
  if [ "${EXCLUDE_DEV}" = "true" ]; then
    TAG="$(echo "${RESPONSE}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | grep -v "dev" | sort -rV | head -1)"
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
    # curl ends its two header lines with \n and then redraws its progress
    # after each \r: lines end at \n until two are read, at \r after.
    DOWNLOAD_URL="${DOWNLOAD_URL}" awk -v RS='\r' '
      function emit(s, f) {
        line++
        split(s, f, " ")
        pcent = f[1]
        # % Total, % Received, Xferd and the rest, without the columns between
        if (length(s) > 20) s = substr(s, 4, 7) substr(s, 15, 9) substr(s, 32, 9) substr(s, 48)
        gsub(/ /, "\302\240", s) # replacing space with nbsp as dialog squashes spaces
        if (line <= 3) {
          header = header s "\n"
        } else {
          printf "XXX\n%s\n%s%s\nXXX\n", pcent, header, s
          fflush()
        }
      }
      BEGIN { header = "Downloading " ENVIRON["DOWNLOAD_URL"] "...\n\n" }
      {
        rec = $0
        while (line < 2 && (p = index(rec, "\n")) > 0) {
          emit(substr(rec, 1, p - 1))
          rec = substr(rec, p + 1)
        }
        emit(rec)
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
        updateAborted "Failed to retrieve file size. Aborting update."
        return 1
      fi

      if [ "${TMP_AVAILABLE}" -lt "${FILE_SIZE}" ]; then
        updateAborted "Not enough space or RAM.\nRequired: $((FILE_SIZE / 1024 / 1024)) MB\nAvailable: $((TMP_AVAILABLE / 1024 / 1024)) MB."
        return 1
      fi

      if ! downloadWithGauge "${URL}" "${TMP_PATH}/update.zip" "Download Update: ${TAG}..."; then
        updateAborted "Download failed! Check network and try again."
        return 1
      fi
    fi
  fi

  if validateZipFile "${TMP_PATH}/update.zip" 1048576; then
    if [ "${TAG}" != "zip" ]; then
      local HASH_URL="${UPDATE_URL}/${TAG}/update-${TAG}.hash"
      [ "${BETA}" = "true" ] && HASH_URL="${BETA_URL}/${TAG}/update-${TAG}.hash"
      HASH="$(curl -skL --retry 3 --retry-delay 2 --retry-all-errors "${HASH_URL}" | awk '{print $1}')"

      if [ "${HASH}" != "$(sha256sum "${TMP_PATH}/update.zip" | awk '{print $1}')" ]; then
        rm -f "${TMP_PATH}/update.zip"
        updateAborted "Update failed - Hash mismatch!\nTry again later."
        return 1
      fi
    fi

    LOG_FILE="${TMP_PATH}/updatelog"
    rm -f "${LOG_FILE}"
    touch "${LOG_FILE}"

    (
      echo "Cleanup old files..."
      rm -rf "${ADDONS_PATH}" "${CONFIGS_PATH}" "${CUSTOM_PATH}" "${LKMS_PATH}" "${MODULES_PATH}" "${PATCH_PATH}"
      # Remove every shipped kernel/ramdisk variant, not just the current one, so a
      # renamed build (bzImage-<variant>) can not leave a stale image behind that
      # grub would keep booting. initrd-user is generated on the device and must
      # survive; initrd-dsm/zImage-dsm are rebuilt from the PAT after the update.
      for F in "${PART3_PATH}"/bzImage-* "${PART3_PATH}"/initrd-*; do
        [ -f "${F}" ] || continue
        [ "${F}" = "${ARC_RAMDISK_USER_FILE}" ] && continue
        rm -f "${F}"
      done
      # The theme ships as a whole file set; unzip only overwrites, so drop it
      # first to avoid orphans from a previous theme release.
      rm -rf "${GRUB_PATH}/theme"
      # GRUB itself comes in p3/grub-update (see updateGrub); a leftover from an
      # update that did not install it must not mix with this one.
      rm -rf "${PART3_PATH}/grub-update"
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
    # PIPESTATUS[0] is the subshell - $? would be dialog's status, and any
    # command in between (a sleep, a dialog) would clobber it first.
    local EXTRACT_RET=${PIPESTATUS[0]}
    sleep 2

    if [ ${EXTRACT_RET} -ne 0 ]; then
      rm -f "${TMP_PATH}/update.zip"
      resetBuild
      dialog --backtitle "$(backtitle)" --title "Update Failed" \
        --infobox "Update failed!\nReboot to Config Mode..." 5 50
      sleep 3
      rebootTo config
    fi

    # Cleanup
    rm -f "${TMP_PATH}/update.zip"
    rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"

    local NEW_VERSION="$(cat "${PART1_PATH}/ARC-VERSION" 2>/dev/null | head -1 | tr -d "[:space:]" | sed 's/^[v|V]//g')"
    if [ "${TAG}" = "zip" ] || [ "${NEW_VERSION}" = "${TAG}" ]; then
      dialog --backtitle "$(backtitle)" --title "Update Loader" \
      --infobox "Update Loader successful!" 3 50
      sleep 2
    else
      if [ "${ARC_MODE}" = "update" ]; then
        resetBuild
        dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
          --infobox "Update failed!\nReboot to Config Mode..." 0 0
        sleep 3
        rebootTo config
      else
        return 1
      fi
    fi
  else
    rm -f "${TMP_PATH}/update.zip"
    if [ -z "${TAG}" ]; then
      updateAborted "Could not find the latest release. Aborting update."
    else
      updateAborted "Update failed - the update file is broken!\nTry again later."
    fi
    return 1
  fi

  if ! updateGrub; then
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "GRUB could not be updated completely!\nIf the loader does not boot, write the image again." 0 0
    sleep 5
  fi

  # The release brought its own module packs, which can add or drop modules
  # from one release to the next, so the selection is made again from them.
  reselectModules

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

# An update that failed before anything on the loader was changed. Update mode
# runs with nobody at the console, so it boots DSM with the build the loader
# already has rather than stop at the shell or in Config Mode; from the menu the
# caller gets the failure back.
function updateAborted() {
  if [ "${ARC_MODE}" = "update" ]; then
    dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
      --infobox "${1}\nBooting DSM with the current Loader..." 0 0
    sleep 5
    rebootTo dsm
  fi
  dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
    --infobox "${1}" 0 0
  sleep 3
  return 1
}

###############################################################################
# Update GRUB from the update zip. GRUB travels there as p3/grub-update:
#   bootcode.img         the release image up to p1: MBR boot code and core.img
#   EFI/BOOT/BOOT*.EFI   the EFI loaders
#   boot/grub/<target>/  the modules, one directory per target
# not under p1/, where an older Arc would extract BIOS modules next to the
# boot code it leaves in place, and that GRUB does not start. It goes on the
# loader in pairs that must match: the EFI modules with the EFI loaders, and
# the BIOS modules with the boot code. The BIOS pair stays as it is when the
# disk's boot code is not GRUB's (a GPT disk, another boot manager) or
# core.img does not fit before p1; the old GRUB keeps working there.
function updateGrub() {
  local SRC="${PART3_PATH}/grub-update"
  local T F SIZE RET=0
  [ -d "${SRC}" ] || return 0

  for T in i386-efi x86_64-efi; do
    replaceGrubDir "${SRC}/boot/grub/${T}" "${GRUB_PATH}/${T}" || RET=1
  done
  for F in "${SRC}/EFI/BOOT/"*; do
    [ -f "${F}" ] || continue
    case "${F,,}" in *.efi) ;; *) continue ;; esac
    mkdir -p "${PART1_PATH}/EFI/BOOT"
    { cp -f "${F}" "${PART1_PATH}/EFI/BOOT/$(basename "${F}").part" &&
      mv -f "${PART1_PATH}/EFI/BOOT/$(basename "${F}").part" "${PART1_PATH}/EFI/BOOT/$(basename "${F}")"; } || RET=1
  done

  if [ ${RET} -eq 0 ] && [ -d "${SRC}/boot/grub/i386-pc" ] &&
    checkGrubBootCode "${LOADER_DISK}" "${SRC}/bootcode.img"; then
    if replaceGrubDir "${SRC}/boot/grub/i386-pc" "${GRUB_PATH}/i386-pc"; then
      # core.img into the gap before p1, then the MBR's boot code: its first
      # 440 bytes, so the disk signature and partition table stay.
      SIZE=$(stat -c%s "${SRC}/bootcode.img")
      { dd if="${SRC}/bootcode.img" of="${LOADER_DISK}" bs=512 skip=1 seek=1 count=$((SIZE / 512 - 1)) conv=notrunc,fsync 2>/dev/null &&
        dd if="${SRC}/bootcode.img" of="${LOADER_DISK}" bs=440 count=1 conv=notrunc,fsync 2>/dev/null; } || RET=1
    else
      RET=1
    fi
  fi

  sync
  rm -rf "${SRC}"
  return ${RET}
}

# Put a copy of ${1} at ${2}. The copy is made beside ${2} first, so ${2} is
# the old directory or the whole new one, never half of each.
function replaceGrubDir() {
  [ -d "${1}" ] || return 0
  rm -rf "${2}.new" "${2}.old"
  cp -r "${1}" "${2}.new" || { rm -rf "${2}.new"; return 1; }
  if [ -d "${2}" ]; then
    mv -f "${2}" "${2}.old" || { rm -rf "${2}.new"; return 1; }
  fi
  mv -f "${2}.new" "${2}" || return 1
  rm -rf "${2}.old"
}

# Whether ${2}, the release image up to p1, can go on disk ${1}: both are MBR
# disks with GRUB's boot code, and it ends before the disk's p1 begins.
function checkGrubBootCode() {
  local DISK="${1}" CODE="${2}" F I SIZE P1START
  [ -b "${DISK}" ] && [ -f "${CODE}" ] || return 1
  SIZE=$(stat -c%s "${CODE}" 2>/dev/null || echo 0)
  [ "${SIZE}" -ge 1024 ] && [ $((SIZE % 512)) -eq 0 ] || return 1
  for F in "${CODE}" "${DISK}"; do
    [ "$(od -An -tx1 -j510 -N2 "${F}" | tr -d ' \n')" = "55aa" ] || return 1
    head -c 440 "${F}" | grep -aq "GRUB" || return 1
  done
  for I in 0 1 2 3; do
    [ "$(od -An -tx1 -j$((446 + 16 * I + 4)) -N1 "${DISK}" | tr -d ' \n')" = "ee" ] && return 1
  done
  P1START=$(od -An -tu4 -j454 -N4 "${DISK}" | tr -d ' \n')
  [ -n "${P1START}" ] && [ $((P1START * 512)) -ge "${SIZE}" ]
}

###############################################################################
# Select every module of the installed pack, as the modules menu's "Select
# all" does. The platform and kernel are read from the config here, because
# update mode runs before arc.sh loads them.
function reselectModules() {
  local PLATFORM PRODUCTVER KVER KPRE KERNEL PACK
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  [ -z "${PLATFORM}" ] || [ -z "${PRODUCTVER}" ] && return 0
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${P_FILE}")"
  [ -z "${KVER}" ] && return 0
  # The pack unpackModules reads
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  if [ "${KERNEL}" != "official" ]; then
    PACK="${CUSTOM_PATH}/modules-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}-${KERNEL}.tgz"
  else
    PACK="${MODULES_PATH}/${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.tgz"
  fi
  # No pack, no list: keep the old selection rather than an empty one
  [ -f "${PACK}" ] || return 0
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  mergeConfigModules "$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
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
        TAG="$(curl -m 10 -skL "${API_URL}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | grep -v "dev" | sort -rV | head -1 | sed 's/^[v|V]//g')"
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
    local DEV="${LOADER_DISK}"

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
    TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1 | sed 's/^[v|V]//g')"
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
      TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1 | sed 's/^[v|V]//g')"
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
    TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1 | sed 's/^[v|V]//g')"
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
    TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1 | sed 's/^[v|V]//g')"
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
      TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1 | sed 's/^[v|V]//g')"
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
      TAG="$(curl -m 10 -skL "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1 | sed 's/^[v|V]//g')"
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
    [ -n "${REPO}" ] && REMOTE="$(curl -m 10 -skL "https://api.github.com/repos/${REPO}/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | head -1 | sed 's/^[v|V]//g')"
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