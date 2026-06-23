# lmi-rootfs-builder

面向 Xiaomi lmi / SM8250 mainline Linux 启动流程的 arm64 RootFS 构建项目。

这个仓库已经不再以 Android LXC / Droidspaces / Termux:X11 容器为主线。当前主线是为刷入 `userdata` 的原生 Linux rootfs 生成可用的发行版根文件系统，配合已经适配好的 lmi boot/kernel 使用。

## 项目定位

- 使用 GitHub Actions 在 arm64 runner 上构建 rootfs tarball。
- 提供 KDE Native 桌面 rootfs 和 Server/headless rootfs 两条构建线。
- 默认集成 lmi 固件覆盖、SSH、NetworkManager、常用设备访问组和首次启动服务。
- 使用发行版自带 Mesa/Freedreno 栈，不使用 `mesa-for-android-container`。
- 不包含 Droidspaces、Termux:X11、anland、Android 容器音频转发等旧容器方案组件。

## GitHub Actions

仓库主要使用两个 workflow：

- `Build LMI Native RootFS`
  构建带 KDE/桌面可选项的原生 rootfs。

- `Build LMI Server RootFS`
  构建无桌面 server/headless rootfs。该 workflow 固定关闭 KDE 和 Fcitx5。

构建完成后会上传 `.tar.xz` artifact，并在成功时发布到 Release。CI 默认只发布 tarball，不直接发布 ext4 镜像，避免 GitHub Release 单文件大小限制和 CI 磁盘压力。

## Native 目标

Native 目标适合桌面环境、Mesa/Freedreno、KDE、输入法等图形栈测试。

当前支持：

- `Ubuntu-Rolling-LMI-Native`
- `Ubuntu-22-LMI-Native`
- `Ubuntu-24-LMI-Native`
- `Ubuntu-26-LMI-Native`
- `Debian-Testing-LMI-Native`
- `Debian-12-LMI-Native`
- `Debian-Sid-LMI-Native`
- `Debian-13-LMI-Native`
- `Arch-LMI-Native`
- `Fedora-42-LMI-Native`
- `Fedora-43-LMI-Native`
- `Fedora-44-LMI-Native`
- `Fedora-45-LMI-Native`
- `Fedora-Rawhide-LMI-Native`

部分目标复用同一个 Dockerfile，只通过 base image 切换发行版版本：

- Ubuntu 系复用 `Ubuntu-26-LMI-Native.Dockerfile`
- Debian 系复用 `Debian-13-LMI-Native.Dockerfile`
- Fedora 系复用 `Fedora-43-LMI-Native.Dockerfile`

## Server 目标

Server 目标适合 SSH、网络、包管理器、轻量 rootfs、服务端环境测试。

当前支持：

- `Ubuntu-Rolling-LMI-Server`
- `Ubuntu-22-LMI-Server`
- `Ubuntu-24-LMI-Server`
- `Ubuntu-26-LMI-Server`
- `Debian-Testing-LMI-Server`
- `Debian-12-LMI-Server`
- `Debian-Sid-LMI-Server`
- `Debian-13-LMI-Server`
- `Arch-LMI-Server`
- `Fedora-42-LMI-Server`
- `Fedora-43-LMI-Server`
- `Fedora-44-LMI-Server`
- `Fedora-45-LMI-Server`
- `Fedora-Rawhide-LMI-Server`
- `AlmaLinux-9-LMI-Server`
- `AlmaLinux-10-LMI-Server`
- `RockyLinux-9-LMI-Server`
- `RockyLinux-10-LMI-Server`
- `Alpine-3.20-LMI-Server`
- `Alpine-3.22-LMI-Server`
- `OpenSUSE-Leap-15.6-LMI-Server`
- `OpenSUSE-Leap-16.0-LMI-Server`
- `OpenSUSE-Tumbleweed-LMI-Server`
- `Mint-22-LMI-Server`

说明：

- `Alpine` 使用 OpenRC。
- `openSUSE`、`AlmaLinux`、`RockyLinux` 使用 systemd 相关服务配置。
- `Mint-22-LMI-Server` 是 Ubuntu 24.04 兼容目标。Linux Mint 没有稳定适合该 workflow 的官方 arm64 Docker 基础镜像，所以这里不是完整 Mint 用户态。

## 常用构建参数

GitHub Actions 页面可以配置：

- `build_target`
  要构建的发行版目标，或选择 `all`。

- `custom_username`
  默认用户。当前常用值：`xmzd`。

- `password`
  root 和默认用户密码。当前常用值：`1`。

- `build_kde`
  仅 Native workflow 有效：
  - `conc`：较完整 KDE 桌面
  - `min`：最小 KDE 桌面
  - `false`：不安装 KDE

- `enable_zh_tz`
  启用中文 locale 和 `Asia/Shanghai` 时区。

- `enable_srf`
  仅 Native workflow 有效，安装 Fcitx5 输入法。

- `enable_kfgj`
  安装开发工具链。

- `enable_zip`
  安装压缩/解压工具。

- `enable_docker`
  在 rootfs 内安装 Docker 相关包。注意手机内核是否支持 Docker 需要另行验证。

- `enable_tmoe`
  安装 tmoe helper。

- `allow_root_ssh`
  允许使用 root 账号通过 SSH 密码登录。默认关闭。

- `base_image`
  可选 base image 覆盖项。例如 Docker Hub 限流时可填镜像代理，或手动指定测试镜像。

## 本地构建

