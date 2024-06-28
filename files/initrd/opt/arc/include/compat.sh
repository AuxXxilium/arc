[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" 2>/dev/null && pwd)"

. ${ARC_PATH}/include/functions.sh

###############################################################################
# Compatibility boot

function compatboot () {
  # Remove old Addons
  if arrayExistItem "codecpatch:" $(readConfigMap "addons" "${USER_CONFIG_FILE}"); then
    deleteConfigKey "addons.codecpatch" "${USER_CONFIG_FILE}"
  fi
  return 0
}