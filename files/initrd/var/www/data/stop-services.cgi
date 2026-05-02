#!/usr/bin/env bash
#
# Stop ttyd and dufs services on logout
#

echo "Content-type: application/json"
echo ""

# Stop ttyd using killall
if pidof ttyd > /dev/null 2>&1; then
    killall -q ttyd
    TTYD_STOPPED=true
else
    TTYD_STOPPED=false
fi

# Stop dufs using killall
if pidof dufs > /dev/null 2>&1; then
    killall -q dufs
    DUFS_STOPPED=true
else
    DUFS_STOPPED=false
fi

# Return status
echo "{"
echo "  \"success\": true,"
echo "  \"ttyd_stopped\": ${TTYD_STOPPED},"
echo "  \"dufs_stopped\": ${DUFS_STOPPED}"
echo "}"
