. /opt/arpl/include/modules.sh

function getModules() {
    unset USERMODULES
    declare -A USERMODULES
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    # Unzip modules for temporary folder
    rm -rf "${TMP_PATH}/modules"
    mkdir -p "${TMP_PATH}/modules"
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
    # Get list of all modules
    rm -f "$MODULE_ALIAS_FILE"
    exportPCIModules >"$MODULE_ALIAS_FILE"
    listPCIModules
    rm -f "$MODULE_ALIAS_FILE"
    exportMISCModules >"$MODULE_ALIAS_FILE"
    listMISCModules
    rm -rf "${TMP_PATH}/modules"
}

function exportPCIModules() {
  echo "{"
  echo "\"modules\" : ["
  for module in $(ls ${TMP_PATH}/modules/*.ko); do
      if [ $(modinfo $module --field alias | wc -l) -ge 1 ]; then
          for alias in $(modinfo $module --field alias | grep -iE 'pci|usb'); do
              module=`basename "${module}" .ko`
              echo "{"
              echo "\"name\" :  \"${module}\"",
              echo "\"alias\" :  \"${alias}\""
              echo "}",
          done
      fi
      #       echo "},"
  done | sed '$ s/,//'
  echo "]"
  echo "}"
}

function exportMISCModules() {
  echo "{"
  echo "\"modules\" : ["
  for module in $(ls ${TMP_PATH}/modules/*.ko); do
      if [ $(modinfo $module --field alias | wc -l) -ge 1 ]; then
          for alias in $(modinfo $module --field alias | grep -ivE 'pci|usb'); do
              module=`basename "${module}" .ko`
              echo "{"
              echo "\"name\" :  \"${module}\"",
              echo "\"alias\" :  \"${alias}\""
              echo "}",
          done
      fi
      #       echo "},"
  done | sed '$ s/,//'
  echo "]"
  echo "}"
}

function listPCIModules() {
  lspci -n | while read line; do
    vendor="$(echo $line | awk '{print substr($3,1,4)}' | tr [:lower:] [:upper:])"
    device="$(echo $line | awk '{print substr($3,6,8)}' | tr [:lower:] [:upper:])"
    pciid="${vendor}d0000${device}"
    ID=$(jq -e -r ".modules[] | select(.alias | contains(\"${pciid}\")?) | .name " "$MODULE_ALIAS_FILE")
    [ -n "${ID}" ] && writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
  done
  lsusb | while read line; do
    vendor="$(echo $line | awk '{print substr($6,1,4)}' | tr [:lower:] [:upper:])"
    device="$(echo $line | awk '{print substr($6,6,8)}' | tr [:lower:] [:upper:])"
    usbid="${vendor}d0000${device}"
    ID=$(jq -e -r ".modules[] | select(.alias | contains(\"${usbid}\")?) | .name " "$MODULE_ALIAS_FILE")
    [ -n "${ID}" ] && writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
  done
}

function listMISCModules() {
  while read line; do
    [ -n "${line}" ] && writeConfigKey "modules.${line}" "" "${USER_CONFIG_FILE}"
  done < <(jq -e -r ".modules[] | select(.alias ?) | .name " "$MODULE_ALIAS_FILE")
}