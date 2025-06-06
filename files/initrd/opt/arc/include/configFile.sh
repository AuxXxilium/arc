###############################################################################
# Delete a key in config file
# 1 - Path of Key
# 2 - Path of yaml config file
function deleteConfigKey() {
  yq eval 'del(.'${1}')' --inplace "${2}" 2>/dev/null
}

###############################################################################
# Write to yaml config file
# 1 - Path of Key
# 2 - Value
# 3 - Path of yaml config file
function writeConfigKey() {
  local value="${2}"
  [ "${value}" = "{}" ] && yq eval ".${1} = {}" --inplace "${3}" 2>/dev/null || yq eval ".${1} = \"${value}\"" --inplace "${3}" 2>/dev/null
}

###############################################################################
# Read key value from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Return Value
function readConfigKey() {
  local RESULT
  RESULT=$(yq eval '.'${1}' | explode(.)' "${2}" 2>/dev/null)
  [ "${RESULT}" = "null" ] && echo "" || echo "${RESULT}"
}

###############################################################################
# Write to yaml config file
# 1 - Modules
# 2 - Path of yaml config file
function mergeConfigModules() {
  local MS="ARCMOD\n${1// /\\n}"
  local L="$(echo -en "${MS}" | awk '{print "modules."$1":"}')"
  local xmlfile=$(mktemp)
  echo -en "${L}" | yq -p p -o=yaml >"${xmlfile}"
  deleteConfigKey "modules.\"ARCMOD\"" "${xmlfile}"
  yq eval-all --inplace 'select(fileIndex == 0) * select(fileIndex == 1)' "${2}" "${xmlfile}" 2>/dev/null
  rm -f "${xmlfile}"
}

###############################################################################
# Write to yaml config file if key not exists
# 1 - Path of Key
# 2 - Value
# 3 - Path of yaml config file
function initConfigKey() {
  [ -z "$(readConfigKey "${1}" "${3}")" ] && writeConfigKey "${1}" "${2}" "${3}" || true
}

###############################################################################
# Read Entries as map(key=value) from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns map of values
function readConfigMap() {
  yq eval '.'${1}' | explode(.) | to_entries | map([.key, .value] | join(": ")) | .[]' "${2}" 2>/dev/null
}

###############################################################################
# Read an array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array/map of values
function readConfigArray() {
  yq eval '.'${1}'[]' "${2}" 2>/dev/null
}

###############################################################################
# Read Entries as array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array of values
function readConfigEntriesArray() {
  yq eval '.'${1}' | explode(.) | to_entries | map([.key])[] | .[]' "${2}" 2>/dev/null
}

###############################################################################
# Check yaml config file
# 1 - Path of yaml config file
# Returns error information
function checkConfigFile() {
  yq eval "${1}" 2>&1
}