#!/usr/bin/env bash

echo "Content-type: text/plain"
echo ""

# get IP
# 1 - ethN
function getIP() {
  local IP=""
  if [ -n "${1}" ] && [ -d "/sys/class/net/${1}" ]; then
    IP=$(/sbin/ip addr show "${1}" scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -d'/' -f1 | head -1)
    [ -z "${IP}" ] && IP=$(/sbin/ip route show dev "${1}" 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p' | head -1)
  else
    IP=$(/sbin/ip addr show scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -d'/' -f1 | head -1)
    [ -z "${IP}" ] && IP=$(/sbin/ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\) metric .*/\1/p' | head -1)
  fi
  echo "${IP}"
  return 0
}

BOOTIPWAIT=3
ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 -name 'eth*' -exec basename {} \; | sort)"
for N in ${ETHX}; do
  COUNT=0
  while true; do
    CARRIER=$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)
    if [ "${CARRIER}" = "0" ]; then
      break
    elif [ -z "${CARRIER}" ]; then
      break
    fi
    COUNT=$((COUNT + 1))
    IP="$(getIP "${N}")"
    if [ -n "${IP}" ]; then
      if ! echo "${IP}" | grep -q "^169\.254\."; then
        IPCON="${IP}"
      fi
      break
    fi
  done
done
echo "${IPCON:-"No IP found"}"