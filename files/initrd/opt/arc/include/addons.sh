#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

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
    case "${BETA}" in
      false)    echo -e "${ADDON}\t\Z4${DESC}\Zn" ;;
      true) echo -e "${ADDON}\t\Z1${DESC}\Zn" ;;
    esac
  done
}

#################################################################################
# Install Addon into ramdisk image
# 1 - Addon
# 2 - Platform
# 3 - DSM version (e.g. 7.4), used to prune non-matching versioned addons/*.tgz
# 4 - Kernel version (e.g. 5.10.55), used to prune non-matching versioned addons/*.tgz
function installAddon() {
  local ADDON="${1:-}"
  local PLATFORM="${2:-}"
  local DSMVER="${3:-}"
  local KVER="${4:-}"
  [ -z "${ADDON}" ] && echo "ERROR: Addon not defined" && return 1
  isAddonAvailable "${ADDON}" "${PLATFORM}" || {
    deleteConfigKey "addon.${ADDON}" "${USER_CONFIG_FILE}"
    return 0
  }
  local TMP_ADDON="${TMP_PATH}/${ADDON}"
  mkdir -p "${TMP_ADDON}"
  local HAS_FILES=0
  local FOUND_TGZ=0
  for TGZ in "${ADDONS_PATH}/${ADDON}/all.tgz"; do
    if [ -f "${TGZ}" ]; then
      FOUND_TGZ=1
      if tar -zxf "${TGZ}" -C "${TMP_ADDON}" 2>>"${LOG_FILE}"; then
        HAS_FILES=1
      fi
    fi
  done
  if [ "${FOUND_TGZ}" -eq 1 ] && [ "${HAS_FILES}" -ne 1 ]; then
    echo "ERROR: Addon ${ADDON} failed to extract" | tee -a "${LOG_FILE}"
    rm -rf "${TMP_ADDON}"
    return 1
  fi
  [ "${HAS_FILES}" -ne 1 ] && deleteConfigKey "addon.${ADDON}" "${USER_CONFIG_FILE}" && rm -rf "${TMP_ADDON}" && return 0
  if [ -f "${TMP_ADDON}/install.sh" ]; then
    if ! cp -f "${TMP_ADDON}/install.sh" "${RAMDISK_PATH}/addons/${ADDON}.sh" 2>>"${LOG_FILE}"; then
      echo "ERROR: Addon ${ADDON} failed to copy install.sh" | tee -a "${LOG_FILE}"
      rm -rf "${TMP_ADDON}"
      return 1
    fi
    chmod +x "${RAMDISK_PATH}/addons/${ADDON}.sh"
  fi
  # Addons ship either a single version-agnostic package named "<name>-<tag>.tgz"
  # (e.g. acpid-7.1.tgz - one suffix segment, kept as-is regardless of build) or
  # per DSM/kernel version packages named "<name>-<dsmver>-<kver>.tgz" (e.g.
  # sensors-7.4-5.10.55.tgz - two suffix segments). Only the versioned package
  # matching the current build is needed at boot, so drop the other versioned
  # ones to save ramdisk space; version-agnostic packages are always kept.
  if [ -d "${TMP_ADDON}/root/addons" ] && [ -n "${DSMVER}" ] && [ -n "${KVER}" ]; then
    for VERSIONED_TGZ in "${TMP_ADDON}/root/addons/${ADDON}"-*.tgz; do
      [ -f "${VERSIONED_TGZ}" ] || continue
      SUFFIX="${VERSIONED_TGZ#"${TMP_ADDON}/root/addons/${ADDON}"-}"
      SUFFIX="${SUFFIX%.tgz}"
      # Version-agnostic: suffix has no "-", e.g. "7.1" (only one segment)
      [ "${SUFFIX}" = "${SUFFIX%-*}" ] && continue
      # Versioned: keep only the exact match for this build
      [ "${SUFFIX}" = "${DSMVER}-${KVER}" ] && continue
      rm -f "${VERSIONED_TGZ}"
    done
  fi
  # -n (no-clobber) intentionally skips files that already exist in the
  # ramdisk and exits non-zero for that; not a real failure, so its result
  # is not checked here.
  [ -d "${TMP_ADDON}/root" ] && cp -rnf "${TMP_ADDON}/root/"* "${RAMDISK_PATH}/" 2>>"${LOG_FILE}"
  rm -rf "${TMP_ADDON}"
  return 0
}

###############################################################################
# Detect if has new local plugins to install/reinstall
function updateAddon() {
  for F in $(LC_ALL=C printf '%s\n' ${ADDONS_PATH}/*.addon 2>/dev/null | sort -V); do
    local ADDON="$(basename "${F}" | sed 's|.addon||')"
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