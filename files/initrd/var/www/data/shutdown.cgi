#!/usr/bin/env bash
#
# Shut down or restart the system (action=poweroff|reboot, default poweroff)
#

DATA=""
if [ "${REQUEST_METHOD}" = "POST" ] && [ -n "${CONTENT_LENGTH}" ]; then
  read -r -N "${CONTENT_LENGTH}" DATA
fi
[ -z "${DATA}" ] && DATA="${QUERY_STRING}"

case "&${DATA}&" in
  *"&action=reboot&"*) CMD='/sbin/reboot || reboot' ;;
  *) CMD='/sbin/poweroff || poweroff' ;;
esac

echo "Content-type: application/json"
echo ""
echo "{\"success\": true}"

nohup sh -c "sleep 1; ${CMD}" >/dev/null 2>&1 &
disown
