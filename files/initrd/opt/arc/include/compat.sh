###############################################################################
# Compatibility boot

function compatboot () {
  # Locale
  KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
  if [ -n "${KEYMAP}" ]; then
    export LC_ALL="${KEYMAP}.UTF-8"
  fi
  # Timezone
  TIMEZONE="$(readConfigKey "time.timezone" "${USER_CONFIG_FILE}")"
  REGION="$(readConfigKey "time.region" "${USER_CONFIG_FILE}")"
  if [ -n "${TIMEZONE}" ] && [ -n "${REGION}" ]; then
    ln -sf "/usr/share/zoneinfo/right/${TIMEZONE}/${REGION}" /etc/localtime
  fi
  # Check for compatibility
  deleteConfigKey "nanover" "${USER_CONFIG_FILE}"
  return 0
}