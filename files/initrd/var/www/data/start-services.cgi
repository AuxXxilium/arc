#!/usr/bin/env bash
#
# Start ttyd and dufs services after successful login
#

echo "Content-type: application/json"
echo ""

# Source arc.conf for port configuration
CONFIG_FILE="/etc/arc.conf"
if [ -f "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
fi

# Set defaults if not configured
TTYD_PORT="${TTYD_PORT:-7681}"
DUFS_PORT="${DUFS_PORT:-7304}"

# Check if ttyd is already running
if ! pidof ttyd > /dev/null 2>&1; then
    # Start ttyd with login - same as S99ttyd but forces root login
    #
    # -W is required from ttyd 1.7.4 on. The flag inverted: 1.7.3 had
    # "-R, --readonly" and was writable by default, 1.7.7 has
    # "-W, --writable" and is READONLY by default. Without it the
    # terminal renders and the websocket connects, but every keystroke
    # is silently dropped.
    /usr/bin/ttyd -W -p ${TTYD_PORT} -t titleFixed=Arc login -f root > /dev/null 2>&1 &
    TTYD_STARTED=true
else
    TTYD_STARTED=false
fi

# Check if dufs is already running
if ! pidof dufs > /dev/null 2>&1; then
    # Start dufs with same options as init script
    /usr/sbin/dufs -A -p ${DUFS_PORT} --assets /var/www/assets/ / > /dev/null 2>&1 &
    DUFS_STARTED=true
else
    DUFS_STARTED=false
fi

# Return status
echo "{"
echo "  \"success\": true,"
echo "  \"ttyd\": {"
echo "    \"port\": ${TTYD_PORT},"
echo "    \"started\": ${TTYD_STARTED},"
echo "    \"running\": true"
echo "  },"
echo "  \"dufs\": {"
echo "    \"port\": ${DUFS_PORT},"
echo "    \"started\": ${DUFS_STARTED},"
echo "    \"running\": true"
echo "  }"
echo "}"
