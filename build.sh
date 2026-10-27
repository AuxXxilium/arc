#!/usr/bin/env bash
#
# Copyright (C) 2026 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# Build an Arc image locally, end to end:
#
#   1. pull       update the working tree (fast-forward only)
#   2. deps       addons, modules, configs, patches, custom, LKMs, theme:
#                 fetched once and reused, again with --refresh or --release
#   3. buildroot  loader kernel + initramfs, built here from the build's own
#                 clone of arc-buildroot-essential's main and of Buildroot,
#                 both in work/ (AUX_TOKEN), only what changed
#   4. pack       arc.img and arc.vmdk, on a disk made here: GRUB built from
#                 source once into work/, partitions, ARC1-3, grub-install
#
#   ./build.sh                      the build menu on a terminal, else all
#                                   four. The menu asks whether to pack the
#                                   release files too
#   ./build.sh deps pack            only the stages named
#   ./build.sh --no-pull            all but the pull (also --no-deps,
#                                   --no-buildroot, --no-pack)
#   ./build.sh --refresh            fetch the dependencies again
#   ./build.sh --clean-buildroot    buildroot from an empty output tree
#   ./build.sh --essential          the Essential variant, as build.yml makes
#                                   it: no 4.4 kernel modules or LKMs, the
#                                   Essential platforms, and arc-essential as
#                                   the loader's update source
#   ./build.sh --release            then the release files as build.yml packs
#                                   them: img, vmdk (flat and dynamic), vhd,
#                                   vhdx and ova zips, the update zip and its
#                                   hash, with the latest dependencies.
#                                   Asks for the version, and once the
#                                   files are written whether to publish them:
#                                   as a stable (arc) or beta (arc-beta)
#                                   release, or for --essential to
#                                   arc-essential (AUX_TOKEN)
#   ./build.sh --stable             --release, published to arc without asking
#   ./build.sh --beta               --release, published to arc-beta without
#                                   asking
#   ./build.sh --essential --publish
#                                   --release, published to arc-essential
#                                   without asking (--publish alone: arc)
#   --no-publish                    --release, and do not ask
#   --replace                       a release already published may have its
#                                   files replaced (build.yml's allowUpdates)
#
# Environment: AUX_TOKEN, VERSION, BUILDROOT_REF (pin a Buildroot tag),
# KERNEL_VERSION (pin a kernel of arc_defconfig's series), BR_CONFIG (an
# arc-buildroot-essential checkout to build instead of the clone), JOBS.
#
# Unlike before, no `git clean -fdx`: the buildroot tree in work/ takes an
# hour to build. Only the build's own output is removed.

set -eo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${HERE}"

. scripts/functions.sh "${AUX_TOKEN}"

# --------------------------------------------------------------- config ---

WORK="${HERE}/work"
# The dependency and buildroot versions the release notes list, kept so a
# pack without those stages still names what it packed.
STATE="${WORK}/versions.env"

# Buildroot, as arc-buildroot-essential's workflow builds it: the newest
# release of BUILDROOT_SERIES unless BUILDROOT_REF pins one, and the newest
# kernel of arc_defconfig's series unless KERNEL_VERSION pins one.
BR_SRC="${WORK}/buildroot"
BR_OUT="${BR_SRC}/output"
BUILDROOT_URL="${BUILDROOT_URL:-https://github.com/buildroot/buildroot.git}"
BUILDROOT_SERIES="${BUILDROOT_SERIES:-2026.02}"
BUILDROOT_REF="${BUILDROOT_REF:-}"
KERNEL_VERSION="${KERNEL_VERSION:-}"
BR_CONFIG_REPO="AuxXxilium/arc-buildroot-essential"
BR_CONFIG="${BR_CONFIG:-}"
# arc-buildroot-essential's out-of-tree drivers, checked after a build
# (check_buildroot): the Realtek NICs and the ITE fan chips.
OOT_DRIVERS="it87 r8125 r8126 r8127 r8168 r8169"

# GRUB, built from source once into work/ (build_grub) and installed on a
# disk of arc's layout once per GRUB build (make_grub_disk): MBR, p1 FAT32
# ARC1 (GRUB, active), p2 ext2 ARC2 (DSM's kernel and ramdisk), p3 ext4
# ARC3 (the loader and everything else). The loader finds its partitions by
# these labels, and grub.cfg finds p3 by ARC3: not cosmetic.
GRUB_VERSION="${GRUB_VERSION:-grub-2.14}"
GRUB_URL="${GRUB_URL:-https://ftp.gnu.org/gnu/grub}"
GRUB_TARGETS="i386-pc i386-efi x86_64-efi"
GRUB_SRC="${WORK}/${GRUB_VERSION}"
LABEL="ARC"
P1_SIZE=50
P2_SIZE=50
IMAGE_SIZE=3700
# The empty disk, GRUB on it and nothing else: what the pack writes the
# loader onto, and what Clone Loader writes to another disk (it goes into
# the initrd as /opt/arc/grub.img.gz).
GRUB_DISK="${WORK}/grub.img.gz"

STABLE_REPO="${STABLE_REPO:-AuxXxilium/arc}"
BETA_REPO="${BETA_REPO:-AuxXxilium/arc-beta}"
ESSENTIAL_REPO="${ESSENTIAL_REPO:-AuxXxilium/arc-essential}"

# What goes into the image and the update zip: copies of files/p1, files/p3
# and files/initrd, so the version files, the Essential edits and the GRUB
# update never touch the tracked tree or the fetched dependencies.
STAGE="${WORK}/stage"

IMAGE_FILE="arc.img"
DEV_VERSION="13.3.7"
BUILD="$(date +'%y%m%d')"
BUILD_TIME="$(date +'%Y-%m-%d %H:%M')"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

# ---------------------------------------------------------------- output ---

log() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    warning:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\n\033[1;31m==> error:\033[0m %s\n' "$*" >&2
  exit 1
}

step=0
steps_total=0
stage() {
  step=$((step + 1))
  log "${step}/${steps_total}  $*"
}

# remember <key> <value>
remember() {
  mkdir -p "${WORK}"
  touch "${STATE}"
  sed -i "/^${1}=/d" "${STATE}"
  printf '%s=%q\n' "${1}" "${2}" >>"${STATE}"
}

# --------------------------------------------------------------- stages ---

do_pull=1 do_deps=1 do_buildroot=1 do_pack=1
do_brclean=0 do_release=0 do_replace=0
# --refresh: fetch the dependencies again rather than reuse them. A release
# always does (set in the driver): it ships what is current.
do_refresh=0
# full or essential.
variant="full"
# Where the release goes: stable, beta or essential without asking, no to
# keep it local, empty to ask once the files are written.
publish_to=""
explicit=0

for arg in "$@"; do
  case "${arg}" in
  pull | deps | buildroot | pack)
    if [ "${explicit}" -eq 0 ]; then
      do_pull=0 do_deps=0 do_buildroot=0 do_pack=0
      explicit=1
    fi
    eval "do_${arg}=1"
    ;;
  --no-pull) do_pull=0 ;;
  --no-deps) do_deps=0 ;;
  --no-buildroot) do_buildroot=0 ;;
  --no-pack) do_pack=0 ;;
  --refresh) do_refresh=1 ;;
  --clean-buildroot) do_brclean=1 ;;
  --essential) variant="essential" ;;
  --release) do_release=1 ;;
  --stable) do_release=1 publish_to="stable" ;;
  --beta) do_release=1 publish_to="beta" ;;
  --publish) do_release=1 publish_to="auto" ;;
  --no-publish) do_release=1 publish_to="no" ;;
  --replace) do_replace=1 ;;
  -h | --help)
    sed -n '/^# Build an Arc image/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) die "unknown argument: ${arg}" ;;
  esac
done

# Essential has one release repository, the full loader two.
if [ "${publish_to}" = "auto" ]; then
  [ "${variant}" = "essential" ] && publish_to="essential" || publish_to="stable"
fi
if [ "${variant}" = "essential" ]; then
  case "${publish_to}" in
  stable | beta) die "Essential is published to ${ESSENTIAL_REPO} only: --essential --publish." ;;
  esac
fi

# ------------------------------------------------------------ toolchecks ---

# Collected rather than fatal on the first one, so a host short three
# packages says so once.
missing_cmds=""
missing_pkgs=""

# need <command> [package]
need() {
  command -v "${1}" >/dev/null 2>&1 && return 0
  missing_cmds="${missing_cmds} ${1}"
  missing_pkgs="${missing_pkgs} ${2:-${1}}"
}

