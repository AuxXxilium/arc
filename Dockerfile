# Wraps a built arc.img in qemux/qemu so `docker run` boots it directly,
# without users needing to write their own Compose file / volume mount.
# See docker.md for the manual (bind-mount) alternative.
FROM qemux/qemu:latest

COPY arc.img /arc.img

ENV BOOT=""
ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_FMT="qcow2"
ENV DISK_TYPE="sata"
ENV DISK_SIZE="32G"
ENV ARGUMENTS="-device nec-usb-xhci,id=usb0,multifunction=on -drive file=/arc.img,media=disk,format=raw,if=none,id=udisk1 -device usb-storage,bus=usb0.0,port=1,drive=udisk1,bootindex=999,removable=on"

# DSM management (5000/5001) and Arc's own web config/file-browser/terminal
# (7080/7304/7681, matching HTTPPORT/DUFSPORT/TTYDPORT defaults) -- see
# docker.md for the port meanings and how to remap them if you changed
# these via the loader's "Change Loader Ports" menu.
EXPOSE 5000 5001 7080 7304 7681
