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
#   2. deps       addons, modules, configs, patches, custom, LKMs, theme
#   3. buildroot  loader kernel + initramfs: the latest arc-buildroot-essential
#                 release, or built here from source (--rebuild-buildroot)
#   4. pack       arc.img and arc.vmdk
#
#   ./img-gen.sh                      the build menu on a terminal (dialog),
#                                     else all four
#   ./img-gen.sh deps pack            only the stages named
#   ./img-gen.sh --no-pull            all but the pull (also --no-deps,
#                                     --no-buildroot, --no-pack)
#   ./img-gen.sh --rebuild-buildroot  build buildroot instead of downloading
#                                     it, from the build's own clone of
#                                     arc-buildroot-essential's main and of
#                                     Buildroot, both in work/ (AUX_TOKEN)
#   ./img-gen.sh --clean-buildroot    the same, from an empty output tree
#   ./img-gen.sh --essential          the Essential variant, as build.yml makes
#                                     it: no 4.4 kernel modules or LKMs, the
#                                     Essential platforms, and arc-essential as
#                                     the loader's update source
#   ./img-gen.sh --release            then the release files as build.yml packs
#                                     them: img, vmdk (flat and dynamic), vhd,
#                                     vhdx and ova zips, the update zip and its
#                                     hash. Asks for the version, and once the
#                                     files are written whether to publish them:
#                                     as a stable (arc) or beta (arc-beta)
#                                     release, or for --essential to
#                                     arc-essential (AUX_TOKEN)
#   ./img-gen.sh --stable             --release, published to arc without asking
#   ./img-gen.sh --beta               --release, published to arc-beta without
#                                     asking
#   ./img-gen.sh --essential --publish
#                                     --release, published to arc-essential
#                                     without asking (--publish alone: arc)
#   --no-publish                      --release, and do not ask
#   --replace                         a release already published may have its
#                                     files replaced (build.yml's allowUpdates)
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
do_rebuild=0 do_brclean=0 do_release=0 do_replace=0
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
  --rebuild-buildroot) do_rebuild=1 ;;
  --clean-buildroot) do_rebuild=1 do_brclean=1 ;;
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

check_tools() {
  need git
  need curl
  need jq
  if [ "${do_deps}" -eq 1 ] || [ "${do_buildroot}" -eq 1 ]; then
    need unzip
    need tar
  fi
  if [ "${do_buildroot}" -eq 1 ] && [ "${do_rebuild}" -eq 1 ]; then
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
    if [ "${do_release}" -eq 1 ]; then
      need zip
      need unzip
      need sha256sum "coreutils"
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
  [ "${do_rebuild}" -eq 1 ] && rest="${rest} --rebuild-buildroot"
  [ "${do_release}" -eq 1 ] && rest="${rest} --release"
  [ "${do_replace}" -eq 1 ] && rest="${rest} --replace"
  [ "${variant}" = "essential" ] && rest="${rest} --essential"
  case "${publish_to}" in
  stable | beta) rest="${rest} --${publish_to}" ;;
  essential) rest="${rest} --publish" ;;
  no) rest="${rest} --no-publish" ;;
  esac

  chmod 0755 "${HERE}/img-gen.sh" 2>/dev/null || true
  info "restarting with the new img-gen.sh"
  # shellcheck disable=SC2086
  ARC_PULLED=1 exec "${HERE}/img-gen.sh" --no-pull ${rest}
}

# ============================================================= 2. deps ===

