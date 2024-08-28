###############################################################################
# Compatibility boot

function compatboot () {
  # Check for compatibility
  deleteConfigKey "nanover" "${USER_CONFIG_FILE}"
  return 0
}