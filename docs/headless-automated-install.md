# Headless / automated install

This guide is for operators who already know the target **model**, **platform**, and **DSM PAT** and want to configure and build the loader without the Config Mode browser (`:7080`).

Config Mode remains the recommended path for first-time users and when choosing a locked model (e.g. DS923+ in Arc 3.x).

On a 2-core, 4 GB RAM VM on a Zen 5600G host, a pre-seeded headless install can reach the DSM Web Assistant (`:5000`) in about **2 minutes** from first loader boot (measured 2026-07-31: DS923+, DSM 7.2.2-72806, Arc 3.1.0).

## Overview

1. Pre-seed `/mnt/p1/user-config.yml` with model, platform, version, and PAT fields.
2. Reboot into **Automated Mode** (`automated_arc`).
3. The loader configures, downloads PAT files, builds, and boots DSM.
4. Complete the DSM first-boot wizard in the browser (`:5000`).

Automated Mode runs `arc.sh` on the loader console (serial / local display). Dialog menus work there; do not call `arcModel` / `makearc` over SSH without a TTY.

## Required `user-config.yml` fields

| Key | Example | Notes |
|-----|---------|-------|
| `model` | `DS923+` | Set explicitly — do not rely on auto-select for locked models |
| `platform` | `r1000` | From `configs/data.yml` for your model |
| `productver` | `7.2` | Major DSM version |
| `buildnum` | `72806` | Build number |
| `smallnum` | `0` | Small revision |
| `paturl` | `https://global.download.synology.com/...` | PAT download URL |
| `pathash` | `1ab30d0ab9d9d5e53942e101c1011513` | PAT hash |
| `arc.patch` | `true` | Arc Patch (recommended for AME/QC/etc.) |
| `arc.offline` | `false` | **Required** for online PAT download |
| `arc.confdone` | `false` | Reset before rebuild |
| `arc.builddone` | `false` | Reset before rebuild |

### PAT lookup

On a running loader, PAT url/hash for a model/version live in:

```text
/mnt/p3/configs/data.yml
```

Example (DS923+, DSM 7.2.2-72806):

```yaml
r1000:
  "DS923+":
    "7.2.2-72806-0":
      url: "https://global.download.synology.com/download/DSM/release/7.2.2/72806/DSM_DS923%2B_72806.pat"
      hash: "1ab30d0ab9d9d5e53942e101c1011513"
```

Seed with external tools (e.g. `yq`) — avoid partial in-loader edits via SSH; they can corrupt YAML.

## Trigger Automated Mode

From the loader shell (or after SSH as `root`):

```bash
cd /opt/arc
. include/functions.sh
readData
rebootTo automated
```

`rebootTo automated` sets grub `next_entry=automated`, writes the p3 marker, and creates the p1 `/automated` file grub needs to expose the automated menuentry.

Alternatively:

```bash
echo "arc-${MODEL}-${PRODUCTVER}-${ARC_VERSION}" > /mnt/p3/automated
touch /mnt/p1/automated
grub-editenv /mnt/p1/boot/grub/grubenv set next_entry=automated
reboot
```

## Verify success

| Signal | Meaning |
|--------|---------|
| `/proc/cmdline` contains `automated_arc` | Automated boot ran |
| `arc.confdone` and `arc.builddone` are `true` | Build finished |
| Loader SSH closes, `http://<ip>:5000` responds | DSM Web Assistant up |

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Boots `force_arc` (Config Mode) instead of `automated_arc` | Missing `/mnt/p1/automated` before reboot |
| Stuck at upload dialog (`:7304`) with `confdone=true`, `builddone=false` | `arc.offline: true` — set to `false` when PAT url/hash are configured |
| `Loader Disk not found!` over SSH | Normal before `mountloader` runs; use Automated Mode reboot or see LOADER_DISK fallback |
| Invalid YAML / empty `platform` with `model` set | Run `resetBuildConfig` or re-seed with `yq` |

## Related

- [Arc Loader Custom](https://auxxxilium.github.io/arc) — automated installation variant
- Config Mode UI: `http://<loader-ip>:7080`
- FAQ & Wiki: https://xpenology.tech/wiki