stage_deps() {
  stage "deps"

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

  pkgs="$(make -s -C "${BR_SRC}" show-targets)"
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
    make -s -C "${BR_SRC}" "${pkg}-dirclean"
  done
  if [ -n "${orphans}" ]; then
    warn "changed options of packages no longer built:${orphans}
    Their files stay in the loader until --clean-buildroot."
  fi
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
    git clone -q --depth 1 --branch "${BUILDROOT_REF}" "${BUILDROOT_URL}" "${BR_SRC}"
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
      make -s -C "${BR_SRC}" BR2_EXTERNAL="${BR_SRC}/external" arc_defconfig
      if [ -f "${prev}" ]; then
        if [ "$(arch_options "${prev}")" != "$(arch_options "${BR_OUT}/.config")" ]; then
          info "target architecture changed, building everything again"
          rm -rf "${BR_OUT}"
          make -s -C "${BR_SRC}" BR2_EXTERNAL="${BR_SRC}/external" arc_defconfig
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
    FORCE_UNSAFE_CONFIGURE=1 make -C "${BR_SRC}" BR2_JLEVEL="${JOBS}"

    [ -f "${BR_OUT}/images/bzImage" ] || die "buildroot produced no bzImage."
    [ -f "${BR_OUT}/images/rootfs.cpio.zst" ] || die "buildroot produced no rootfs.cpio.zst."
    echo "${fp}" >"${fpfile}"
  fi

  rm -rf br
  mkdir -p br
  cp -f "${BR_OUT}/images/bzImage" "br/bzImage-apex"
  cp -f "${BR_OUT}/images/rootfs.cpio.zst" "br/initrd-apex"
  remember APEX "local: buildroot ${BUILDROOT_REF}, kernel ${KERNEL_VERSION}, arc-buildroot-essential@${BR_CONFIG_REV}"
}

stage_buildroot() {
  if [ "${do_rebuild}" -eq 1 ]; then
    stage "buildroot (rebuild)"
    build_buildroot
  else
    stage "buildroot (download)"
    rm -rf br
    getBuildroot "apex" || die "could not get the buildroot release."
    remember APEX "${apex}"
  fi
  info "bzImage-apex      $(du -h br/bzImage-apex | cut -f1)"
  info "initrd-apex       $(du -h br/initrd-apex | cut -f1)"
}

# ============================================================= 4. pack ===

LOOPX=""

unmount_image() {
  sudo umount "/tmp/p1" 2>/dev/null || true
  sudo umount "/tmp/p3" 2>/dev/null || true
  if [ -n "${LOOPX}" ]; then
    sudo losetup --detach "${LOOPX}" 2>/dev/null || true
    LOOPX=""
  fi
}

# A failed pack does not leave the image mounted.
trap '[ -z "${LOOPX}" ] || unmount_image' EXIT

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
  if [ "${variant}" = "essential" ]; then
    info "essential"
    make_essential
  fi

  info "repacking initrd"
  cp -f "br/bzImage-apex" "${STAGE}/p3/bzImage-apex"
  repackInitrd "br/initrd-apex" "${STAGE}/initrd" "${STAGE}/p3/initrd-apex"

  info "writing ${IMAGE_FILE}"
  gzip -dc "files/initrd/opt/arc/grub.img.gz" >"${IMAGE_FILE}"
  unmount_image
  LOOPX="$(sudo losetup -P -f --show "${IMAGE_FILE}")"
  sudo rm -rf "/tmp/p1" "/tmp/p3"
  mkdir -p "/tmp/p1" "/tmp/p3"
  sudo mount "${LOOPX}p1" "/tmp/p1"
  sudo mount "${LOOPX}p3" "/tmp/p3"
  sudo cp -rf "${STAGE}/p1/"* "/tmp/p1"
  sudo cp -rf "${STAGE}/p3/"* "/tmp/p3"
  sudo sync

  # GRUB for the Update Loader, as build.yml stages it: the image up to p1
  # (MBR boot code and core.img), the EFI loaders and the modules. In the
  # update zip only, never in the image.
  local grub_update="${STAGE}/p3/grub-update" t p1start
  mkdir -p "${grub_update}/boot/grub" "${grub_update}/EFI/BOOT"
  for t in i386-pc i386-efi x86_64-efi; do
    [ -d "/tmp/p1/boot/grub/${t}" ] && cp -r "/tmp/p1/boot/grub/${t}" "${grub_update}/boot/grub/"
  done
  find "/tmp/p1/EFI/BOOT" -maxdepth 1 -iname 'boot*.efi' -exec cp {} "${grub_update}/EFI/BOOT/" \;
  p1start="$(od -An -tu4 -j454 -N4 "${IMAGE_FILE}" | tr -d ' \n')"
  dd if="${IMAGE_FILE}" of="${grub_update}/bootcode.img" bs=512 count="${p1start}" status=none
  [ -f "${grub_update}/boot/grub/i386-pc/normal.mod" ] && ls "${grub_update}/EFI/BOOT/"* >/dev/null ||
    die "could not stage GRUB for the update."

  unmount_image
  rmdir "/tmp/p1" "/tmp/p3"

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
    VERSION=${VERSION} ./img-gen.sh pack ${again} tries again."
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
# The build set up in dialog -- stages, variant, buildroot, release,
# publishing, version -- and then run, with nothing more to answer.

