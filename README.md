<div align="center">

<img width="160" alt="arc" src="files/initrd/var/www/data/arc_loader.png">

### Arc — Redpill loader for DSM 7.x

A DSM 7.x loader for x86-64 with guided setup, wide hardware support and addons.<br>
Configure it on the machine's screen or from your browser.

<a href="https://github.com/AuxXxilium/arc/releases/latest"><img alt="Download" src="https://img.shields.io/badge/download-red?style=for-the-badge&label=latest&color=%23FF0000"></a>
<a href="https://xpenology.tech/wiki"><img alt="Wiki" src="https://img.shields.io/badge/read_first-blue?style=for-the-badge&label=wiki&color=%230066CC"></a>
<a href="https://discord.auxxxilium.tech"><img alt="Discord" src="https://img.shields.io/badge/discord-5865F2?style=for-the-badge&label=chat&color=%235865F2"></a>

</div>

---

> [!IMPORTANT]
> * Arc and DSM are **independent** from each other — Arc is a boot helper for DSM.
> * **Commercial use is not permitted and strictly forbidden.**
> * DSM and all parts of it are under copyright / ownership by Synology Inc.
> * Arc is based on full DSM, not vDSM.
> * The loader is free and will stay free forever. If you paid a suspicious person for it, I can't help you — I'm not connected to them.

> [!WARNING]
> Any user-specific modification of the tested and prebuilt loader images can cause irreversible data loss. Back up anything on the machine's disks first. The project is released for educational and learning purposes only, and I'm not liable for damage or loss of any kind.

---

## ✨ What Arc does

Arc turns an x86-64 PC, server or VM into a DSM 7.x machine. You write it to a disk, boot from it, and configure it in the menu — on the machine's screen, or at `http://<loader-ip>:7080` in a browser.

* **Guided setup** — Choose Model → Build Loader → Boot Loader, with DSM version, addons and modules picked for you and changeable before the build
* **Wide hardware support** — 4.4 and 5.10 based platforms, drivers for many controllers and NICs, SATA PortMap and DTS map options for the disk layout
* **Custom kernels** — on the 5.10 platforms with DSM 7.3 and later, choose between Synology's stock kernel and [arc-custom](https://github.com/AuxXxilium/arc-custom)'s kernels with hybrid CPU, wider hardware and 64 thread support
* **Arc Patch** — a serial and MACs for the chosen model, with AME, QuickConnect, push notifications and more; or bring your own, or use random ones
* **Addons and modules** — select addons (stable and beta) and kernel modules per build
* **Hardware options** — NIC order, fan control, CPU scaling governor, GPU passthrough (IOMMU), USB disks as internal, eMMC and SATA DOM boot
* **DSM options** — edit cmdline and synoinfo, add a user or change a password, allow a DSM downgrade, reset the network config, force-enable SSH, clear blocked IPs and the update cache
* **Web tools** — the web config at `:7080` with a terminal and a file manager, for machines without a screen
* **Loader tools** — backup, restore and recovery, static IP, loader password and ports, clone the loader to another disk, Format Disks, offline mode
* **Updates itself** — from the GitHub release, latest or beta, or from an update file

---

## 🧭 How it works

```
GRUB → Arc (Buildroot) → menu on screen, web config on :7080
                       └─ Build Loader: DSM boot files → kernel (stock or arc-custom)
                          → ramdisk patched → addons and modules added
        Boot Loader:  Arc → kexec → DSM 7.x → DSM's own installer
```

Arc runs on its own small Linux system; DSM runs on the kernel of its platform — **4.4.302** or **5.10.55**. DSM's identity — model, serial, MACs — goes on the kernel command line, and the `redpill` module does what the command line cannot. On hypervisors where kexec is not reliable, **Directboot** reboots straight into DSM instead.

---

## 🖥️ Supported

| Platform | Kernel | DSM |
| :-- | :-- | :-- |
| `apollolake`, `broadwell`, `broadwellnk`, `broadwellnkv2`, `broadwellntbap`, `denverton`, `geminilake`, `purley`, `r1000`, `v1000` | 4.4.302 | 7.2, 7.3, 7.4 |
| `epyc7002`, `geminilakenk`, `r1000nk`, `v1000nk` | 5.10.55 | 7.2, 7.3, 7.4 — custom kernel from 7.3 |
| `epyc7003`, `epyc7003ntb`, `icelaked` | 5.10.55 | 7.4 |

The platforms and models come from [arc-configs](https://github.com/AuxXxilium/arc-configs); the menu shows which models fit the machine.

---

## 📋 What you need

* An x86-64 machine or VM you own
* A disk for the loader, 4 GB or more — a USB stick, or a SATA disk in a VM
* At least one disk for DSM
* A wired network
* Internet while building, to fetch DSM's boot files

Arc also runs in Docker, through a QEMU VM — see [docker.md](docker.md).

---

## ⬆️ Updates

Arc updates itself. Under **Update**, **Update Loader** replaces the loader's files in place and keeps your configuration; **Upgrade Loader** reflashes it. Both fetch the latest release or the beta, together with addons, modules, configs, patches and kernels. **Update Dependencies** fetches only those.

No internet on the machine? Arc can also update offline from an update file from the [releases](https://github.com/AuxXxilium/arc/releases/latest).

---

## 📚 Documentation

* [Documentation](https://xpenology.tech/wiki) — **read this first**

---

## 🧰 More from the Arc Project

| Project | Description |
| :-- | :-- |
| [Arc Loader Essential](https://github.com/AuxXxilium/arc-essential) | Arc with reduced size, only for Linux 5.x models |
| [Arc Loader Beta](https://github.com/AuxXxilium/arc-beta) | Beta releases of Arc |
| [Arc Loader Custom](https://auxxxilium.github.io/arc) | Loader with automated installation |
| [arx](https://github.com/AuxXxilium/arx) | The future of Arc — set up entirely from your browser |
| [Arc Control](https://github.com/AuxXxilium/arc-control) | DSM app for loader settings, monitoring and hardware tuning |
| [Arc Utilities](https://github.com/AuxXxilium/arc-utils) | Tools to install, patch and activate DSM apps on Xpenology |
| [AuxXxilium](https://github.com/AuxXxilium) | Everything else from the Arc Project |

---

### Developer

- <a href="https://github.com/AuxXxilium">AuxXxilium</a>
- <a href="https://github.com/FulcrumCode">Fulcrum</a>

### Thanks

* **TTG** and everyone who continued the original redpill-load project, which the `redpill` module is based on
* **pocopico, jumkey, fbelavenuto, wjz304, PeterSuh-Q3** and others, whose code and work are part of Arc and its addons

<div align="center">

[![Stars](https://img.shields.io/github/stars/AuxXxilium/arc?style=for-the-badge&logo=github)](https://github.com/AuxXxilium/arc)
[![Discord](https://img.shields.io/discord/639072565155069962?style=for-the-badge&logo=discord&label=Discord)](https://discord.auxxxilium.tech)

</div>
