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
    RESPONSE="$(curl -m 10 -sL "${URL}" 2>/dev/null || true)"
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
  TAG="$(echo "${RESPONSE}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p)"
  if [ "${EXCLUDE_DEV}" = "true" ]; then
    TAG="$(echo "${RESPONSE}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | grep -v "dev" | sort -rV | sed -n 1p)"
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
      curl -fL --proto '=https' --proto-redir '=https' --retry 3 --retry-delay 2 --retry-all-errors "${DOWNLOAD_URL}" -o "${TMP_OUTPUT_PATH}" 2>&3 3>&-
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
# zipPathsOk <zip> [<top directory>...]
#
# The same check as zip_paths_ok in Arc Control's loader-update.lib.sh,
# which runs it on the update it installs from DSM.
#
# Whether every entry of <zip> stays inside the directory it is unpacked into,
# and, with top directories given, inside one of them. Read from the archive
# itself rather than from unzip's listing: the central directory (what a
# listing shows) and every entry's local header (what BusyBox's unzip goes by
# when it extracts), which must name the same path. Refused:
# - an absolute name, a "." or ".." component, an empty one ("a//b"), a
#   backslash, a control or non-ASCII byte;
# - a name outside the top directories;
# - any symlink (release zips carry none: zip -r stores what a link points to);
# - a local header that names something else than the central directory, a
#   split or zip64 archive, a central directory that does not add up.
# unzip's own clean-up is no substitute: it turns "../x" and "/x" into "x" and
# goes on, so they land beside p1 and p3 - on p2, say - and it makes a symlink
# to anywhere. ZIP_ERROR says what was refused.
function zipPathsOk() {
  local zip="${1}" size tailn eocd list
  shift
  local tops="${*}"
  ZIP_ERROR=""
  size="$(stat -c%s "${zip}" 2>/dev/null)"
  if [ -z "${size}" ] || [ "${size}" -lt 22 ]; then
    ZIP_ERROR="it is not a zip archive"
    return 1
  fi

  # The end of central directory record: the last "PK\5\6" in the final
  # 64 KiB + 22 bytes, the most a comment can push it back.
  tailn=$((size < 65557 ? size : 65557))
  eocd="$(tail -c "${tailn}" "${zip}" 2>/dev/null | od -An -v -tu1 | awk -v base="$((size - tailn))" '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      for (p = n - 22; p >= 0; p--)
        if (b[p] == 80 && b[p + 1] == 75 && b[p + 2] == 5 && b[p + 3] == 6) {
          printf "%d %d %d %d %.0f %.0f %.0f\n", b[p + 4] + 256 * b[p + 5], b[p + 6] + 256 * b[p + 7],
            b[p + 8] + 256 * b[p + 9], b[p + 10] + 256 * b[p + 11],
            b[p + 12] + 256 * b[p + 13] + 65536 * b[p + 14] + 16777216 * b[p + 15],
            b[p + 16] + 256 * b[p + 17] + 65536 * b[p + 18] + 16777216 * b[p + 19], base + p
          exit
        }
    }')"
  set -- ${eocd}
  if [ ${#} -ne 7 ]; then
    ZIP_ERROR="it is not a zip archive (no end of central directory)"
    return 1
  fi
  # disk, central directory disk, entries on this disk, entries, size, offset
  if [ "${1}" -ne 0 ] || [ "${2}" -ne 0 ] || [ "${3}" -ne "${4}" ] || [ "${4}" -eq 65535 ] ||
    [ "${6}" -eq 4294967295 ] || [ $(($6 + $5)) -gt "${7}" ]; then
    ZIP_ERROR="it is a split or zip64 archive, or its central directory is damaged"
    return 1
  fi

  # The central directory: one line per entry, "<local header offset>
  # <name length> <name bytes, comma-separated>", or "BAD <reason>".
  list="$(dd if="${zip}" bs=65536 iflag=skip_bytes,count_bytes skip="${6}" count="${5}" 2>/dev/null |
    od -An -v -tu1 | awk -v total="${4}" -v tops="${tops}" '
    function bad(why) { print "BAD " why; exit }
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      nt = split(tops, top, " ")
      p = 0; k = 0
      while (p < n) {
        if (p + 46 > n || b[p] != 80 || b[p + 1] != 75 || b[p + 2] != 1 || b[p + 3] != 2)
          bad("the central directory is damaged")
        nl = b[p + 28] + 256 * b[p + 29]
        xl = b[p + 30] + 256 * b[p + 31]
        cl = b[p + 32] + 256 * b[p + 33]
        if (p + 46 + nl + xl + cl > n) bad("the central directory is damaged")
        name = ""; bytes = ""
        for (i = 0; i < nl; i++) {
          c = b[p + 46 + i]
          if (c < 32 || c > 126 || c == 92) bad("an entry has a name with a control, non-ASCII or backslash character")
          name = name sprintf("%c", c)
          bytes = bytes (i ? "," : "") c
        }
        if (name == "") bad("an entry has no name")
        # Unix "made by" and S_IFLNK in the upper half of the external attributes
        if (b[p + 5] == 3 && int((b[p + 40] + 256 * b[p + 41]) / 4096) == 10) bad(name " is a symlink")
        if (substr(name, 1, 1) == "/") bad(name " is an absolute path")
        m = split(name, part, "/")
        for (i = 1; i <= m; i++) {
          if (part[i] == "." || part[i] == "..") bad(name " leaves the directory it is unpacked into")
          if (part[i] == "" && i < m) bad(name " has an empty path component")
        }
        if (nt) {
          ok = 0
          for (i = 1; i <= nt; i++) if (part[1] == top[i] && m > 1) ok = 1
          if (!ok) bad(name " is outside " tops)
        }
        printf "%.0f %d %s\n", b[p + 42] + 256 * b[p + 43] + 65536 * b[p + 44] + 16777216 * b[p + 45], nl, bytes
        k++
        p += 46 + nl + xl + cl
      }
      if (k != total) bad("the central directory lists " k " entries, the archive says " total)
    }')"
  case "${list}" in
    "") ZIP_ERROR="its central directory could not be read"; return 1 ;;
    "BAD "* | *"
