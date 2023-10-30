#!/usr/bin/env bash

function use() {
  echo "Use: ${0} junior|config"
  exit 1
}

# Sanity checks
if [ ! ${USER} = "root" ]; then
  exec sudo $0 $@
fi
[ -z "${1}" ] && use
[ ! "${1}" = "junior" -a ! "${1}" = "config" ] && use
echo "Rebooting to ${1} mode"
echo 1 > /proc/sys/kernel/syno_install_flag
mount /dev/synoboot1 /mnt
GRUBPATH="$(dirname $(find /mnt/ -name grub.cfg | head -1))"
ENVFILE="${GRUBPATH}/grubenv"
[ ! -f "${ENVFILE}" ] && grub-editenv ${ENVFILE} create

grub-editenv ${ENVFILE} set next_entry="${1}"
umount /mnt
[ -x /usr/syno/sbin/synopoweroff ] && \
  /usr/syno/sbin/synopoweroff -r ||
  reboot