# need_header <file> <package>
need_header() {
  [ -e "/usr/include/${1}" ] && return 0
  missing_cmds="${missing_cmds} ${1}"
  missing_pkgs="${missing_pkgs} ${2}"
}

# need_pkg <pkg-config name> <package>
#
# For a library found through pkg-config rather than on the include path:
# freetype, which GRUB's font tool needs.
need_pkg() {
  command -v pkg-config >/dev/null 2>&1 || return 0 # reported as pkg-config
  pkg-config --exists "${1}" 2>/dev/null && return 0
  missing_cmds="${missing_cmds} ${1}"
  missing_pkgs="${missing_pkgs} ${2}"
}

check_tools() {
  need git
  need curl
  need jq
  if [ "${do_deps}" -eq 1 ] || [ "${do_buildroot}" -eq 1 ]; then
    need unzip
    need tar
  fi
  if [ "${do_buildroot}" -eq 1 ]; then
    need make "build-essential"
    need gcc "build-essential"
    need g++ "build-essential"
    need bc
    need flex
    need bison
    need rsync
    need patch
    need cpio
    need file
    need perl
    need wget
    need cmp "diffutils"
    need sha256sum "coreutils"
    need_header "elf.h" "libelf-dev"
    need_header "openssl/ssl.h" "libssl-dev"
  fi
  if [ "${do_pack}" -eq 1 ]; then
    need sudo
    need losetup "util-linux"
    need qemu-img "qemu-utils"
    need cpio
    need file
    need zstd
    need gzip
    need zip
    need sha256sum "coreutils"
    if [ "${do_release}" -eq 1 ]; then
      need unzip
    fi

    # The disk, once per GRUB build.
    if [ ! -f "${GRUB_DISK}" ] || [ "$(cat "${WORK}/grub.fingerprint" 2>/dev/null)" != "$(grub_fingerprint)" ]; then
      need fdisk
      need mkdosfs "dosfstools"
      need mkfs.ext2 "e2fsprogs"
      need mkfs.ext4 "e2fsprogs"
    fi
    # GRUB, once per work/. A release tarball ships its configure: no
    # autoconf, automake or libtool.
    if [ ! -f "${GRUB_SRC}/.built" ]; then
      need make "build-essential"
      need gcc "build-essential"
      need pkg-config
      need msgfmt "gettext"
      need gawk
      need bison
      need flex
      need python3
      need_pkg "freetype2" "libfreetype6-dev"
      need_header "zlib.h" "zlib1g-dev"
      need_header "lzma.h" "liblzma-dev"
      need_header "libdevmapper.h" "libdevmapper-dev"
      # What GRUB makes fonts/unicode.pf2 from, grub.cfg's font.
      if [ -z "$(find /usr/share/fonts -iname 'unifont*' -print -quit 2>/dev/null)" ]; then
        missing_cmds="${missing_cmds} unifont"
        missing_pkgs="${missing_pkgs} unifont"
      fi
    fi
  fi

  [ -z "${missing_cmds}" ] && return 0

  local cmds pkgs
  cmds="$(printf '%s\n' ${missing_cmds} | sort -u | tr '\n' ' ')"
  pkgs="$(printf '%s\n' ${missing_pkgs} | sort -u | tr '\n' ' ')"
  printf '\n\033[1;31m==> missing:\033[0m %s\n\n' "${cmds}" >&2
  printf '    Install them:\n\n      sudo apt install -y %s\n\n' "${pkgs}" >&2
  exit 1
}

# ============================================================= 1. pull ===

stage_pull() {
  stage "pull"

  if [ ! -d .git ]; then
    warn "not a git checkout, nothing to pull"
    return 0
  fi

  # Tracked changes only: the build leaves untracked files all over files/,
  # and they cannot conflict with a fast-forward. A real local edit stops
  # the pull rather than being reset away.
  if [ -n "$(git status --porcelain -uno)" ]; then
    warn "tracked files have local changes, skipping pull"
    git status --short -uno | sed 's/^/    /'
    return 0
  fi

  local before after
  before="$(git rev-parse HEAD)"
  info "$(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
  git pull --ff-only
  after="$(git rev-parse HEAD)"
  info "now at $(git rev-parse --short HEAD)"

  [ "${before}" = "${after}" ] && return 0

  # bash reads a script as it runs it: carrying on in a script the pull
  # just rewrote runs half of each. Hand over to the new one, once.
  if [ -n "${ARC_PULLED}" ]; then
    warn "already re-executed once, continuing without another"
    return 0
  fi

  local rest=""
  [ "${do_deps}" -eq 1 ] || rest="${rest} --no-deps"
  [ "${do_buildroot}" -eq 1 ] || rest="${rest} --no-buildroot"
  [ "${do_pack}" -eq 1 ] || rest="${rest} --no-pack"
  [ "${do_brclean}" -eq 1 ] && rest="${rest} --clean-buildroot"
  [ "${do_refresh}" -eq 1 ] && rest="${rest} --refresh"
  [ "${do_release}" -eq 1 ] && rest="${rest} --release"
  [ "${do_replace}" -eq 1 ] && rest="${rest} --replace"
  [ "${variant}" = "essential" ] && rest="${rest} --essential"
  case "${publish_to}" in
  stable | beta) rest="${rest} --${publish_to}" ;;
  essential) rest="${rest} --publish" ;;
  no) rest="${rest} --no-publish" ;;
  esac

  chmod 0755 "${HERE}/build.sh" 2>/dev/null || true
  info "restarting with the new build.sh"
  # shellcheck disable=SC2086
  ARC_PULLED=1 exec "${HERE}/build.sh" --no-pull ${rest}
}

# ============================================================= 2. deps ===

# Written once every dependency is in files/, so an interrupted fetch is
# fetched again rather than reused.
DEPS_DONE="${WORK}/deps.done"

stage_deps() {
  stage "deps"

  # Fetched once and reused, as arx stages its artifacts: they are a few
  # hundred MB over the API, and a build that only changed the loader does
  # not need new ones. --refresh, menu 7 and every release fetch them again.
  if [ "${do_refresh}" -eq 0 ] && [ -f "${DEPS_DONE}" ]; then
    (. "${STATE}" && info "already fetched: addons ${ADDONTAG}, modules ${MODULETAG}, custom ${CUSTOMTAG}, lkms ${LKMTAG}")
    info "--refresh (menu 7) fetches them again"
    return 0
  fi
  rm -f "${DEPS_DONE}"

  # What an earlier build left: not every get* empties its destination
  # first, and the theme unpacks over p1.
  git clean -fdxq -- files/p1 files/p3

  getAddons "files/p3/addons" || die "could not get the addons"
  getModules "files/p3/modules" || die "could not get the modules"
  getConfigs "files/p3/configs" || die "could not get the configs"
  getPatches "files/p3/patches" || die "could not get the patches"
  getCustom "files/p3/custom" || die "could not get custom"
  getLKMs "files/p3/lkms" || die "could not get the LKMs"
  getTheme "files/p1/boot/grub" || die "could not get the theme"

  remember ADDONTAG "${ADDONTAG}"
  remember MODULETAG "${MODULETAG}"
  remember CONFIGTAG "${CONFIGTAG}"
  remember PATCHTAG "${PATCHTAG}"
  remember CUSTOMTAG "${CUSTOMTAG}"
  remember LKMTAG "${LKMTAG}"
  remember THEMETAG "${THEMETAG}"
  touch "${DEPS_DONE}"
}

# ======================================================== 3. buildroot ===

# The token goes to git through the environment, not the command line,
# where any user on the host could read it.
github_git() {
  if [ -n "${AUX_TOKEN}" ]; then
    GIT_CONFIG_COUNT=1 \
      GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" \
      GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "${AUX_TOKEN}" | base64 -w0)" \
      git "$@"
  else
    git "$@"
  fi
}

# The arc-buildroot-essential tree to build: the build's own clone in work/,
# brought to origin/main on every build, so nothing already on the build
# host is reused. BR_CONFIG names another checkout, only when set.
resolve_br_config() {
  if [ -n "${BR_CONFIG}" ]; then
    [ -f "${BR_CONFIG}/arc/configs/arc_defconfig" ] ||
      die "BR_CONFIG=${BR_CONFIG} is not an arc-buildroot-essential checkout."
  else
    BR_CONFIG="${WORK}/arc-buildroot-essential"
    if [ -d "${BR_CONFIG}/.git" ]; then
      github_git -C "${BR_CONFIG}" fetch -q origin main ||
        die "could not fetch ${BR_CONFIG_REPO} (can AUX_TOKEN read it?)"
      git -C "${BR_CONFIG}" reset -q --hard FETCH_HEAD
    else
      mkdir -p "${WORK}"
      github_git clone -q "https://github.com/${BR_CONFIG_REPO}.git" "${BR_CONFIG}" ||
        die "could not clone ${BR_CONFIG_REPO} (can AUX_TOKEN read it?)"
    fi
  fi

  BR_CONFIG_REV="$(git -C "${BR_CONFIG}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  if [ -n "$(git -C "${BR_CONFIG}" status --porcelain 2>/dev/null)" ]; then
    BR_CONFIG_REV="${BR_CONFIG_REV}-dirty"
  fi
  info "config            ${BR_CONFIG} @ ${BR_CONFIG_REV}"
}

