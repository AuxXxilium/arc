#!/usr/bin/env bash
# Change Password CGI script for Arc Web Config
# Updates user password and persists to initrd

# JSON response function
send_json() {
    echo "Content-Type: application/json"
    echo "Cache-Control: no-cache, no-store, must-revalidate"
    echo "Pragma: no-cache"
    echo "Expires: 0"
    echo ""
    echo "$1"
}

# URL decode function
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# Parse query string manually
parse_qs() {
    local IFS='&'
    for param in $QUERY_STRING; do
        local key="${param%%=*}"
        local value="${param#*=}"
        case "$key" in
            username) USERNAME=$(urldecode "$value") ;;
            currentPassword) CURRENT_PASSWORD=$(urldecode "$value") ;;
            newPassword) NEW_PASSWORD=$(urldecode "$value") ;;
        esac
    done
}

# Parse parameters from query string
parse_qs

# Validate input
if [ -z "$USERNAME" ] || [ -z "$CURRENT_PASSWORD" ] || [ -z "$NEW_PASSWORD" ]; then
    send_json '{"success": false, "message": "All fields are required"}'
    exit 0
fi

# Validate password length
if [ ${#NEW_PASSWORD} -lt 4 ]; then
    send_json '{"success": false, "message": "Password must be at least 4 characters"}'
    exit 0
fi

# Call loaderPassword using command-line interface (consistent approach)
if /opt/arc/arc-functions.sh loaderPassword "${USERNAME}" "${NEW_PASSWORD}" "false" 2>/dev/null; then
    send_json '{"success": true, "message": "Password changed and persisted successfully"}'
else
    send_json '{"success": false, "message": "Failed to change password"}'
fi
