# LMI Native Rootfs

These targets build native arm64 rootfs images for the Xiaomi lmi mainline Linux boot flow. They are separate from the original Droidspaces/LXC targets.

Native targets:

- `Ubuntu-26-LMI-Native.Dockerfile`
- `Debian-13-LMI-Native.Dockerfile`
- `Arch-LMI-Native.Dockerfile`
- `Fedora-43-LMI-Native.Dockerfile`

The native targets keep distribution Mesa/Freedreno packages for the Snapdragon GPU path. They intentionally do not install `mesa-for-android-container`, Termux-X11, Droidspaces services, Android audio forwarding, anland, or Android container groups.

## Build

Use the GitHub Actions workflow `Build LMI Native RootFS` for normal builds. It can build one target or all native targets and publish a release artifact.

Local builds are mainly for debugging. Run from this directory in WSL or Linux with Docker buildx available:

```bash
chmod +x build_rootfs-lmi-native.sh scripts/lmi-make-ext4-image.sh scripts/lmi-native-firstboot.sh

./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -v lmi
./build_rootfs-lmi-native.sh -i Debian-13-LMI-Native.Dockerfile -v lmi
./build_rootfs-lmi-native.sh -i Arch-LMI-Native.Dockerfile -v lmi
./build_rootfs-lmi-native.sh -i Fedora-43-LMI-Native.Dockerfile -v lmi
```

The workflow runs on `ubuntu-24.04-arm`, so the images are built natively for arm64. It does not need QEMU/binfmt for the normal GitHub build path.

Useful options:

```bash
# KDE profile: false, min, conc
./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -K conc

# username/password
./build_rootfs-lmi-native.sh -i Debian-13-LMI-Native.Dockerfile -u xmzd -p 1

# override base image when Docker Hub is rate-limited
./build_rootfs-lmi-native.sh -i Arch-LMI-Native.Dockerfile -B mirror.gcr.io/library/archlinux:base

# also create an ext4 image
./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -v lmi -s 12G
```

The output tarball name is:

```text
<target>-rootfs-arm64-<date>-<version>.tar.xz
```

If `-s` or `-E` is used, the helper also creates:

```text
<target>-rootfs-arm64-<date>-<version>.ext4.img
<target>-rootfs-arm64-<date>-<version>.ext4.sparse.img
```

The sparse image is only produced when `img2simg` is installed.

## Firmware Overlay

Put device firmware under `firmware/lmi/` using paths relative to `/lib/firmware`.

Example:

```text
firmware/lmi/qcom/sm8250/xiaomi/lmi/venus.mbn
firmware/lmi/qcom/sm8250/adsp.mbn
```

Everything under `firmware/lmi/` is copied into `/lib/firmware/` during the build. Compressed `.zst` firmware files are decompressed in the image.

## Runtime Defaults

The first boot service enables common native services when they exist:

- SSH: `ssh.service` or `sshd.service`
- networking: `NetworkManager.service`
- DNS: `systemd-resolved.service`
- desktop: `sddm.service`

It also adds the configured user to device access groups such as `input`, `video`, `render`, `audio`, `plugdev`, `netdev`, and `wheel` when those groups exist.

The generated rootfs does not apply DPMS or panel suspend workarounds. Display sleep behavior should stay opt-in or be handled in the kernel/device tree path.

## Flashing

For a direct userdata image:

```bash
fastboot flash userdata <target>.ext4.sparse.img
fastboot reboot
```

If you only built the tarball, create and populate an ext4 filesystem yourself or run:

```bash
sudo scripts/lmi-make-ext4-image.sh <target>.tar.xz <target>.ext4.img 12G
```

Use a boot image known to work with the same rootfs layout. The rootfs builder does not replace boot image, device tree, kernel modules, or bootloader configuration.