state_of() {
  case "${1}" in
  pull)
    git rev-parse --short HEAD 2>/dev/null || echo "not a checkout"
    ;;
  deps)
    if [ -f "${STATE}" ] && grep -q '^ADDONTAG=' "${STATE}" && [ -n "$(ls -A files/p3/addons 2>/dev/null | grep -v '^\.gitkeep$')" ]; then
      (. "${STATE}" && echo "addons ${ADDONTAG}, modules ${MODULETAG}")
    else
      echo "not fetched"
    fi
    ;;
  buildroot)
    if [ -f br/initrd-apex ] && [ -f "${STATE}" ]; then
      (. "${STATE}" && echo "${APEX:-unknown}")
    else
      echo "none"
    fi
    ;;
  rebuild)
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

dlg() {
  dialog --backtitle "Arc build  $(git rev-parse --abbrev-ref HEAD 2>/dev/null)@$(state_of pull)" \
    --colors --stdout "$@"
}

msg() {
  dlg --title "${1}" --msgbox "${2}" 0 0 || true
}

# onoff <value> <wanted>: a dialog list's on or off.
onoff() {
  if [ "${1}" = "${2}" ]; then echo "on"; else echo "off"; fi
}

stages_text() {
  local s="" n v
  for n in pull deps buildroot pack; do
    eval "v=\${do_${n}}"
    if [ "${v}" -eq 1 ]; then s="${s:+${s} + }${n}"; fi
  done
  echo "${s:-none}"
}

br_text() {
  if [ "${do_rebuild}" -eq 0 ]; then
    echo "download the latest release"
  elif [ "${do_brclean}" -eq 1 ]; then
    echo "rebuild here, from an empty output tree"
  else
    echo "rebuild here, only what changed"
  fi
}

publish_text() {
  if [ "${do_release}" -eq 0 ]; then
    echo "-"
  elif [ -z "${publish_to}" ]; then
    echo "ask when the files are written"
  elif [ "${publish_to}" = "no" ]; then
    echo "no, keep the files here"
  else
    echo "${publish_to} ($(release_repo "${publish_to}"))"
  fi
}

version_text() {
  if [ "${do_release}" -eq 0 ]; then
    echo "${DEV_VERSION} (dev build)"
  else
    echo "${VERSION:-not set}"
  fi
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
  local choice="b"
  command -v dialog >/dev/null 2>&1 ||
    die "the build menu needs dialog: sudo apt install -y dialog
    Or run without the menu, see ./img-gen.sh --help."

  while true; do
    choice="$(dlg --title "Arc build" --cancel-label "Quit" --default-item "${choice}" \
      --menu "Set the build up, then start it." 0 0 0 \
      b "\Zb\Z4Start the build\Zn" \
      s "Stages         $(stages_text)" \
      v "Variant        ${variant}" \
      r "Buildroot      $(br_text)" \
      f "Release files  $(onoff "${do_release}" 1 | sed 's/on/yes/; s/off/no/')" \
      p "Publish        $(publish_text)" \
      n "Version        $(version_text)" \
      c "Clean          drop build output")" || {
      clear
      exit 0
    }
    case "${choice}" in
    b)
      if menu_start; then
        clear
        return 0
      fi
      ;;
    s) menu_stages ;;
    v) menu_variant ;;
    r) menu_buildroot ;;
    f) menu_release ;;
    p) menu_publish ;;
    n) menu_version || true ;;
    c) menu_clean ;;
    esac
  done
}

