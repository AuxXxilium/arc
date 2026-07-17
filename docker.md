# Running Arc in Docker

Arc can be run under Docker by running `arc.img` inside a full
hardware-emulated VM ([qemux/qemu](https://github.com/qemus/qemu)) that lives
inside a Docker container. QEMU (with `/dev/kvm` acceleration) boots the
image exactly like real hardware would, and DSM runs inside that emulated
machine. This is a normal, fully working way to run Arc + DSM.

## Option 1: Prebuilt image (quickest)

Every release with Docker Hub publishing enabled ships a ready-to-run image
with `arc.img` already baked in — no manual disk setup needed:

```sh
docker run -d --name arc \
  --device /dev/kvm --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -p 5000:5000 -p 5001:5001 -p 7080:7080 -p 7304:7304 -p 7681:7681 \
  -v ./data:/storage \
  auxxxilium/arc:latest
```

Use `auxxxilium/arc:<version>` instead of `:latest` to pin a specific
release. See the [Dockerfile](Dockerfile) for exactly what this image sets.

## Option 2: Build and run your own image

Build `arc.img` first (see the main [README](README.md) / `img-gen.sh`), then
run it with the following Docker Compose file:

```yaml
version: "3.9"
services:
  arc:
    image: qemux/qemu:latest
    container_name: arc
    environment:
      BOOT: ""
      RAM_SIZE: "4G"      # >= 4G recommended for DSM
      CPU_CORES: "2"
      DISK_FMT: "qcow2"
      DISK_TYPE: "sata"
      DISK_SIZE: "32G"    # data disk size
      ARGUMENTS: "-device nec-usb-xhci,id=usb0,multifunction=on -drive file=/arc.img,media=disk,format=raw,if=none,id=udisk1 -device usb-storage,bus=usb0.0,port=1,drive=udisk1,bootindex=999,removable=on"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - 5000:5000   # DSM management
      - 5001:5001   # DSM management (HTTPS)
      - 7080:7080   # Arc web config (HTTPPORT)
      - 7304:7304   # Arc file browser (DUFSPORT)
      - 7681:7681   # Arc web terminal (TTYDPORT)
    volumes:
      - ./arc.img:/arc.img
      - ./data:/storage
    restart: always
    stop_grace_period: 2m
```

Notes:

- Replace `./arc.img` with the actual path to your built image.
- The port list matches Arc's own defaults (`HTTP_PORT`/`DUFS_PORT`/`TTYD_PORT`
  in `/etc/arc.conf`, falling back to `7080`/`7304`/`7681`) plus DSM's own
  `5000`/`5001` once DSM has booted inside the VM. If you changed these via
  the loader's "Change Loader Ports" menu, update the port mappings to match.
- `/dev/kvm` is required for hardware-accelerated virtualization; without it
  QEMU falls back to slow software emulation.
- Once running, configure the loader at `http://<host>:7080` the same way
  you would on real hardware.
