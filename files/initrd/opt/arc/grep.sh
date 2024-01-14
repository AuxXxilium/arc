#!/usr/bin/env bash

cd /tmp
tar cfvz log.tar.gz /mnt/p1/logs/
cd /opt/arc
echo "Logs can be found at /tmp/log.tar.gz"