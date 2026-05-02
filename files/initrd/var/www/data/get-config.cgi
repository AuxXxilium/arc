#!/usr/bin/env bash

echo "Content-type: text/plain"
echo ""

# Read and output arc.conf
if [ -f "/etc/arc.conf" ]; then
    cat /etc/arc.conf
else
    # Return defaults if file doesn't exist
    echo "DUFS_PORT=7304"
    echo "TTYD_PORT=7681"
fi
