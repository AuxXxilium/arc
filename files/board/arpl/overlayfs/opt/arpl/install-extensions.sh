#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Detect if has new local plugins to install/reinstall
for F in $(ls ${CACHE_PATH}/*.extension 2>/dev/null); do
  EXTENSION=$(basename "${F}" | sed 's|.extension||')
  rm -rf "${EXTENSIONS_PATH}/${EXTENSION}"
  mkdir -p "${EXTENSIONS_PATH}/${EXTENSION}"
  echo "Installing ${F} to ${EXTENSIONS_PATH}/${EXTENSION}"
  tar -xaf "${F}" -C "${EXTENSIONS_PATH}/${EXTENSION}"
  rm -f "${F}"
done
