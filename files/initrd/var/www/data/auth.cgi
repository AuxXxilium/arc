#!/usr/bin/env bash
#
# Authentication CGI script for Arc Web Config
# Handles login, logout and session verification against /etc/shadow
#

SESSION_DIR="/tmp/arc_sessions"
SESSION_LIFETIME=86400 # 24 hours in seconds

# Always emit a valid header block, even on unexpected failure, so the
# webserver never sees an empty CGI response.
send_json() {
    echo "Content-Type: application/json"
    echo "Cache-Control: no-cache, no-store, must-revalidate"
    echo "Pragma: no-cache"
    echo "Expires: 0"
    echo ""
    echo "$1"
}

fail_safe() {
    send_json '{"success": false, "message": "Internal error"}'
    exit 0
}
trap fail_safe ERR

urldecode() {
    local URL_ENCODED="${1//+/ }"
    printf '%b' "${URL_ENCODED//%/\\x}"
}

# Read parameters from POST body (falling back to the query string)
parse_params() {
    local DATA=""
    if [ "${REQUEST_METHOD}" = "POST" ]; then
        [ -n "${CONTENT_LENGTH}" ] && read -r -N "${CONTENT_LENGTH}" DATA
    fi
    [ -z "${DATA}" ] && DATA="${QUERY_STRING}"

    local IFS='&'
    for PARAM in ${DATA}; do
        local KEY="${PARAM%%=*}"
        local VALUE="${PARAM#*=}"
        case "${KEY}" in
        action) ACTION=$(urldecode "${VALUE}") ;;
        username) USERNAME=$(urldecode "${VALUE}") ;;
        password) PASSWORD=$(urldecode "${VALUE}") ;;
        token) TOKEN=$(urldecode "${VALUE}") ;;
        esac
    done
}

# Reject anything that could escape the session directory
valid_token() {
    case "$1" in
    "" | *[!a-f0-9]*) return 1 ;;
    esac
    return 0
}

verify_password() {
    local USER="$1"
    local PASS="$2"

    local HASH
    HASH="$(awk -F: -v u="${USER}" '$1 == u {print $2; exit}' /etc/shadow 2>/dev/null)"

    # No entry, or a locked/passwordless account
    case "${HASH}" in
    "" | '*' | '!' | '!!') return 1 ;;
    esac

    # Hashes are written by loaderPassword as: $id$salt$checksum
    local ID SALT CHECKSUM
    IFS='$' read -r _ ID SALT CHECKSUM <<<"${HASH}"
    if [ -z "${ID}" ] || [ -z "${SALT}" ] || [ -z "${CHECKSUM}" ]; then
        return 1
    fi

    local COMPUTED
    COMPUTED="$(openssl passwd "-${ID}" -salt "${SALT}" "${PASS}" 2>/dev/null)"
    [ -n "${COMPUTED}" ] && [ "${COMPUTED}" = "${HASH}" ]
}

create_session_token() {
    openssl rand -hex 32 2>/dev/null
}

save_session() {
    local USER="$1"
    local TOK="$2"

    mkdir -p "${SESSION_DIR}" 2>/dev/null || return 1
    chmod 700 "${SESSION_DIR}" 2>/dev/null

    local SESSION_FILE="${SESSION_DIR}/${TOK}"
    printf '%s\n%s\n' "${USER}" "$(date +%s)" >"${SESSION_FILE}" 2>/dev/null || return 1
    chmod 600 "${SESSION_FILE}" 2>/dev/null
    return 0
}

verify_session() {
    local USER="$1"
    local TOK="$2"

    valid_token "${TOK}" || return 1

    local SESSION_FILE="${SESSION_DIR}/${TOK}"
    [ -f "${SESSION_FILE}" ] || return 1

    local STORED_USER STAMP
    { read -r STORED_USER; read -r STAMP; } <"${SESSION_FILE}" 2>/dev/null

    case "${STAMP}" in
    "" | *[!0-9]*) rm -f "${SESSION_FILE}" 2>/dev/null; return 1 ;;
    esac

    local NOW
    NOW="$(date +%s)"
    if [ "${STORED_USER}" = "${USER}" ] && [ "$((NOW - STAMP))" -lt "${SESSION_LIFETIME}" ]; then
        return 0
    fi

    rm -f "${SESSION_FILE}" 2>/dev/null
    return 1
}

delete_session() {
    local TOK="$1"
    valid_token "${TOK}" || return 0
    rm -f "${SESSION_DIR}/${TOK}" 2>/dev/null
    return 0
}

cleanup_expired_sessions() {
    [ -d "${SESSION_DIR}" ] || return 0

    local NOW
    NOW="$(date +%s)"
    for SESSION_FILE in "${SESSION_DIR}"/*; do
        [ -f "${SESSION_FILE}" ] || continue
        local STAMP
        { read -r _; read -r STAMP; } <"${SESSION_FILE}" 2>/dev/null
        case "${STAMP}" in
        "" | *[!0-9]*) rm -f "${SESSION_FILE}" 2>/dev/null; continue ;;
        esac
        [ "$((NOW - STAMP))" -ge "${SESSION_LIFETIME}" ] && rm -f "${SESSION_FILE}" 2>/dev/null
    done
    return 0
}

ACTION=""
USERNAME=""
PASSWORD=""
TOKEN=""

parse_params
cleanup_expired_sessions

case "${ACTION}" in
login)
    if [ -z "${USERNAME}" ] || [ -z "${PASSWORD}" ]; then
        send_json '{"success": false, "message": "Username and password are required"}'
        exit 0
    fi

    if verify_password "${USERNAME}" "${PASSWORD}"; then
        NEW_TOKEN="$(create_session_token)"
        if [ -n "${NEW_TOKEN}" ] && save_session "${USERNAME}" "${NEW_TOKEN}"; then
            send_json "{\"success\": true, \"token\": \"${NEW_TOKEN}\", \"username\": \"${USERNAME}\"}"
        else
            send_json '{"success": false, "message": "Failed to create session"}'
        fi
    else
        send_json '{"success": false, "message": "Invalid username or password"}'
    fi
    ;;
verify)
    if [ -z "${USERNAME}" ] || [ -z "${TOKEN}" ]; then
        send_json '{"success": false}'
        exit 0
    fi

    if verify_session "${USERNAME}" "${TOKEN}"; then
        send_json '{"success": true}'
    else
        send_json '{"success": false}'
    fi
    ;;
logout)
    [ -n "${TOKEN}" ] && delete_session "${TOKEN}"
    send_json '{"success": true}'
    ;;
*)
    send_json '{"success": false, "message": "Invalid action"}'
    ;;
esac

exit 0