本地构建主要用于调试。推荐在 WSL Ubuntu 或 Linux 环境中运行，并准备 Docker buildx。

```bash
chmod +x build_rootfs-lmi-native.sh scripts/lmi-make-ext4-image.sh scripts/lmi-native-firstboot.sh

# Ubuntu 26 Native
./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -v lmi

# Ubuntu 24 Native，复用 Ubuntu 26 Dockerfile
./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -B ubuntu:24.04 -v lmi

# Debian 13 Native
./build_rootfs-lmi-native.sh -i Debian-13-LMI-Native.Dockerfile -v lmi

# Fedora 45 Native，复用 Fedora 43 Dockerfile
./build_rootfs-lmi-native.sh -i Fedora-43-LMI-Native.Dockerfile -B fedora:45 -v lmi

# Alpine Server
./build_rootfs-lmi-native.sh -i Alpine-LMI-Server.Dockerfile -B alpine:3.22 -K false -h false -v lmi

# openSUSE Tumbleweed Server
./build_rootfs-lmi-native.sh -i OpenSUSE-LMI-Server.Dockerfile -K false -h false -v lmi

# AlmaLinux 10 Server
./build_rootfs-lmi-native.sh -i EL-LMI-Server.Dockerfile -B almalinux:10 -K false -h false -v lmi

# 允许 root 通过 SSH 密码登录
./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -r true -v lmi
```

输出 tarball 格式：

```text
<target>-rootfs-arm64-<date>-<version>.tar.xz
```

## 生成 ext4 / sparse userdata 镜像

GitHub Actions 产物是 tarball。刷入手机前需要在本地转换成 ext4 镜像，通常再转换成 Android sparse 镜像。

在 WSL/Linux 中：

```bash
sudo apt-get update
sudo apt-get install -y e2fsprogs android-sdk-libsparse-utils rsync
sudo scripts/lmi-make-ext4-image.sh <rootfs>.tar.xz <rootfs>.ext4.img 16G
```

如果安装了 `img2simg`，脚本会同时生成：

```text
<rootfs>.ext4.sparse.img
```

KDE 桌面镜像建议使用 `16G` 或更大。Server 镜像可以更小，但如果后续要大量安装软件，也建议预留空间。

本地构建时也可以直接让脚本生成 ext4：

```bash
./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -v lmi -s 16G
```

## 刷入方式

确认你已经有可启动该 rootfs 布局的 lmi boot/kernel 后，再刷入 userdata。

```bash
fastboot flash userdata <rootfs>.ext4.sparse.img
fastboot reboot
```

注意：

- rootfs builder 不负责构建 boot.img。
- rootfs builder 不替换内核、dtb/dtbo、内核模块或 bootloader 配置。
- 如果 boot/kernel 与 rootfs 预期不一致，可能表现为无法进系统、无 SSH、无显示或设备驱动缺失。

## 固件覆盖

把设备固件放到 `firmware/lmi/`，路径按 `/lib/firmware` 的相对路径组织。

示例：

```text
firmware/lmi/qcom/sm8250/xiaomi/lmi/venus.mbn
firmware/lmi/qcom/sm8250/adsp.mbn
```

构建时会把 `firmware/lmi/` 下的内容复制到 rootfs 的 `/lib/firmware/`。`.zst` 固件会在镜像内尝试解压。

## 默认运行时配置

构建出的 rootfs 会尽量启用这些服务：

- SSH：`ssh.service` 或 `sshd.service`
- 网络：`NetworkManager.service`
- DNS：`systemd-resolved.service`，发行版支持时启用
- 时间同步：`systemd-timesyncd.service` 或发行版对应服务
- 桌面：Native KDE 目标启用 `sddm.service`

默认用户会加入常见设备访问组，例如：

```text
input video render audio plugdev netdev wheel sudo
```

不同发行版的组名不完全一致，Dockerfile 会按发行版能力尽量创建或加入。

默认 SSH 配置允许普通用户密码登录，但不允许 root 通过 SSH 登录：

```text
PermitRootLogin no
PasswordAuthentication yes
```

如果在 GitHub Actions 中开启 `allow_root_ssh`，或本地构建时传入 `-r true`，会改为：

```text
PermitRootLogin yes
PasswordAuthentication yes
```

## 已知限制

- Native KDE 桌面是否稳定，主要取决于当前 boot/kernel、GPU/DRM、触控、Wi-Fi、音频等设备适配状态。
- Server 目标更容易构建成功，但不代表所有手机硬件能力都已经可用。
- Fedora Rawhide、Debian Sid、Ubuntu Rolling 属于滚动/开发分支，适合测试新包，不建议作为长期稳定 rootfs。
- Alpine、AlmaLinux、RockyLinux 更适合 server/headless，不建议作为 lmi 桌面主线。
- `Mint-22-LMI-Server` 是 Ubuntu 24.04 兼容构建，不是完整 Linux Mint ARM64 官方 rootfs。

## 相关文件

- `build_rootfs-lmi-native.sh`
  通用 rootfs 构建脚本。

- `scripts/lmi-make-ext4-image.sh`
  tarball 转 ext4/sparse userdata 镜像脚本。

- `scripts/lmi-native-firstboot.sh`
  首次启动服务脚本。

- `.github/workflows/build-lmi-native-rootfs.yml`
  Native rootfs GitHub Actions workflow。

- `.github/workflows/build-lmi-server-rootfs.yml`
  Server rootfs GitHub Actions workflow。
