function getmodules() {
    echo "{" >> $MODULE_ALIAS_FILE
    echo "\"modules\" : [" >> $MODULE_ALIAS_FILE
    for module in $(ls /tmp/modules/*.ko); do
        if [ $(modinfo $module --field alias| wc -l) -ge 1 ]; then
            for alias in $(modinfo $module --field alias); do
                echo "{"
                echo "\"name\" :  \"${module}\"",
                echo "\"alias\" :  \"${alias}\""
                echo "}",
            done
        fi
    done | sed '$ s/,//' >> $MODULE_ALIAS_FILE
    echo "]" >> $MODULE_ALIAS_FILE
    echo "}" >> $MODULE_ALIAS_FILE
    findmodules
}

function findmodules() {
    lspci -n | while read line; do
        vendor="$(echo $line | cut -c 15-18)"
        device="$(echo $line | cut -c 20-23)"
        selectmodules "${vendor}" "${device}"
    done
}

function selectmodules() {
    vendor="$(echo $1 | awk '{print toupper($0)}')"
    device="$(echo $2 | awk '{print toupper($0)}')"
    pciid="${vendor}d0000${device}"
    MODULES=$(jq -e -r ".modules[] | select(.alias | contains(\"${pciid}\")?) | .name " $MODULE_ALIAS_FILE | sort | uniq -c | awk -F" " '$1<2 {print $2}')
	ID=$(echo "${MODULES}" | sed 's:^/tmp/modules/::' | cut -f 1 -d '.')
    if [ -f "${TMP_PATH}/modules/${ID}.ko" ]; then
      writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
    fi
}

function miscmodules() {
        MODULES=$(jq -e -r ".modules[] | select((.alias | contains(\"usb\")) or (.alias | contains(\"pci\")) | not) | .name " $MODULE_ALIAS_FILE)
        ID=$(echo "${MODULES}" | sed 's:^/tmp/modules/::' | cut -f 1 -d '.')
        while IFS= read -r line; do
        if [ -f "${TMP_PATH}/modules/${line}.ko" ]; then
            writeConfigKey "modules.${line}" "" "${USER_CONFIG_FILE}"
        fi
        done <<< "$ID"
}