if [ -z "${KERNELLOAD}" ]; then
  writeConfigKey "arc.kernelload" "power" "${USER_CONFIG_FILE}"
fi
# Add Onlinemode to old configs
if [ -z "${ONLINEMODE}" ]; then
  writeConfigKey "arc.onlinemode" "true" "${USER_CONFIG_FILE}"
fi
# Reset DirectDSM if User boot to Config
if [ "${DIRECTDSM}" = "true" ]; then
  writeConfigKey "arc.directdsm" "false" "${USER_CONFIG_FILE}"
fi