menu_stages() {
  local sel s
  sel="$(dlg --title "Stages" --separate-output --checklist "Space selects a stage." 0 0 0 \
    pull "$(state_of pull)" "$(onoff "${do_pull}" 1)" \
    deps "$(state_of deps)" "$(onoff "${do_deps}" 1)" \
    buildroot "$(state_of buildroot)" "$(onoff "${do_buildroot}" 1)" \
    pack "$(state_of pack)" "$(onoff "${do_pack}" 1)")" || return 0
  do_pull=0 do_deps=0 do_buildroot=0 do_pack=0
  for s in ${sel}; do
    eval "do_${s}=1"
  done
}

menu_variant() {
  local sel
  sel="$(dlg --title "Variant" --radiolist "" 0 0 0 \
    full "every platform, released to arc or arc-beta" "$(onoff "${variant}" full)" \
    essential "no 4.4 kernels, released to arc-essential" "$(onoff "${variant}" essential)")" || return 0
  variant="${sel:-${variant}}"
  # Essential has one release repository, the full loader two.
  case "${variant}:${publish_to}" in
  essential:stable | essential:beta | full:essential) publish_to="" ;;
  esac
}

menu_buildroot() {
  local sel mode="download"
  if [ "${do_rebuild}" -eq 1 ]; then mode="rebuild"; fi
  if [ "${do_brclean}" -eq 1 ]; then mode="clean"; fi
  sel="$(dlg --title "Buildroot" --radiolist "Local tree: $(state_of rebuild)" 0 0 0 \
    download "the latest arc-buildroot-essential release" "$(onoff "${mode}" download)" \
    rebuild "build here, only what changed" "$(onoff "${mode}" rebuild)" \
    clean "build here, from an empty output tree" "$(onoff "${mode}" clean)")" || return 0
  case "${sel}" in
  download) do_rebuild=0 do_brclean=0 ;;
  rebuild) do_rebuild=1 do_brclean=0 ;;
  clean) do_rebuild=1 do_brclean=1 ;;
  *) return 0 ;;
  esac
  do_buildroot=1
}

menu_release() {
  local rc=0
  dlg --title "Release files" --yesno "Pack the release files too?\n\nimg, vmdk (flat and dynamic), vhd, vhdx and ova zips, the update zip and its hash. A release needs a version." 0 0 || rc=$?
  case "${rc}" in
  0)
    do_release=1
    do_pack=1
    ;;
  1) do_release=0 ;;
  esac
}

menu_publish() {
  local sel cur="${publish_to:-ask}"
  if [ "${variant}" = "essential" ]; then
    sel="$(dlg --title "Publish" --radiolist "Where the release files go once they are written." 0 0 0 \
      ask "ask when the files are written" "$(onoff "${cur}" ask)" \
      essential "${ESSENTIAL_REPO}" "$(onoff "${cur}" essential)" \
      no "keep the files here" "$(onoff "${cur}" no)")" || return 0
  else
    sel="$(dlg --title "Publish" --radiolist "Where the release files go once they are written." 0 0 0 \
      ask "ask when the files are written" "$(onoff "${cur}" ask)" \
      stable "${STABLE_REPO}" "$(onoff "${cur}" stable)" \
      beta "${BETA_REPO}" "$(onoff "${cur}" beta)" \
      no "keep the files here" "$(onoff "${cur}" no)")" || return 0
  fi
  case "${sel}" in
  "") return 0 ;;
  ask) publish_to="" ;;
  *) publish_to="${sel}" ;;
  esac
  do_release=1
  do_pack=1
}