# The release tag the buildroot checkout is at; empty without one.
buildroot_ref() {
  git -C "${BR_SRC}" describe --tags --exact-match HEAD 2>/dev/null || true
}

# BUILDROOT_REF when set, else the newest BUILDROOT_SERIES release upstream.
# Offline, the one checked out, so the build is the same build again.
resolve_buildroot() {
  if [ -n "${BUILDROOT_REF}" ]; then
    info "buildroot         ${BUILDROOT_REF} (BUILDROOT_REF)"
    return 0
  fi
  BUILDROOT_REF="$(git ls-remote --tags --refs "${BUILDROOT_URL}" "refs/tags/${BUILDROOT_SERIES}*" 2>/dev/null |
    sed -n "s|.*refs/tags/\(${BUILDROOT_SERIES//./\\.}\(\.[0-9]*\)\{0,1\}\)\$|\1|p" |
    sort -V | tail -n 1)" || true
  if [ -n "${BUILDROOT_REF}" ]; then
    info "buildroot         ${BUILDROOT_REF} (newest ${BUILDROOT_SERIES} release)"
    return 0
  fi
  BUILDROOT_REF="$(buildroot_ref)"
  [ -n "${BUILDROOT_REF}" ] || die "no buildroot release: ${BUILDROOT_URL} unreachable and none cloned."
  warn "${BUILDROOT_URL} unreachable, building with buildroot ${BUILDROOT_REF} as before"
}

# The kernel, as the workflow sets it: KERNEL_VERSION when set, else the
# newest point release of arc_defconfig's series. Offline, the one the last
# build used, so the build is the same build again.
#
# Sets KERNEL_VERSION, KERNEL_HASH and KERNEL_HDR.
resolve_kernel() {
  local kseries sums

  kseries="$(sed -nE 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="([0-9]+\.[0-9]+)\..*"$/\1/p' "${BR_CONFIG}/arc/configs/arc_defconfig")"
  [ -n "${kseries}" ] || die "arc_defconfig names no kernel version."

  if sums="$(curl -fsSL --retry 3 "https://cdn.kernel.org/pub/linux/kernel/v${kseries%%.*}.x/sha256sums.asc")"; then
    if [ -z "${KERNEL_VERSION}" ]; then
      KERNEL_VERSION="$(sed -nE "s/^[0-9a-f]{64}  linux-(${kseries//./\\.}\.[0-9]+)\.tar\.xz$/\1/p" <<<"${sums}" |
        sort -t. -k3,3n | tail -1)"
    fi
    KERNEL_HASH="$(grep -E "^[0-9a-f]{64}  linux-${KERNEL_VERSION//./\\.}\.tar\.xz$" <<<"${sums}" | cut -d' ' -f1)" || true
  else
    KERNEL_VERSION="${KERNEL_VERSION:-$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\(.*\)"$/\1/p' "${BR_OUT}/.config" 2>/dev/null)}"
    KERNEL_HASH="$(sed -n "s/^sha256  \([0-9a-f]\{64\}\)  linux-${KERNEL_VERSION//./\\.}\.tar\.xz$/\1/p" \
      "${BR_SRC}/external/hashes/linux/linux.hash" 2>/dev/null)"
    [ -n "${KERNEL_VERSION}" ] && [ -n "${KERNEL_HASH}" ] ||
      die "kernel.org is unreachable and there is no earlier build to take the kernel from."
    warn "kernel.org unreachable, building kernel ${KERNEL_VERSION} as before"
  fi

  case "${KERNEL_VERSION}" in
  "${kseries}".[0-9]*) ;;
  *) die "kernel '${KERNEL_VERSION}' is not a ${kseries} release; arc_defconfig's series changes by a commit." ;;
  esac
  [ -n "${KERNEL_HASH}" ] || die "no sha256 for linux-${KERNEL_VERSION}.tar.xz on kernel.org."
  info "kernel            ${KERNEL_VERSION}"

  KERNEL_HDR="BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_${kseries/./_}"
  grep -qx "config ${KERNEL_HDR}" "${BR_SRC}/package/linux-headers/Config.in.host" ||
    die "buildroot ${BUILDROOT_REF} has no headers choice for kernel ${kseries} (${KERNEL_HDR})."
}

# What a build is made of: the Buildroot release, the kernel and the content
# of arc-buildroot-essential's arc/. The same as the last finished build's
# means there is nothing to build.
br_fingerprint() {
  {
    echo "${BUILDROOT_REF} ${KERNEL_VERSION} ${KERNEL_HASH}"
    (cd "${BR_CONFIG}/arc" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
  } | sha256sum | cut -d' ' -f1
}

# install_if_changed <file> <dest>
#
# Replaces dest only when the content differs and says whether it did: an
# unchanged file keeps its mtime, and Buildroot sees nothing new.
install_if_changed() {
  if cmp -s "${1}" "${2}"; then
    rm -f "${1}"
    return 1
  fi
  mkdir -p "$(dirname "${2}")"
  mv -f "${1}" "${2}"
}

# The workflow's `cp -rf arc/* buildroot/`, which arc_defconfig's paths are
# relative to, with the kernel's version, headers series and sha256 written
# into the defconfig and hash files. rsync takes only what changed, and
# --delete a file removed there; the hash files are left to the writes
# below.
sync_br_config() {
  local tmp="${WORK}/sync.tmp" f

  mkdir -p "${BR_SRC}/board/arc" "${BR_SRC}/external"
  rsync -a --delete "${BR_CONFIG}/arc/board/arc/" "${BR_SRC}/board/arc/"
  rsync -a --delete \
    --exclude "/hashes/linux/linux.hash" --exclude "/hashes/linux-headers/linux-headers.hash" \
    "${BR_CONFIG}/arc/external/" "${BR_SRC}/external/"

  sed -E \
    -e "s|^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE=.*|BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE=\"${KERNEL_VERSION}\"|" \
    -e "s|^BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_[0-9_]+=y|${KERNEL_HDR}=y|" \
    "${BR_CONFIG}/arc/configs/arc_defconfig" >"${tmp}"
  install_if_changed "${tmp}" "${BR_SRC}/configs/arc_defconfig" && info "arc_defconfig changed"

  # linux-headers downloads the same tarball first, under its own name.
  for f in linux/linux.hash linux-headers/linux-headers.hash; do
    {
      echo "# From https://www.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/sha256sums.asc"
      echo "sha256  ${KERNEL_HASH}  linux-${KERNEL_VERSION}.tar.xz"
    } >"${tmp}"
    install_if_changed "${tmp}" "${BR_SRC}/external/hashes/${f}" || true
  done
}

# The BR2_PACKAGE_ options of a .config, sorted, a switch-off as SYM=n.
package_options() {
  sed -n -e 's/^\(BR2_PACKAGE_[A-Z0-9_]*=.*\)/\1/p' \
    -e 's/^# \(BR2_PACKAGE_[A-Z0-9_]*\) is not set$/\1=n/p' "${1}" | sort
}

# The target architecture options of a .config: the toolchain is built for
# them, so a change means building everything again.
arch_options() {
  grep -E '^BR2_(ARCH|GCC_TARGET_[A-Z_]*|x86_[a-z0-9_]*)=' "${1}" | sort || true
}

# Buildroot does not rebuild a package whose options changed. Each option
# that differs from the previous configure is traced to the package it
# belongs to (the longest package name that is a prefix of it), and that
# package is dircleaned for the build to redo.
rebuild_changed_packages() {
  local prev="${1}" syms pkgs sym rest pkg name best orphans="" cleaned=""

  syms="$(comm -3 <(package_options "${prev}") <(package_options "${BR_OUT}/.config") |
    sed 's/^[[:space:]]*//; s/=.*//' | sort -u)"
  [ -n "${syms}" ] || return 0

  pkgs="$(make -s -C "${BR_SRC}" O="${BR_OUT}" show-targets)"
  for sym in ${syms}; do
    rest="${sym#BR2_PACKAGE_}"
    best=""
    for pkg in ${pkgs}; do
      name="$(printf '%s' "${pkg}" | tr 'a-z-' 'A-Z_')"
      case "${rest}" in
      "${name}" | "${name}"_*)
        if [ "${#pkg}" -gt "${#best}" ]; then best="${pkg}"; fi
        ;;
      esac
    done
    if [ -z "${best}" ]; then
      orphans="${orphans} ${sym}"
    else
      case " ${cleaned} " in
      *" ${best} "*) ;;
      *) cleaned="${cleaned} ${best}" ;;
      esac
    fi
  done

  for pkg in ${cleaned}; do
    info "options of ${pkg} changed, rebuilding it"
    make -s -C "${BR_SRC}" O="${BR_OUT}" "${pkg}-dirclean"
  done
  if [ -n "${orphans}" ]; then
    warn "changed options of packages no longer built:${orphans}
    Their files stay in the loader until --clean-buildroot."
  fi
}