BAD "*) ZIP_ERROR="$(printf '%s\n' "${list}" | sed -n 's/^BAD //p' | head -1)"; return 1 ;;
  esac

  # Every local header, in the same order: its signature, and the same name.
  local off len bytes res lf
  # A file, not awk -v: one argument may not exceed 128 KiB, and a release
  # lists over a thousand entries.
  lf="$(mktemp 2>/dev/null)" || { ZIP_ERROR="no temporary file"; return 1; }
  printf '%s\n' "${list}" >"${lf}"
  res="$(while read -r off len bytes; do
      dd if="${zip}" bs=4096 iflag=skip_bytes,count_bytes skip="${off}" count="$((30 + len))" 2>/dev/null
    done <"${lf}" | od -An -v -tu1 | awk -v lf="${lf}" '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      ne = 0
      while ((getline l < lf) > 0) line[++ne] = l
      p = 0
      for (e = 1; e <= ne; e++) {
        split(line[e], f, " "); nl = f[2]; split(f[3], want, ",")
        if (p + 30 + nl > n || b[p] != 80 || b[p + 1] != 75 || b[p + 2] != 3 || b[p + 3] != 4 ||
          b[p + 26] + 256 * b[p + 27] != nl) { print "BAD"; exit }
        for (i = 0; i < nl; i++) if (b[p + 30 + i] != want[i + 1]) { print "BAD"; exit }
        p += 30 + nl
      }
      print (p == n) ? "OK" : "BAD"
    }')"
  rm -f "${lf}"
  if [ "${res}" != "OK" ]; then
    ZIP_ERROR="an entry is stored under another name than its archive listing shows"
    return 1
  fi
  return 0
}

###############################################################################
# The SHA-256 GitHub lists for a release asset ("digest": "sha256:<hex>"), read
# from the release API over a checked connection, or nothing.
# 1 - releases API url, 2 - tag, 3 - asset name
function githubAssetSha256() {
  local RESPONSE
  RESPONSE="$(githubApiJsonRetry "${1}/tags/${2}")" || return 1
  echo "${RESPONSE}" | jq -r --arg asset "${3}" '.assets[]? | select(.name == $asset) | .digest // empty' 2>/dev/null |
    sed -n 's/^sha256:\([0-9a-f]\{64\}\)$/\1/p' | head -1
}

###############################################################################
# A downloaded release zip is the one GitHub lists, and unpacks inside the
# directory it goes to. The components (addons, modules, custom kernel,
# configs, patches, LKMs) and the image were installed as downloaded, with
# curl -k, so whatever answered became part of the loader. On failure the zip
# is removed and the reason shown; nothing was changed yet.
# 1 - zip, 2 - releases API url, 3 - tag, 4 - asset name, 5 - dialog title
function checkReleaseZip() {
  local WANT HAVE MSG=""
  WANT="$(githubAssetSha256 "${2}" "${3}" "${4}")"
  HAVE="$(sha256sum "${1}" 2>/dev/null | awk '{print $1}')"
  if [ -z "${WANT}" ]; then
    MSG="GitHub lists no checksum for ${4} (or the release could not be read)"
  elif [ "${WANT}" != "${HAVE}" ]; then
    MSG="${4} does not match the checksum GitHub lists for it"
  elif ! zipPathsOk "${1}"; then
    MSG="${4} was refused: ${ZIP_ERROR}"
  else
    return 0
  fi
  rm -f "${1}"
  dialog --backtitle "$(backtitle)" --title "${5}" --aspect 18 \
    --infobox "${MSG}.\nNothing was changed." 0 0
  sleep 3
  return 1
}

