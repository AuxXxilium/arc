# Arc Loader PXE 网络启动指南

## 概述

将 Arc Loader（Synology Xpenology/Redpill 引导器）从 USB 启动改为 PXE 网络启动，彻底摆脱 U 盘依赖。

**原理**：将已配置好的 Arc 磁盘镜像（arc.img）压缩后嵌入到 initrd 中，PXE 启动时内核将镜像加载到内存，通过 loop 设备模拟物理磁盘，Arc 正常识别并引导 DSM。

## 架构

```
启动链路：

  目标机器 BIOS PXE Boot
       ↓
  路由器 dnsmasq (TFTP) → undionly.kpxe
       ↓
  undionly.kpxe → TFTP 获取 boot.ipxe
       ↓
  boot.ipxe → HTTP 下载 bzImage + initrd
       ↓
  Linux 内核启动 → /init (init-pxe.sh)
       ↓
  解压内嵌 arc.img.gz 到 tmpfs → losetup 创建 loop 设备
       ↓
  exec /init.buildroot → Arc 正常流程 → kexec DSM
```

## 前置条件

- 一台已通过 U 盘完成 Arc 配置和 DSM 构建的目标 NAS
- HTTP 服务器（如 nginx），用于托管 bzImage、initrd、boot.ipxe
- 路由器支持 dnsmasq，配置 TFTP 和 PXE 引导
- WSL2（Ubuntu）用于构建 initrd（需要 losetup、zstd 等工具）

## 修改的文件及内容

### 1. functions.sh — getBus() 函数修改

文件路径：`arc/files/initrd/opt/arc/include/functions.sh`

新增两行，让 loop 设备被识别为 `virtio` 而非 `usb`，避免 VID/PID 检查失败：

```bash
function getBus() {
  local BUS=""
  [ -f "/.dockerenv" ] && BUS="docker"
  # ↓↓↓ 新增：PXE loop 设备识别为 virtio ↓↓↓
  [ -z "${BUS}" ] && [[ "${1}" == /dev/loop* ]] && BUS="virtio" && echo "${BUS}" && return 0
  # ... 原有逻辑不变
}
```

### 2. init-pxe.sh — 新增，PXE 启动入口脚本

文件路径：`pxe/init-pxe.sh`

替换 buildroot 原始 `/init`，核心流程：

1. 挂载 proc/sysfs/devtmpfs
2. 检测物理 ARC 磁盘（U 盘），有则跳过
3. 创建 2G tmpfs 内存盘
4. 解压内嵌的 `arc.img.gz` 到内存
5. `losetup -P` 创建带分区扫描的 loop 设备
6. `exec /init.buildroot` 进入 Arc 正常流程

关键点：使用 `#!/bin/sh`（非 bash）确保 busybox 兼容。

### 3. boot.ipxe — 新增，iPXE 启动脚本

文件路径：`pxe/boot.ipxe`

```
kernel ${http-path}/bzImage ${cmdline} dsm_arc
initrd ${http-path}/initrd
```

- `vga=792`：设置 1024x768x32 帧缓冲，解决 ttyd 界面显示不全
- `dsm_arc`：直接引导 DSM 模式（已构建完成）
- 不再需要 `pxe_server` 参数（arc.img 已内嵌）

### 4. rebuild-embedded.sh — 新增，WSL 构建脚本

文件路径：`pxe/rebuild-embedded.sh`

构建流程：
1. 从 arc.img 提取 bzImage + initrd（内核 + 基础 buildroot）
2. 解压 initrd → 注入 init-pxe.sh + 修改后的 functions.sh
3. 压缩 arc-configured.img 为 arc.img.gz 嵌入 initrd
4. zstd -19 重新打包
5. 输出到 pxe-output/

### 5. trim.sh — 新增，裁剪镜像脚本

文件路径：`pxe/trim.sh`

将完整的 U 盘镜像（~8GB）裁剪到 ~1.85GB（仅保留已分配分区部分）。

## 构建步骤（从零开始）

### 第一步：提取已配置的 arc.img

1. 将已配置好 Arc 的 U 盘插入 Windows 电脑
2. 用 Win32 Disk Imager 制作完整镜像
3. 在 WSL 中执行 trim.sh 裁剪到 ~1.85GB，得到 `arc-configured.img`

```bash
wsl -d Ubuntu -u root -- bash /mnt/d/software/Synology_Arc/pxe/trim.sh
```

### 第二步：构建 PXE initrd

```bash
wsl -d Ubuntu -u root -- bash /mnt/d/software/Synology_Arc/pxe/rebuild-embedded.sh
```

输出到 `pxe/pxe-output/`：bzImage（~8MB）、initrd（~1.1GB）、boot.ipxe

### 第三步：部署

**HTTP 服务器根目录**：放入 `bzImage`、`initrd`、`boot.ipxe`

**路由器 TFTP 目录**（如 `/jffs/pxe/`）：放入 `undionly.kpxe`、`boot.ipxe`

**路由器 dnsmasq 配置**：
```
dhcp-match=set:ipxe,175
dhcp-boot=tag:!ipxe,undionly.kpxe
dhcp-boot=tag:ipxe,boot.ipxe
```

### 第四步：PXE 启动

1. 目标机器 BIOS 设为 Network Boot（PXE）
2. 开机自动完成：PXE → undionly.kpxe → boot.ipxe → HTTP 下载 → Arc → DSM

## 更新配置

如果需要修改 Arc 配置（换型号、DSM 版本等）：

1. 用 U 盘启动，在 Arc 中修改配置
2. 重新提取 arc-configured.img（重复第一步）
3. 重新构建 initrd（重复第二步）
4. 重新部署（重复第三步）

## 注意事项

| 项目 | 说明 |
|------|------|
| 内存需求 | 至少 4GB（arc.img 解压占 ~2GB tmpfs） |
| initrd 大小 | ~1.1GB，首次 HTTP 下载需等待 |
| 重启行为 | 每次重启重新从网络加载，配置变更不会自动持久化 |
| U 盘兼容 | 同时插 U 盘时优先使用 U 盘，不影响原有方式 |
| 分辨率调整 | boot.ipxe 中 `vga=792`（1024x768x32）可改为其他 VESA 模式 |

## 故障排查

| 错误 | 原因 | 解决 |
|------|------|------|
| "loader disk does not support" | getBus 将 loop 识别为 usb | 确认 functions.sh 有 loop→virtio 补丁 |
| "bootloader disk not found" | loop 设备未创建 | 检查 init-pxe.sh 中 losetup 是否执行 |
| "Rebooting to config mode" | arc.img 未配置（builddone=false） | 使用已配置的 arc-configured.img |
| ttyd 只显示左上角 | 帧缓冲分辨率低 | cmdline 加 `vga=792` |
| "failed to download arc.img" | HTTP 下载模式网络不可用 | 使用嵌入式方案（当前方案） |