# What a build that succeeded can still lack, as arx checks it: each is a
# loader that boots and is found out only on the hardware.
check_buildroot() {
  local drv mp

  # The out-of-tree drivers arc_defconfig enables have to be in the
  # loader's /lib/modules and in modules.order, not only built: a kernel
  # reinstalled after them empties lib/modules/<ver>/kernel, and the NIC
  # never comes up.
  for drv in ${OOT_DRIVERS}; do
    grep -qx "BR2_PACKAGE_${drv^^}=y" "${BR_OUT}/.config" || continue
    [ -n "$(find "${BR_OUT}/target/lib/modules" -name "${drv}.ko" 2>/dev/null)" ] ||
      die "${drv}.ko was built but is not in the loader's /lib/modules."
    grep -qs "/${drv}\.ko$" "${BR_OUT}"/target/lib/modules/*/modules.order ||
      die "${drv}.ko is not in modules.order."
  done

  # kmod's modprobe, not BusyBox's, which fails every call without a word.
  mp="$(readlink -f "${BR_OUT}/target/sbin/modprobe" 2>/dev/null)"
  [ "$(basename "${mp}")" = "kmod" ] ||
    die "the loader's modprobe is not kmod's (${mp:-none}).
    BR2_PACKAGE_KMOD_TOOLS needs BR2_PACKAGE_BUSYBOX_SHOW_OTHERS."
}

build_buildroot() {
  local prev="${WORK}/br.config.prev" fpfile="${WORK}/br.fingerprint" fp d

  mkdir -p "${WORK}"
  resolve_br_config
  resolve_buildroot

  if [ ! -d "${BR_SRC}/.git" ]; then
    git ls-remote --exit-code --tags --refs "${BUILDROOT_URL}" "refs/tags/${BUILDROOT_REF}" >/dev/null ||
      die "buildroot has no release ${BUILDROOT_REF}."
    info "cloning buildroot ${BUILDROOT_REF}"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "${BUILDROOT_REF}" "${BUILDROOT_URL}" "${BR_SRC}"
  elif [ "$(buildroot_ref)" != "${BUILDROOT_REF}" ]; then
    # Buildroot rebuilds nothing for a new release's package versions, so
    # the output starts over. The downloads (.buildroot-dl) stay.
    info "buildroot $(buildroot_ref) -> ${BUILDROOT_REF}, building everything again"
    git -C "${BR_SRC}" fetch -q --depth 1 origin tag "${BUILDROOT_REF}" ||
      die "could not fetch buildroot ${BUILDROOT_REF}."
    git -C "${BR_SRC}" checkout -q "${BUILDROOT_REF}"
    rm -rf "${BR_OUT}"
  fi
  if [ "${do_brclean}" -eq 1 ] && [ -d "${BR_OUT}" ]; then
    info "removing ${BR_OUT}"
    rm -rf "${BR_OUT}"
  fi

  resolve_kernel

  fp="$(br_fingerprint)"
  if [ -f "${BR_OUT}/images/bzImage" ] && [ -f "${BR_OUT}/images/rootfs.cpio.zst" ] &&
    [ "$(cat "${fpfile}" 2>/dev/null)" = "${fp}" ]; then
    info "nothing changed since the last build, reusing it"
  else
    # Gone until this build finishes: a failed one is not a finished one.
    rm -f "${fpfile}"
    sync_br_config

    # Reconfigured only when the defconfig changed, which sync_br_config
    # writes only then.
    if [ ! -f "${BR_OUT}/.config" ] || [ "${BR_SRC}/configs/arc_defconfig" -nt "${BR_OUT}/.config" ]; then
      info "configuring"
      rm -f "${prev}"
      [ -f "${BR_OUT}/.config" ] && cp -f "${BR_OUT}/.config" "${prev}"
      make -s -C "${BR_SRC}" O="${BR_OUT}" BR2_EXTERNAL="${BR_SRC}/external" arc_defconfig
      if [ -f "${prev}" ]; then
        if [ "$(arch_options "${prev}")" != "$(arch_options "${BR_OUT}/.config")" ]; then
          info "target architecture changed, building everything again"
          rm -rf "${BR_OUT}"
          make -s -C "${BR_SRC}" O="${BR_OUT}" BR2_EXTERNAL="${BR_SRC}/external" arc_defconfig
        else
          rebuild_changed_packages "${prev}"
        fi
        rm -f "${prev}"
      fi
    else
      info "configuration is current"
    fi
    # kconfig drops a line it cannot satisfy without a word.
    grep -qx "BR2_LINUX_KERNEL_VERSION=\"${KERNEL_VERSION}\"" "${BR_OUT}/.config" || die "the kernel version did not stick."
    grep -qx "${KERNEL_HDR}=y" "${BR_OUT}/.config" || die "${KERNEL_HDR} did not stick."

    # A new kernel builds in a directory of its own, but the old one's
    # modules stay in target/ and would go into the initramfs too.
    for d in "${BR_OUT}"/target/lib/modules/*; do
      [ -d "${d}" ] || continue
      if [ "${d##*/}" != "${KERNEL_VERSION}" ]; then
        info "removing kernel ${d##*/}'s modules from the target"
        rm -rf "${d}"
      fi
    done

    # Buildroot rebuilds what changed by its stamps, and external.mk makes
    # the out-of-tree drivers follow their sources and the kernel.
    # FORCE_UNSAFE_CONFIGURE: host-tar's configure refuses root otherwise.
    # BR2_JLEVEL rather than -j: the top level is .NOTPARALLEL anyway.
    info "building with ${JOBS} jobs (the first build takes a while)"
    FORCE_UNSAFE_CONFIGURE=1 make -C "${BR_SRC}" O="${BR_OUT}" BR2_JLEVEL="${JOBS}"

    [ -f "${BR_OUT}/images/bzImage" ] || die "buildroot produced no bzImage."
    [ -f "${BR_OUT}/images/rootfs.cpio.zst" ] || die "buildroot produced no rootfs.cpio.zst."
    check_buildroot
    echo "${fp}" >"${fpfile}"
  fi

  rm -rf br
  mkdir -p br
  cp -f "${BR_OUT}/images/bzImage" "br/bzImage-apex"
  cp -f "${BR_OUT}/images/rootfs.cpio.zst" "br/initrd-apex"
  remember APEX "local: buildroot ${BUILDROOT_REF}, kernel ${KERNEL_VERSION}, arc-buildroot-essential@${BR_CONFIG_REV}"
}

stage_buildroot() {
  stage "buildroot"
  build_buildroot
  info "bzImage-apex     $(du -h br/bzImage-apex | cut -f1)"
  info "initrd-apex       $(du -h br/initrd-apex | cut -f1)"
}

# ============================================================= 4. pack ===

MNT="${WORK}/mnt"
LOOPX=""

unmount_image() {
  local p
  for p in p1 p2 p3; do
    sudo umount "${MNT}/${p}" 2>/dev/null || true
    rmdir "${MNT}/${p}" 2>/dev/null || true
  done
  if [ -n "${LOOPX}" ]; then
    sudo losetup --detach "${LOOPX}" 2>/dev/null || true
    LOOPX=""
  fi
}

# A failed pack does not leave the image mounted or the loop device set up.
trap '[ -z "${LOOPX}" ] || unmount_image' EXIT

# attach_image <image>: LOOPX, with its partition nodes there.
attach_image() {
  unmount_image
  LOOPX="$(sudo losetup -P -f --show "${1}")"
  # losetup -P has the kernel scan the table, but udev makes the
  # /dev/loopNpN nodes afterwards: a fast machine gets to mkfs first.
  if command -v udevadm >/dev/null 2>&1; then
    sudo udevadm settle --timeout=10 2>/dev/null || true
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -b "${LOOPX}p3" ] && return 0
    sleep 0.5
  done
  die "the kernel did not create ${LOOPX}p3 for ${1}."
}

