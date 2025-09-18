#!/usr/bin/env bash

echo "Content-type: text/plain"
echo ""

# Lock to ensure only one instance runs
LOCK_FILE="/tmp/remote.lock"
exec 911>"${LOCK_FILE}"
flock -n 911 || {
  echo "Another instance is already running."
  exit 1
}
trap 'flock -u 911; rm -f "${LOCK_FILE}"' EXIT INT TERM HUP

# Start remote assistance
{
  echo "Starting Remote Assistance..."
  LINK=$(sshx -q --name "Arc Remote" 2>&1)
  if [ $? -ne 0 ]; then
    echo "Failed to start remote assistance."
    exit 1
  fi

  echo "Remote Assistance Link: ${LINK}"

  # Send notifications if enabled
  DISCORDNOTIFY=$(readConfigKey "arc.discordnotify" "/etc/arc/config")
  WEBHOOKNOTIFY=$(readConfigKey "arc.webhooknotify" "/etc/arc/config")

  if [ "${DISCORDNOTIFY}" = "true" ]; then
    USERID=$(readConfigKey "arc.userid" "/etc/arc/config")
    sendDiscord "${USERID}" "Remote is running at: ${LINK}"
  fi

  if [ "${WEBHOOKNOTIFY}" = "true" ]; then
    WEBHOOKURL=$(readConfigKey "arc.webhookurl" "/etc/arc/config")
    sendWebhook "${WEBHOOKURL}" "Remote is running at: ${LINK}"
  fi
} || {
  echo "An error occurred while setting up remote assistance."
}

exit 0