#!/usr/bin/env bash

# Shared CI helpers for release metadata and archive downloads.

github_api_json_retry() {
  local url="${1}"
  local tries="${2:-6}"
  local sleep_s="${3:-2}"
  local i=0
  local resp=""

  while [ "${i}" -lt "${tries}" ]; do
    resp="$(curl -fsSL --connect-timeout 10 --retry 3 --retry-delay 1 --retry-all-errors "${url}" 2>/dev/null || true)"
    if [ -n "${resp}" ] && echo "${resp}" | jq -e . >/dev/null 2>&1; then
      printf '%s\n' "${resp}"
      return 0
    fi
    i=$((i + 1))
    sleep "${sleep_s}"
  done

  return 1
}

github_latest_tag() {
  local api_url="${1}"
  local exclude_dev="${2:-false}"
  local tag=""

  if [ "${exclude_dev}" = "true" ]; then
    tag="$(github_api_json_retry "${api_url}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' | grep -v "dev" | sort -rV | head -1)"
  else
    tag="$(github_api_json_retry "${api_url}" | jq -r 'if type=="array" then .[].tag_name // empty else empty end' | sort -rV | head -1)"
  fi

  tag="${tag#v}"
  [ -n "${tag}" ] || return 1
  printf '%s\n' "${tag}"
}

download_validated_zip() {
  local url="${1}"
  local out="${2}"
  local min_size="${3:-1024}"
  local tmp="${out}.part"

  rm -f "${out}" "${tmp}"
  curl -fL --connect-timeout 10 --retry 5 --retry-delay 2 --retry-all-errors "${url}" -o "${tmp}"
  [ -s "${tmp}" ] || return 1
  [ "$(stat -c%s "${tmp}")" -ge "${min_size}" ] || return 1
  unzip -tqq "${tmp}" >/dev/null 2>&1 || return 1
  mv -f "${tmp}" "${out}"
}