# GRUB for each target, from the release tarball, as scripts/grub.sh built
# it for the grub.img.gz arc used to carry. Once per work/: .built says the
# last one finished.
build_grub() {
  local t target platform

  if [ -f "${GRUB_SRC}/.built" ]; then
    info "grub              ${GRUB_VERSION}, already built"
    return 0
  fi

  rm -rf "${GRUB_SRC}"
  mkdir -p "${WORK}"
  info "fetching ${GRUB_VERSION}"
  curl -fsSL --retry 3 -o "${WORK}/${GRUB_VERSION}.tar.gz" "${GRUB_URL}/${GRUB_VERSION}.tar.gz" ||
    die "could not download ${GRUB_URL}/${GRUB_VERSION}.tar.gz."
  tar -zxf "${WORK}/${GRUB_VERSION}.tar.gz" -C "${WORK}"
  rm -f "${WORK}/${GRUB_VERSION}.tar.gz"

  # Without these the installed core cannot read the partition table or
  # find its own partition.
  echo "depends bli part_gpt part_msdos lvm" >"${GRUB_SRC}/grub-core/extra_deps.lst"

  for t in ${GRUB_TARGETS}; do
    target="${t%%-*}"
    platform="${t#*-}"
    info "building grub ${target} ${platform}"
    mkdir -p "${GRUB_SRC}/${t}/grub-core"
    # make install looks for it relative to the build directory.
    cp "${GRUB_SRC}/grub-core/extra_deps.lst" "${GRUB_SRC}/${t}/grub-core/extra_deps.lst"
    (
      cd "${GRUB_SRC}/${t}" &&
        ../configure --prefix="${PWD}/usr" --sbindir="${PWD}/sbin" --sysconfdir="${PWD}/etc" \
          --disable-werror --target="${target}" --with-platform="${platform}" >/dev/null &&
        make -j"${JOBS}" >/dev/null &&
        make install >/dev/null
    ) || die "could not build grub for ${t}."

    # grub-install copies from this tree: the translations (~6 MB) and the
    # stock starfield theme (~2.8 MB) would land on p1. Arc's theme comes
    # from arc-theme. The locale directory stays, empty, or grub-install
    # warns that it cannot open it.
    rm -rf "${GRUB_SRC}/${t}/usr/share/locale" "${GRUB_SRC}/${t}/usr/share/grub/locale" \
      "${GRUB_SRC}/${t}/usr/share/grub/themes"
    mkdir -p "${GRUB_SRC}/${t}/usr/share/locale"
  done

  touch "${GRUB_SRC}/.built"
}

# What the empty disk is made of. Bump the trailing layout number when
# make_grub_disk changes what it writes.
grub_fingerprint() {
  echo "${GRUB_VERSION} ${GRUB_TARGETS} ${LABEL} ${P1_SIZE} ${P2_SIZE} ${IMAGE_SIZE} 1"
}

