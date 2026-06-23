# LMI Native Rootfs

These targets build native arm64 rootfs images for the Xiaomi lmi mainline Linux boot flow. They are separate from the original Droidspaces/LXC targets.

Native targets:

- `Ubuntu-26-LMI-Native.Dockerfile`
- `Debian-13-LMI-Native.Dockerfile`
- `Arch-LMI-Native.Dockerfile`
- `Fedora-43-LMI-Native.Dockerfile`

The native targets keep distribution Mesa/Freedreno packages for the Snapdragon GPU path. They intentionally do not install `mesa-for-android-container`, Termux-X11, Droidspaces services, Android audio forwarding, anland, or Android container groups.

NetworkManager is installed with `wpa_supplicant` and `iw` so PCIe/USB Wi-Fi devices can be managed normally. USB phone tethering is supported through NetworkManager plus `usbmuxd`/`libimobiledevice` for iPhone-style tethering. Ubuntu and Debian native images also stage the Realtek `rtw88/rtw8821c_fw.bin` firmware used by common RTL8821CU USB Wi-Fi adapters.

The native first-boot service grows an ext4 root filesystem to fill the flashed userdata partition when `resize2fs` is available. The images include ext4 tools and a time synchronization service so package manager signature checks do not fail because the device clock starts too far in the past.

## Build

Use the GitHub Actions workflow `Build LMI Native RootFS` for normal builds. It builds one target or all native targets and publishes rootfs tarballs.

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
./build_rootfs-lmi-native.sh -i Arch-LMI-Native.Dockerfile -B menci/archlinuxarm:base

# local-only: also create an ext4 image
./build_rootfs-lmi-native.sh -i Ubuntu-26-LMI-Native.Dockerfile -v lmi -s 12G
```

The output tarball name is:

```text
<target>-rootfs-arm64-<date>-<version>.tar.xz
```

GitHub Actions publishes only the tarball. This keeps CI reliable and avoids GitHub Release's 2 GiB per-asset limit.

If `-s` or `-E` is used in a local build, the helper also creates:

```text
<target>-rootfs-arm64-<date>-<version>.ext4.img
<target>-rootfs-arm64-<date>-<version>.ext4.sparse.img
```

The sparse image is only produced when `img2simg` is installed.

## Local Image Conversion

Convert the release tarball to a userdata image locally in WSL or Linux:

```bash
sudo apt-get update
sudo apt-get install -y e2fsprogs android-sdk-libsparse-utils rsync
sudo scripts/lmi-make-ext4-image.sh <target>.tar.xz <target>.ext4.img 16G
```

From Windows CMD or PowerShell, you can call the WSL wrapper:

```bat
.\scripts\lmi-convert-rootfs-local.cmd -RootfsTar .\<target>.tar.xz -Size 16G
```

Or call the PowerShell script explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\lmi-convert-rootfs-local.ps1 -RootfsTar .\<target>.tar.xz -Size 16G
```

The script automatically grows the requested ext4 size if the unpacked rootfs needs more space, then creates:

```text
<target>.ext4.img
<target>.ext4.sparse.img
```

Use `16G` or larger for KDE desktop images. The sparse image is the one normally flashed with fastboot.

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

After local conversion:

```bash
fastboot flash userdata <target>.ext4.sparse.img
fastboot reboot
```

Use a boot image known to work with the same rootfs layout. The rootfs builder does not replace boot image, device tree, kernel modules, or bootloader configuration.
