#!/usr/bin/env bash
#
# Shutdown the system
#

echo "Content-type: application/json"
echo ""
echo "{\"success\": true}"

nohup sh -c 'sleep 1; /sbin/poweroff || poweroff' >/dev/null 2>&1 &
disown