# The empty disk: arc's partitions, formatted, GRUB installed for every
# target and nothing else, gzipped. Once per GRUB build, as grub.yml made
# grub.img.gz.
make_grub_disk() {
  local img="${WORK}/grub.img" parts t f args

  if [ -f "${GRUB_DISK}" ] && [ "$(cat "${WORK}/grub.fingerprint" 2>/dev/null)" = "$(grub_fingerprint)" ]; then
    info "grub disk         already made"
    return 0
  fi
  rm -f "${GRUB_DISK}" "${WORK}/grub.fingerprint"

  info "making the grub disk (${IMAGE_SIZE} MB)"
  rm -f "${img}"
  dd if=/dev/zero of="${img}" bs=1M seek="${IMAGE_SIZE}" count=0 status=none

  # MBR: p1 and p2 of their sizes, p3 the rest, p1 active for the BIOS
  # path. fdisk exits non-zero on the trailing q whether or not the write
  # worked, so the table is checked instead.
  printf 'n\np\n1\n\n+%sM\nn\np\n2\n\n+%sM\nn\np\n3\n\n\na\n1\nw\nq\n' "${P1_SIZE}" "${P2_SIZE}" |
    fdisk "${img}" >/dev/null 2>&1 || true
  # One "Disk <image>:" header line and one line per partition.
  parts="$(fdisk -l "${img}" 2>/dev/null | grep -cF "$(basename "${img}")" || true)"
  [ "$((parts - 1))" -eq 3 ] || die "the grub disk has $((parts - 1)) partitions, not 3. Run fdisk ${img} by hand to see why."

  attach_image "${img}"
  sudo mkdosfs -F32 -n "${LABEL}1" "${LOOPX}p1" >/dev/null
  sudo mkfs.ext2 -F -L "${LABEL}2" "${LOOPX}p2" >/dev/null 2>&1
  sudo mkfs.ext4 -F -L "${LABEL}3" "${LOOPX}p3" >/dev/null 2>&1

  mkdir -p "${MNT}/p1"
  sudo mount "${LOOPX}p1" "${MNT}/p1"
  sudo mkdir -p "${MNT}/p1/EFI" "${MNT}/p1/boot/grub"
  echo "(hd0)   ${LOOPX}" | sudo tee "${MNT}/p1/boot/grub/device.map" >/dev/null

  info "installing grub"
  for t in ${GRUB_TARGETS}; do
    args=("${LOOPX}" "--target=${t}" "--no-floppy" "--recheck"
      "--grub-mkdevicemap=${MNT}/p1/boot/grub/device.map" "--boot-directory=${MNT}/p1/boot")
    if [[ "${t}" == *efi ]]; then
      # EFI/BOOT/BOOT*.EFI, what firmware boots from a disk it has no NVRAM
      # entry for; and no NVRAM entry on this machine.
      args+=("--efi-directory=${MNT}/p1" "--removable" "--no-nvram")
    else
      args+=("--root-directory=${MNT}/p1")
    fi
    sudo "${GRUB_SRC}/${t}/sbin/grub-install" "${args[@]}" >/dev/null 2>&1 ||
      die "grub-install --target=${t} failed."
  done

  # grub.cfg's font, which grub-install places only when GRUB built it.
  if [ ! -f "${MNT}/p1/boot/grub/fonts/unicode.pf2" ]; then
    sudo mkdir -p "${MNT}/p1/boot/grub/fonts"
    for f in "${GRUB_SRC}"/*/usr/share/grub/unicode.pf2 /usr/share/grub/unicode.pf2; do
      if [ -f "${f}" ]; then
        sudo cp -f "${f}" "${MNT}/p1/boot/grub/fonts/"
        break
      fi
    done
  fi

  # grub-install says it succeeded for an install that left nothing to boot.
  local missing=""
  [ -f "${MNT}/p1/boot/grub/fonts/unicode.pf2" ] || missing="${missing} boot/grub/fonts/unicode.pf2 (install unifont and remove ${GRUB_SRC})"
  for t in ${GRUB_TARGETS}; do
    [ -f "${MNT}/p1/boot/grub/${t}/normal.mod" ] || missing="${missing} boot/grub/${t}/normal.mod"
  done
  for f in BOOTX64.EFI BOOTIA32.EFI; do
    [ -n "$(find "${MNT}/p1/EFI/BOOT" -maxdepth 1 -iname "${f}" -print -quit 2>/dev/null)" ] || missing="${missing} EFI/BOOT/${f}"
  done

  unmount_image
  [ -z "${missing}" ] || die "the grub disk is missing:${missing}"

  gzip -c "${img}" >"${GRUB_DISK}.tmp"
  mv -f "${GRUB_DISK}.tmp" "${GRUB_DISK}"
  rm -f "${img}"
  grub_fingerprint >"${WORK}/grub.fingerprint"
}

# build.yml's Essential cleanup, on the staged copies: no modules or LKMs
# for the 4.4 kernels, the Essential title and platform list, arc-essential
# as the update source, and no beta or dependency-only update in the
# loader's update menu. Every edit has to find its line first: one that no
# longer matches would ship the full loader under the Essential name.
make_essential() {
  local consts="${STAGE}/initrd/opt/arc/include/consts.sh"
  local functions="${STAGE}/initrd/opt/arc/arc-functions.sh"

  rm -f "${STAGE}"/p3/modules/*-4.4.180.tgz "${STAGE}"/p3/modules/*-4.4.302.tgz
  rm -f "${STAGE}"/p3/lkms/*-4.4.180-*.tgz "${STAGE}"/p3/lkms/*-4.4.302-*.tgz

  grep -q 'Arc ' "${consts}" &&
    grep -q 'platforms\.yml' "${consts}" &&
    grep -q 'https://api.github.com/repos/AuxXxilium/arc/releases' "${consts}" &&
    grep -q 'https://github.com/AuxXxilium/arc/releases/download' "${consts}" &&
    grep -qF '2 "Beta ${BETATAG}" \' "${functions}" &&
    grep -qF '3 "Update Dependencies \Z1(maybe not stable)\Zn" \' "${functions}" ||
    die "consts.sh or arc-functions.sh no longer has a line the Essential edits change. Update make_essential and build.yml together."

  sed -i 's|Arc |Arc Essential |' "${consts}"
  sed -i 's|platforms.yml|platforms-essential.yml|g' "${consts}"
  sed -i 's|https://api.github.com/repos/AuxXxilium/arc/releases|https://api.github.com/repos/AuxXxilium/arc-essential/releases|g' "${consts}"
  sed -i 's|https://github.com/AuxXxilium/arc/releases/download|https://github.com/AuxXxilium/arc-essential/releases/download|g' "${consts}"
  sed -i '/2 "Beta ${BETATAG}" \\$/d' "${functions}"
  sed -i '/3 "Update Dependencies \\Z1(maybe not stable)\\Zn" \\$/d' "${functions}"
}

stage_pack() {
  stage "pack (${variant})"

  [ -f br/bzImage-apex ] && [ -f br/initrd-apex ] ||
    die "no buildroot in br/. Run the buildroot stage first."
  [ -n "$(find files/p3/modules -name '*.tgz' -print -quit 2>/dev/null)" ] ||
    die "no modules in files/p3. Run the deps stage first."

  build_grub
  make_grub_disk

  rm -f arc.img arc*.vmdk arc.vhd arc.vhdx arc.vmc arc.ova arc-*.zip update-*.zip update-*.hash
  info "version           ${VERSION} (${BUILD})"

  info "staging"
  rm -rf "${STAGE}"
  mkdir -p "${STAGE}"
  cp -a files/p1 files/p3 files/initrd "${STAGE}/"
  # Left by builds before the staging.
  rm -rf "${STAGE}/p1/ARC-VERSION" "${STAGE}/p1/ARC-BUILD" "${STAGE}/p3/grub-update" \
    "${STAGE}"/p3/bzImage-* "${STAGE}"/p3/initrd-*
  echo "${VERSION}" >"${STAGE}/p1/ARC-VERSION"
  echo "${BUILD}" >"${STAGE}/p1/ARC-BUILD"
  # Clone Loader writes it to another disk.
  cp -f "${GRUB_DISK}" "${STAGE}/initrd/opt/arc/grub.img.gz"
  if [ "${variant}" = "essential" ]; then
    info "essential"
    make_essential
  fi

  info "repacking initrd"
  cp -f "br/bzImage-apex" "${STAGE}/p3/bzImage-apex"
  repackInitrd "br/initrd-apex" "${STAGE}/initrd" "${STAGE}/p3/initrd-apex"

  info "writing ${IMAGE_FILE}"
  gzip -dc "${GRUB_DISK}" >"${IMAGE_FILE}"
  attach_image "${IMAGE_FILE}"
  mkdir -p "${MNT}/p1" "${MNT}/p3"
  sudo mount "${LOOPX}p1" "${MNT}/p1"
  sudo mount "${LOOPX}p3" "${MNT}/p3"

  # Checked before the copy: cp fills a partition and fails partway,
  # leaving an image that looks built and lacks whatever came last.
  local p need avail
  for p in p1 p3; do
    need="$(du -sm "${STAGE}/${p}" | cut -f1)"
    avail="$(df -m --output=avail "${MNT}/${p}" | tail -1 | tr -d ' ')"
    [ "${need}" -lt "${avail}" ] || die "${p} has ${avail} MB free and needs ${need} MB."
    info "writing ${p}          ${need} MB into ${avail} MB"
    sudo cp -rf "${STAGE}/${p}/"* "${MNT}/${p}"
  done
  sudo sync

  # Every staged file is on the image, and what the loader cannot boot
  # without is among them.
  local f missing=""
  for p in p1 p3; do
    while IFS= read -r -d '' f; do
      [ -f "${MNT}/${p}/${f#./}" ] || missing="${missing} ${p}/${f#./}"
    done < <(cd "${STAGE}/${p}" && find . -type f -print0)
  done
  for f in p1/boot/grub/grub.cfg p1/ARC-VERSION p3/bzImage-apex p3/initrd-apex; do
    [ -f "${MNT}/${f}" ] || missing="${missing} ${f}"
  done
  for f in addons configs custom lkms modules patches; do
    [ -n "$(ls -A "${MNT}/p3/${f}" 2>/dev/null)" ] || missing="${missing} p3/${f}/"
  done
  [ -z "${missing}" ] || die "the image is missing:${missing}"

  # GRUB for the Update Loader, as build.yml stages it: the image up to p1
  # (MBR boot code and core.img), the EFI loaders and the modules. In the
  # update zip only, never in the image.
  local grub_update="${STAGE}/p3/grub-update" t p1start
  mkdir -p "${grub_update}/boot/grub" "${grub_update}/EFI/BOOT"
  for t in ${GRUB_TARGETS}; do
    [ -d "${MNT}/p1/boot/grub/${t}" ] && cp -r "${MNT}/p1/boot/grub/${t}" "${grub_update}/boot/grub/"
  done
  find "${MNT}/p1/EFI/BOOT" -maxdepth 1 -iname 'boot*.efi' -exec cp {} "${grub_update}/EFI/BOOT/" \;
  p1start="$(od -An -tu4 -j454 -N4 "${IMAGE_FILE}" | tr -d ' \n')"
  dd if="${IMAGE_FILE}" of="${grub_update}/bootcode.img" bs=512 count="${p1start}" status=none
  [ -f "${grub_update}/boot/grub/i386-pc/normal.mod" ] && ls "${grub_update}/EFI/BOOT/"* >/dev/null ||
    die "could not stage GRUB for the update."

  unmount_image

  info "writing arc.vmdk"
  qemu-img convert -p -f raw -o subformat=monolithicFlat -O vmdk "${IMAGE_FILE}" arc.vmdk

  if [ "${do_release}" -eq 1 ]; then
    pack_release
  fi
  info "${IMAGE_FILE}           $(du -h "${IMAGE_FILE}" | cut -f1)"
}

# The release files, as build.yml's Build Image and Pack Image steps write
# them.
pack_release() {
  local v="${VERSION}" f

  info "release files"
  qemu-img convert -p -f raw -O vmdk "${IMAGE_FILE}" arc-dyn.vmdk
  createvmc "arc.vhd" "arc.vmc"
  qemu-img convert -p -f raw -O vpc "${IMAGE_FILE}" arc.vhd
  qemu-img convert -p -f raw -O vhdx "${IMAGE_FILE}" arc.vhdx
  convertova "${IMAGE_FILE}" "arc.ova"

  zip -q9 "arc-${v}.img.zip" "arc.img"
  zip -q9 "arc-${v}.vmdk-dyn.zip" "arc-dyn.vmdk"
  zip -q9 "arc-${v}.vmdk-flat.zip" "arc.vmdk" "arc-flat.vmdk"
  zip -q9 "arc-${v}.vhd.zip" "arc.vhd" "arc.vmc"
  zip -q9 "arc-${v}.vhdx.zip" "arc.vhdx"
  zip -q9 "arc-${v}.ova.zip" "arc.ova"
  (cd "${STAGE}" && zip -qr "${HERE}/update-${v}.zip" ./p1 ./p3)
  sha256sum "update-${v}.zip" >"update-${v}.hash"

  for f in arc-"${v}".*.zip "update-${v}.zip" "update-${v}.hash"; do
    info "  ${f}  ($(du -h "${f}" | cut -f1))"
  done
}

# ======================================================== publishing ===
#
# The release goes up as a draft and is published once every file is on
# it: the loader's updater reads the releases, and one still missing its
# update zip is a release every loader would find and fail on.

RELEASE_REPO=""
RELEASE_ID=""
RELEASE_URL=""
replacing=0

# The token goes to curl on stdin, not as an argument.
github_auth() {
  printf 'header = "Authorization: Bearer %s"\n' "${AUX_TOKEN}"
}

github_curl() {
  github_auth | curl -fsSL --retry 3 -K - "$@"
}

# The release a tag names, as "<id> <draft>"; empty when there is none.
# The list rather than releases/tags/<tag>, which does not see drafts.
release_for() {
  github_curl "https://api.github.com/repos/${RELEASE_REPO}/releases?per_page=100" |
    jq -r --arg t "${1}" 'map(select(.tag_name == $t))[0] // empty | "\(.id) \(.draft)"'
}

# build.yml's release bodies.
release_body() {
  local information
  if [ "${publish_to}" = "beta" ]; then
    information="  - Beta Release may not be stable. Use with caution as it is intended for testing purposes only. Check Discord for more information."
  else
    information="  - [Release Notes](https://xpenology.tech/release/view.php?f=${VERSION}.txt)"
  fi
  cat <<EOF
### Information:
${information}

### Dependencies:
  - Addons: ${ADDONTAG:-unknown}
  - Modules: ${MODULETAG:-unknown}
  - Configs: ${CONFIGTAG:-unknown}
  - Patches: ${PATCHTAG:-unknown}
  - Custom: ${CUSTOMTAG:-unknown}
  - LKMs: ${LKMTAG:-unknown}
  - Apex: ${APEX:-unknown}
  - Build: ${BUILD_TIME}
EOF
}

# Before the build: a missing token is said now, not after the hour a
# buildroot rebuild takes to reach the question.
publish_preflight() {
  [ -z "${AUX_TOKEN}" ] || return 0
  case "${publish_to}" in
  "") warn "AUX_TOKEN is not set: this build can be packed, not published." ;;
  no) ;;
  *) die "AUX_TOKEN is not set; this build cannot be published to $(release_repo "${publish_to}")." ;;
  esac
}

release_repo() {
  case "${1}" in
  beta) echo "${BETA_REPO}" ;;
  essential) echo "${ESSENTIAL_REPO}" ;;
  *) echo "${STABLE_REPO}" ;;
  esac
}

# Whether the files just written go up, and where: the flags or the menu
# say, else a terminal is asked -- stable or beta for the full loader,
# arc-essential for Essential. Never for DEV_VERSION.
#
# Sets publish_to and RELEASE_REPO.
want_publish() {
  local answer

  [ "${VERSION}" != "${DEV_VERSION}" ] || return 1
  [ "${publish_to}" != "no" ] || return 1
  if [ -z "${publish_to}" ]; then
    if [ ! -t 0 ]; then
      info "not published (no terminal to ask; --stable, --beta or --essential --publish publish without asking)"
      return 1
    fi
    if [ "${variant}" = "essential" ]; then
      printf '\n    publish %s as an Essential release (%s)? [y/N] ' "${VERSION}" "${ESSENTIAL_REPO}"
      read -r answer || answer=""
      case "${answer}" in
      y | Y | yes) publish_to="essential" ;;
      *) return 1 ;;
      esac
    else
      printf '\n    publish %s as a [s]table release (%s), a [b]eta release (%s), or [n]ot? [s/b/N] ' \
        "${VERSION}" "${STABLE_REPO}" "${BETA_REPO}"
      read -r answer || answer=""
      case "${answer}" in
      s | S | stable) publish_to="stable" ;;
      b | B | beta) publish_to="beta" ;;
      *) return 1 ;;
      esac
    fi
  fi
  RELEASE_REPO="$(release_repo "${publish_to}")"
}

# The draft for VERSION: the one an interrupted upload left, or a new one.
# A release already published only with --replace, or a yes.
#
# Sets RELEASE_ID.
release_draft() {
  local rel answer

  [ -n "${AUX_TOKEN}" ] || die "publishing needs AUX_TOKEN."
  rel="$(release_for "${VERSION}")" ||
    die "could not list ${RELEASE_REPO}'s releases with AUX_TOKEN."
  case "${rel}" in
  "")
    jq -n --arg t "${VERSION}" '{tag_name: $t, name: $t, draft: true}' >"${WORK}/release.json"
    RELEASE_ID="$(github_curl -X POST -H "Content-Type: application/json" -d @"${WORK}/release.json" \
      "https://api.github.com/repos/${RELEASE_REPO}/releases" | jq -r '.id')" ||
      die "could not make a draft release on ${RELEASE_REPO}; AUX_TOKEN needs contents: write there."
    ;;
  *" true")
    RELEASE_ID="${rel% *}"
    info "taking over the draft ${VERSION} an earlier upload left"
    ;;
  *)
    if [ "${do_replace}" -eq 0 ]; then
      [ -t 0 ] || die "${VERSION} is already released on ${RELEASE_REPO}; --replace replaces its files."
      printf '    %s is already released on %s. replace its files? [y/N] ' "${VERSION}" "${RELEASE_REPO}"
      read -r answer || answer=""
      case "${answer}" in
      y | Y | yes) ;;
      *) die "not published: ${VERSION} is already released on ${RELEASE_REPO}." ;;
      esac
    fi
    RELEASE_ID="${rel% *}"
    replacing=1
    ;;
  esac
}

# upload_asset <file>
#
# A failed upload can leave a half-made asset, and GitHub refuses a second
# one of the same name: each attempt deletes what is there first.
upload_asset() {
  local f="${1}" name old try
  local api="https://api.github.com/repos/${RELEASE_REPO}/releases"
  name="$(basename "${f}")"

  info "  ${name}  ($(du -h "${f}" | cut -f1))"
  for try in 1 2 3; do
    old="$(github_curl "${api}/${RELEASE_ID}/assets?per_page=100" |
      jq -r --arg n "${name}" '.[] | select(.name == $n) | .id')" || old=""
    if [ -n "${old}" ]; then
      github_curl -X DELETE "${api}/assets/${old}" || true
    fi
    # -T streams the file rather than reading it into memory.
    if github_auth | curl -fSL -# -K - -X POST -T "${f}" \
      -H "Content-Type: application/octet-stream" -o /dev/null \
      "https://uploads.github.com/repos/${RELEASE_REPO}/releases/${RELEASE_ID}/assets?name=${name}"; then
      return 0
    fi
    warn "uploading ${name} failed (attempt ${try} of 3)"
  done
  local again="--${publish_to}"
  [ "${publish_to}" != "essential" ] || again="--essential --publish"
  die "could not upload ${name}. The draft ${VERSION} stays on ${RELEASE_REPO};
    VERSION=${VERSION} ./build.sh pack ${again} tries again."
}

publish_release() {
  local f

  [ -f "${STATE}" ] && . "${STATE}"
  log "publishing ${VERSION} on ${RELEASE_REPO}"
  release_draft
  for f in arc-"${VERSION}".*.zip "update-${VERSION}.zip" "update-${VERSION}.hash"; do
    upload_asset "${f}"
  done

  # An already published release keeps whether it is the latest.
  if [ "${replacing}" -eq 1 ]; then
    jq -n --arg b "$(release_body)" '{body: $b}' >"${WORK}/release.json"
  else
    jq -n --arg b "$(release_body)" '{body: $b, draft: false, make_latest: "true"}' >"${WORK}/release.json"
  fi
  RELEASE_URL="$(github_curl -X PATCH -H "Content-Type: application/json" -d @"${WORK}/release.json" \
    "https://api.github.com/repos/${RELEASE_REPO}/releases/${RELEASE_ID}" | jq -r '.html_url')" ||
    die "the files are up, but the draft ${VERSION} on ${RELEASE_REPO} could not be published."
  rm -f "${WORK}/release.json"
  info "${RELEASE_URL}"
}

# ============================================================== menu ===
#
# A numbered menu, as arx's build.sh has. The variant and a clean buildroot
# are switched in place; every other choice starts the build.

# What is already built, so the menu can say so.
state_of() {
  case "${1}" in
  pull)
    git rev-parse --short HEAD 2>/dev/null || echo "not a checkout"
    ;;
  deps)
    if [ -f "${DEPS_DONE}" ] && [ -f "${STATE}" ]; then
      (. "${STATE}" && echo "addons ${ADDONTAG}, modules ${MODULETAG}")
    else
      echo "not fetched"
    fi
    ;;
  buildroot)
    if [ -f "${BR_OUT}/images/rootfs.cpio.zst" ]; then
      echo "built $(date -r "${BR_OUT}/images/rootfs.cpio.zst" +'%d %b %H:%M'), $(buildroot_ref)"
    elif [ -d "${BR_SRC}" ]; then
      echo "cloned, not built"
    else
      echo "not cloned"
    fi
    ;;
  pack)
    if [ -f "${IMAGE_FILE}" ]; then
      echo "$(du -h "${IMAGE_FILE}" | cut -f1), $(date -r "${IMAGE_FILE}" +'%d %b %H:%M')"
    else
      echo "no image"
    fi
    ;;
  esac
}

# The repository this build would be published to, for the version hint.
target_repo() {
  if [ -n "${publish_to}" ] && [ "${publish_to}" != "no" ]; then
    release_repo "${publish_to}"
  elif [ "${variant}" = "essential" ]; then
    release_repo essential
  else
    release_repo stable
  fi
}

latest_tag() {
  local repo
  repo="$(target_repo)"
  githubLatestReleaseTag "${repo#*/}" 2>/dev/null || true
}