menu_version() {
  local v latest hint=""
  latest="$(latest_tag)"
  [ -z "${latest}" ] || hint="\nNewest on $(target_repo): ${latest}"
  v="$(dlg --title "Version" --inputbox "The release version, major.minor.patch.${hint}" 0 0 "${VERSION}")" || return 1
  if [[ ! "${v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    msg "Version" "Not a version: '${v}' (major.minor.patch)."
    return 1
  fi
  VERSION="${v}"
  do_release=1
  do_pack=1
}

# What the build needs, asked for now rather than an hour into it.
menu_start() {
  local publishing=0
  if [ "${do_release}" -eq 1 ] && [ -n "${publish_to}" ] && [ "${publish_to}" != "no" ]; then
    publishing=1
  fi

  if [ $((do_pull + do_deps + do_buildroot + do_pack)) -eq 0 ]; then
    msg "Start" "No stage is selected."
    return 1
  fi
  if [ "${do_release}" -eq 1 ] && [ "${do_pack}" -eq 0 ]; then
    msg "Start" "The release files are written by the pack stage: select it too, or turn the release files off."
    return 1
  fi
  if [ "${do_release}" -eq 1 ] && [ -z "${VERSION}" ]; then
    menu_version || return 1
  fi
  if [ "${publishing}" -eq 1 ] && [ "${VERSION}" = "${DEV_VERSION}" ]; then
    msg "Start" "${DEV_VERSION} is the dev build's version and is never published."
    return 1
  fi
  if [ "${publishing}" -eq 1 ] && [ -z "${AUX_TOKEN}" ]; then
    msg "Start" "AUX_TOKEN is not set: the build cannot be published to $(release_repo "${publish_to}")."
    return 1
  fi
  if [ "${do_buildroot}" -eq 1 ] && [ "${do_rebuild}" -eq 1 ] && [ -z "${AUX_TOKEN}" ] && [ -z "${BR_CONFIG}" ] &&
    [ ! -d "${WORK}/arc-buildroot-essential/.git" ]; then
    dlg --title "Start" --yesno "AUX_TOKEN is not set, and cloning ${BR_CONFIG_REPO} may need it.\n\nStart anyway?" 0 0 || return 1
  fi
  return 0
}

# work/buildroot is an hour of building: it goes only when asked for by name.
menu_clean() {
  local what
  what="$(dlg --title "Clean" --menu "Drop what?" 0 0 0 \
    a "images and zips       arc.img, vmdk, vhd(x), ova, release zips" \
    b "deps and buildroot    files/p1, files/p3 output, br/, work/stage" \
    c "buildroot output      work/buildroot/output, keeps the clone and downloads" \
    d "everything            all of the above and work/")" || return 0

  case "${what}" in
  a)
    rm -f arc.img arc*.vmdk arc.vhd arc.vhdx arc.vmc arc.ova arc-*.zip update-*.zip update-*.hash
    msg "Clean" "Removed the images and zips."
    ;;
  b)
    git clean -fdxq -- files/p1 files/p3
    rm -rf br "${STAGE}" "${STATE}"
    msg "Clean" "Removed the dependencies, br/ and work/stage."
    ;;
  c)
    rm -rf "${BR_OUT}" "${WORK}/br.fingerprint"
    msg "Clean" "Removed work/buildroot/output."
    ;;
  d)
    if dlg --title "Clean" --defaultno --yesno "This drops the buildroot clone and its downloads too: the next rebuild starts from nothing.\n\nRemove everything?" 0 0; then
      rm -f arc.img arc*.vmdk arc.vhd arc.vhdx arc.vmc arc.ova arc-*.zip update-*.zip update-*.hash
      git clean -fdxq -- files/p1 files/p3
      rm -rf br "${WORK}"
      msg "Clean" "Removed everything."
    fi
    ;;
  esac
}

# ============================================================== driver ===

# No arguments and a terminal to ask on: the menu. Otherwise straight
# through, so a job with no one to answer does not block.
if [ "$#" -eq 0 ] && [ -t 0 ]; then
  menu
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
