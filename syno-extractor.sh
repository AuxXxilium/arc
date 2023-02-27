#!/usr/bin/env bash

ROOT_PATH=$PWD
TOOL_PATH="$(dirname $(readlink -f "$0"))/syno-extractor"

GITHUB_URL="https://raw.githubusercontent.com/AuxXxilium/arc/main/syno-extractor"

[ ! -d "${TOOL_PATH}" ] && mkdir -p "${TOOL_PATH}"
for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7 syno_extract_system_patch; do
  [ ! -e "${TOOL_PATH}/${f}" ] && curl -skL "${GITHUB_URL}/${f}" -o "${TOOL_PATH}/${f}"
done
sudo chmod -R +x "${TOOL_PATH}"
sudo LD_LIBRARY_PATH="${TOOL_PATH}" "${TOOL_PATH}/syno_extract_system_patch" $@