menu() {
  local choice
  while true; do
    printf '\n'
    printf '    \033[1marc build\033[0m  %s@%s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" "$(state_of pull)"
    printf '    \033[2m%s\033[0m\n\n' "$(printf '%.0s-' $(seq 1 46))"
    printf '      \033[1m1\033[0m  everything          \033[2mall four stages\033[0m\n'
    printf '\n'
    printf '      \033[1m2\033[0m  pull                \033[2m%s\033[0m\n' "$(state_of pull)"
    printf '      \033[1m3\033[0m  deps                \033[2m%s\033[0m\n' "$(state_of deps)"
    printf '      \033[1m4\033[0m  buildroot           \033[2m%s\033[0m\n' "$(state_of buildroot)"
    printf '      \033[1m5\033[0m  pack                \033[2m%s\033[0m\n' "$(state_of pack)"
    printf '\n'
    printf '      \033[1m6\033[0m  deps + buildroot + pack  \033[2mall but the pull\033[0m\n'
    printf '      \033[1m7\033[0m  everything, updated \033[2mas 1, fetching addons, modules, configs,\033[0m\n'
    printf '                          \033[2mpatches, custom, LKMs and theme again\033[0m\n'
    printf '\n'
    printf '      \033[1mv\033[0m  variant             \033[2m%s\033[0m\n' "${variant}"
    printf '      \033[1mr\033[0m  clean buildroot     \033[2m%s\033[0m\n' \
      "$([ "${do_brclean}" -eq 1 ] && echo "yes, from an empty output tree" || echo "no, only what changed")"
    printf '      \033[1mc\033[0m  clean               \033[2mdrop build output\033[0m\n'
    printf '\n'
    printf '      \033[1mq\033[0m  quit\n'
    printf '\n'
    printf '    choice: '

    read -r choice || {
      echo
      exit 0
    }

    # The stages return, so a stage's output is not buried under a
    # redrawn menu. v and r go round again to show what they switched.
    case "${choice}" in
    1) do_pull=1 do_deps=1 do_buildroot=1 do_pack=1; return 0 ;;
    2) do_pull=1 do_deps=0 do_buildroot=0 do_pack=0; return 0 ;;
    3) do_pull=0 do_deps=1 do_buildroot=0 do_pack=0; return 0 ;;
    4) do_pull=0 do_deps=0 do_buildroot=1 do_pack=0; return 0 ;;
    5) do_pull=0 do_deps=0 do_buildroot=0 do_pack=1; return 0 ;;
    6) do_pull=0 do_deps=1 do_buildroot=1 do_pack=1; return 0 ;;
    7) do_pull=1 do_deps=1 do_buildroot=1 do_pack=1 do_refresh=1; return 0 ;;
    v | V)
      if [ "${variant}" = "full" ]; then variant="essential"; else variant="full"; fi
      ;;
    r | R) do_brclean=$((1 - do_brclean)) ;;
    c | C) menu_clean ;;
    q | Q) exit 0 ;;
    *) warn "not a choice: ${choice}" ;;
    esac
  done
}

