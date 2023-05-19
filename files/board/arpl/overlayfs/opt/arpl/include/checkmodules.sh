function getModules() {
    unset USERMODULES
    declare -A USERMODULES
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    getModulesJson
    echo "{"
    echo "\"modules\" : ["
    for module in $(ls ${TMP_PATH}/modules/*.ko); do
        if [ $(modinfo $module --field alias | wc -l) -ge 1 ]; then
            for alias in $(modinfo $module --field alias); do
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
    listModules
}

function getModulesJson() {
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  # Get list of all modules
  rm -f "$MODULE_ALIAS_FILE"
  getModules >"$MODULE_ALIAS_FILE"
  rm -rf "${TMP_PATH}/modules"
}

function listModules() {
    if $(jq '.' $MODULE_ALIAS_FILE >/dev/null); then
        ID=$(listID | sort | uniq)
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
    fi

}

function listID() {
  lspci -n | while read line; do
    vendor="$(echo $line | awk '{print substr($3,1,4)}' | tr [:lower:] [:upper:])"
    device="$(echo $line | awk '{print substr($3,6,8)}' | tr [:lower:] [:upper:])"
    pciid="${vendor}d0000${device}"
    matchedmodule=$(jq -e -r ".modules[] | select(.alias | contains(\"${pciid}\")?) | .name " $MODULE_ALIAS_FILE)
    [ -n "${matchedmodule}" ] && echo "${matchedmodule}"
  done
  lsusb | while read line; do
    vendor="$(echo $line | awk '{print substr($6,1,4)}' | tr [:lower:] [:upper:])"
    device="$(echo $line | awk '{print substr($6,6,8)}' | tr [:lower:] [:upper:])"
    usbid="${vendor}d0000${device}"
    matchedmodule=$(jq -e -r ".modules[] | select(.alias | contains(\"${usbid}\")?) | .name " $MODULE_ALIAS_FILE)
    [ -n "${matchedmodule}" ] && echo "${matchedmodule}"
  done
  while read line; do
    matchedmodule=$(jq -e -r '.modules[] | select(.alias | contains("pci")//contains("usb") | not ?) | .name' $MODULE_ALIAS_FILE)
    [ -n "${matchedmodule}" ] && echo "${matchedmodule}"
  done <<< "cat $MODULE_ALIAS_FILE"
}