###############################################################################
# A download that failed, in a line: a wrong clock is the usual reason a
# certificate does not verify, and the loader checks certificates.
DOWNLOAD_FAILED="Download failed! Check the network, and the date and time (a wrong clock fails the certificate check)."

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

      local TMP_AVAILABLE
      TMP_AVAILABLE="$(df --output=avail "${TMP_PATH}" | tail -1)"
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
        updateAborted "${DOWNLOAD_FAILED}"
        return 1
      fi
    fi
  fi

  if validateZipFile "${TMP_PATH}/update.zip" 1048576; then
    if [ "${TAG}" != "zip" ]; then
      local HASH_URL="${UPDATE_URL}/${TAG}/update-${TAG}.hash"
      [ "${BETA}" = "true" ] && HASH_URL="${BETA_URL}/${TAG}/update-${TAG}.hash"
      # The hash the release publishes beside the zip, with its certificate
      # checked (until now with -k). One that cannot be had is a failure,
      # never a reason to skip the check.
      HASH="$(curl -fsSL --proto '=https' --proto-redir '=https' -m 30 --retry 3 --retry-delay 2 --retry-all-errors "${HASH_URL}" 2>/dev/null | awk 'NR == 1 {print tolower($1)}')"
      if [ "${#HASH}" -ne 64 ] || [ -n "${HASH//[0-9a-f]/}" ]; then
        rm -f "${TMP_PATH}/update.zip"
        updateAborted "Update failed - update-${TAG}.hash, the checksum of the release, could not be fetched.\nNothing was changed. Check the network and the date and time, and try again."
        return 1
      fi
      if [ "${HASH}" != "$(sha256sum "${TMP_PATH}/update.zip" | awk '{print $1}')" ]; then
        rm -f "${TMP_PATH}/update.zip"
        updateAborted "Update failed - Hash mismatch!\nTry again later."
        return 1
      fi
    fi

    # Every entry inside p1/ or p3/, before anything is removed: the zip is
    # unpacked into /mnt, where p2 - DSM's kernel and ramdisk - is mounted
    # beside them, and unzip itself turns "../x" into "x" and goes on. Also
    # for a zip given by hand, which has no published hash.
    if ! zipPathsOk "${TMP_PATH}/update.zip" p1 p3; then
      rm -f "${TMP_PATH}/update.zip"
      updateAborted "Update failed - the update was refused: ${ZIP_ERROR}.\nNothing was changed."
      return 1
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

    local NEW_VERSION
    NEW_VERSION="$(cat "${PART1_PATH}/ARC-VERSION" 2>/dev/null | head -1 | tr -d "[:space:]" | sed 's/^[v|V]//g')"
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
        TAG="$(curl -m 10 -sL "${API_URL}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | grep -v "dev" | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
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

      local TMP_AVAILABLE
      TMP_AVAILABLE="$(df --output=avail "${TMP_PATH}" | tail -1)"
      TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

      local FILE_SIZE
      FILE_SIZE=$(curl -sL --proto '=https' "${API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"arc-${TAG}.img.zip\") | .size")

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
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "${DOWNLOAD_FAILED}" 0 0
        sleep 3
        return 1
      fi
    fi
  fi
  # The image is written over the whole loader disk, so it has to be the one
  # the release lists (until now nothing checked it), and a zip given by hand
  # still has to unpack inside TMP_PATH.
  if [ "${TAG}" != "zip" ] && [ -f "${TMP_PATH}/arc.img.zip" ] &&
    ! checkReleaseZip "${TMP_PATH}/arc.img.zip" "${API_URL}" "${TAG}" "arc-${TAG}.img.zip" "Upgrade Loader"; then
    return 1
  fi
  if [ -f "${TMP_PATH}/arc.img.zip" ] && ! zipPathsOk "${TMP_PATH}/arc.img.zip"; then
    rm -f "${TMP_PATH}/arc.img.zip"
    dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
      --infobox "The image was refused: ${ZIP_ERROR}.\nNothing was changed." 0 0
    sleep 3
    return 1
  fi
  if validateZipFile "${TMP_PATH}/arc.img.zip" 1048576; then
    local TMP_AVAILABLE
    TMP_AVAILABLE="$(df --output=avail "${TMP_PATH}" | tail -1)"
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))
    local FILE_SIZE
    FILE_SIZE="$(stat -c%s "${TMP_PATH}/arc.img.zip")"
    local REQUIRED_SPACE
    REQUIRED_SPACE="$((FILE_SIZE * 2))"

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
  local TAG=""
  idx=0
  while [ "${idx}" -le 5 ]; do
    TAG="$(curl -m 10 -sL "https://api.github.com/repos/AuxXxilium/arc-addons/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons-${TAG}.zip"

    local TMP_AVAILABLE
    TMP_AVAILABLE="$(df --output=avail "${TMP_PATH}" | tail -1)"
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

    local FILE_SIZE
    FILE_SIZE=$(curl -sL "${ADDONS_API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"addons-${TAG}.zip\") | .size")

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
    if validateZipFile "${TMP_PATH}/addons.zip" 1024 &&
      checkReleaseZip "${TMP_PATH}/addons.zip" "${ADDONS_API_URL}" "${TAG}" "addons-${TAG}.zip" "Update Addons"; then
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
  local TAG=""
    idx=0
    while [ "${idx}" -le 5 ]; do
      TAG="$(curl -m 10 -sL "https://api.github.com/repos/AuxXxilium/arc-patches/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
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
    if validateZipFile "${TMP_PATH}/patches.zip" 1024 &&
      checkReleaseZip "${TMP_PATH}/patches.zip" "https://api.github.com/repos/AuxXxilium/arc-patches/releases" "${TAG}" "patches-${TAG}.zip" "Update Patches"; then
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
  local TAG=""
  idx=0
  while [ "${idx}" -le 5 ]; do
    TAG="$(curl -m 10 -sL "https://api.github.com/repos/AuxXxilium/arc-custom/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-custom/releases/download/${TAG}/custom-${TAG}.zip"

    local TMP_AVAILABLE
    TMP_AVAILABLE="$(df --output=avail "${TMP_PATH}" | tail -1)"
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

    local FILE_SIZE
    FILE_SIZE=$(curl -sL "${CUSTOM_API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"custom-${TAG}.zip\") | .size")

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
    if validateZipFile "${TMP_PATH}/custom.zip" 1024 &&
      checkReleaseZip "${TMP_PATH}/custom.zip" "${CUSTOM_API_URL}" "${TAG}" "custom-${TAG}.zip" "Update Custom"; then
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
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${P_FILE}")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${P_FILE}")"
  local TAG=""
  idx=0
  while [ "${idx}" -le 5 ]; do
    TAG="$(curl -m 10 -sL "https://api.github.com/repos/AuxXxilium/arc-modules/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
    if [ -n "${TAG}" ]; then
      break
    fi
    sleep 3
    idx=$((${idx} + 1))
  done
  if [ -n "${TAG}" ]; then
    export TAG="${TAG}"
    export URL="https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules-${TAG}.zip"

    local TMP_AVAILABLE
    TMP_AVAILABLE="$(df --output=avail "${TMP_PATH}" | tail -1)"
    TMP_AVAILABLE=$((TMP_AVAILABLE * 1024))

    local FILE_SIZE
    FILE_SIZE=$(curl -sL "${MODULES_API_URL}/tags/${TAG}" | jq ".assets[] | select(.name == \"modules-${TAG}.zip\") | .size")

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

    if ! downloadWithGauge "${URL}" "${TMP_PATH}/modules.zip" "Download Modules: ${TAG}..."; then
      return 1
    fi
    if validateZipFile "${TMP_PATH}/modules.zip" 1024 &&
      checkReleaseZip "${TMP_PATH}/modules.zip" "${MODULES_API_URL}" "${TAG}" "modules-${TAG}.zip" "Update Modules"; then
      # The old set goes only now, once the new one checked out.
      rm -rf "${MODULES_PATH}"
      mkdir -p "${MODULES_PATH}"
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
      while read -r ID _; do
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
  local TAG=""
  if [ -z "${1}" ]; then
    idx=0
    while [ "${idx}" -le 5 ]; do
      TAG="$(curl -m 10 -sL "https://api.github.com/repos/AuxXxilium/arc-configs/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
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
    if validateZipFile "${TMP_PATH}/configs.zip" 1024 &&
      checkReleaseZip "${TMP_PATH}/configs.zip" "https://api.github.com/repos/AuxXxilium/arc-configs/releases" "${TAG}" "configs-${TAG}.zip" "Update Configs"; then
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
  local TAG=""
  if [ -z "${1}" ]; then
    idx=0
    while [ "${idx}" -le 5 ]; do
      TAG="$(curl -m 10 -sL "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
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
    if validateZipFile "${TMP_PATH}/rp-lkms.zip" 1024 &&
      checkReleaseZip "${TMP_PATH}/rp-lkms.zip" "https://api.github.com/repos/AuxXxilium/arc-lkm/releases" "${TAG}" "rp-lkms.zip" "Update LKMs"; then
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
    [ -n "${REPO}" ] && REMOTE="$(curl -m 10 -sL "https://api.github.com/repos/${REPO}/releases" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' 2>/dev/null | sort -rV | sed -n 1p | sed 's/^[v|V]//g')"
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