# work/buildroot is an hour of building: it goes only when asked for by name.
menu_clean() {
  local what confirm
  printf '\n'
  printf '      \033[1ma\033[0m  images and zips     \033[2marc.img, vmdk, vhd(x), ova, release zips\033[0m\n'
  printf '      \033[1mb\033[0m  deps and buildroot  \033[2mfiles/p1, files/p3 output, br/, work/stage\033[0m\n'
  printf '      \033[1mc\033[0m  buildroot output    \033[2mwork/buildroot/output, keeps the clone\033[0m\n'
  printf '      \033[1me\033[0m  grub                \033[2mthe grub build and the grub disk in work/\033[0m\n'
  printf '      \033[1md\033[0m  everything          \033[2mall of the above and work/\033[0m\n'
  printf '\n'
  printf '    clean what (enter to cancel): '
  read -r what || return 0

  case "${what}" in
  a)
    rm -f arc.img arc*.vmdk arc.vhd arc.vhdx arc.vmc arc.ova arc-*.zip update-*.zip update-*.hash
    info "removed the images and zips"
    ;;
  b)
    git clean -fdxq -- files/p1 files/p3
    rm -rf br "${STAGE}" "${STATE}" "${DEPS_DONE}"
    info "removed the dependencies, br/ and work/stage"
    ;;
  c)
    rm -rf "${BR_OUT}" "${WORK}/br.fingerprint"
    info "removed work/buildroot/output"
    ;;
  e)
    rm -rf "${GRUB_SRC}" "${GRUB_DISK}" "${WORK}/grub.img" "${WORK}/grub.fingerprint"
    info "removed the grub build and the grub disk"
    ;;
  d)
    printf '    this drops the buildroot clone and its downloads too. type yes: '
    read -r confirm || return 0
    if [ "${confirm}" = "yes" ]; then
      rm -f arc.img arc*.vmdk arc.vhd arc.vhdx arc.vmc arc.ova arc-*.zip update-*.zip update-*.hash
      git clean -fdxq -- files/p1 files/p3
      rm -rf br "${WORK}"
      info "removed everything"
    else
      info "cancelled"
    fi
    ;;
  "") info "cancelled" ;;
  *) warn "not a choice: ${what}" ;;
  esac
}

# ============================================================== driver ===

# No arguments and a terminal to ask on: the menu. Otherwise straight
# through, so a job with no one to answer does not block.
if [ "$#" -eq 0 ] && [ -t 0 ]; then
  menu

  # Asked now, not after the pack: the build before it can take an hour.
  if [ "${do_pack}" -eq 1 ] && [ "${do_release}" -eq 0 ]; then
    printf '    pack release files (img, vmdk, vhd, vhdx, ova zips, update zip)? [y/N] '
    read -r answer || answer=""
    case "${answer}" in
    y | Y | yes) do_release=1 ;;
    esac
  fi
fi

# A pack without the buildroot stage packs the br/ an earlier build made
# here, never the arc-buildroot-essential release an older one downloaded.
if [ "${do_pack}" -eq 1 ] && [ "${do_buildroot}" -eq 0 ] && [ -f br/initrd-apex ] &&
  ! (. "${STATE}" 2>/dev/null && [ "${APEX#local:}" != "${APEX}" ]); then
  die "the buildroot in br/ was not built here. Build it too:

        ./build.sh buildroot pack"
fi

# A release ships the dependencies as they are now, as it does buildroot.
if [ "${do_release}" -eq 1 ] && [ "${do_deps}" -eq 1 ]; then
  do_refresh=1
fi

if [ -z "${VERSION}" ]; then
  if [ "${do_release}" -eq 0 ] || [ "${do_pack}" -eq 0 ]; then
    VERSION="${DEV_VERSION}"
  else
    [ -t 0 ] || die "a release build needs VERSION (major.minor.patch) when there is no terminal to ask."
    latest="$(latest_tag)"
    printf '    release version%s: ' "${latest:+ (newest on $(target_repo): ${latest})}"
    read -r VERSION || VERSION=""
  fi
fi
# The release tag and the update zip's name: a typo here is a release the
# updater cannot rank.
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "not a version: '${VERSION}' (major.minor.patch)"
# Kept across the re-exec in stage_pull, which would otherwise ask again.
export VERSION

check_tools

if [ "${do_release}" -eq 1 ] && [ "${do_pack}" -eq 1 ] && [ "${VERSION}" != "${DEV_VERSION}" ]; then
  publish_preflight
fi

started="${ARC_STARTED:-$(date +%s)}"
export ARC_STARTED="${started}"

steps_total=$((do_pull + do_deps + do_buildroot + do_pack))

if [ "${do_pull}" -eq 1 ]; then stage_pull; fi
if [ "${do_deps}" -eq 1 ]; then stage_deps; fi
if [ "${do_buildroot}" -eq 1 ]; then stage_buildroot; fi
if [ "${do_pack}" -eq 1 ]; then stage_pack; fi

if [ "${do_pack}" -eq 1 ] && [ "${do_release}" -eq 1 ] && want_publish; then
  publish_release
fi

elapsed=$(($(date +%s) - started))
printf '\n    build done at %s, %dm %ds\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$((elapsed / 60))" "$((elapsed % 60))"
