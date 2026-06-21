# check=skip=SecretsUsedInArgOrEnv
ARG BASE_IMAGE=archlinux:base
FROM ${BASE_IMAGE} AS customizer

ARG BUILD_KDE=conc
ARG ENABLE_zh_tz_ARG=true
ARG ENABLE_kfgj_ARG=false
ARG ENABLE_zip_ARG=true
ARG ENABLE_docker_ARG=false
ARG ENABLE_srf_ARG=true
ARG ENABLE_tmoe_ARG=false
ARG USERNAME=xmzd
ARG PASSWORD=1

COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh
COPY scripts/lmi-native-firstboot.sh /usr/local/sbin/lmi-native-firstboot
COPY scripts/lmi-native-firstboot.service /etc/systemd/system/lmi-native-firstboot.service
COPY firmware/lmi/ /tmp/lmi-firmware/

RUN chmod +x /usr/local/sbin/lmi-native-firstboot /etc/profile.d/ds-aliases.sh && \
    sed -i '/^#ParallelDownloads/s/^#//' /etc/pacman.conf && \
    pacman -Sy --noconfirm archlinux-keyring && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
      bash bash-completion ca-certificates coreutils curl dbus dialog fastfetch \
      file findutils gawk git grep jq kmod nano openssh procps-ng sed sudo systemd e2fsprogs \
      tzdata wget xz zstd \
      iproute2 iptables iputils net-tools networkmanager wpa_supplicant iw bind rfkill wireless-regdb \
      usbutils usbmuxd libimobiledevice \
      bluez pipewire pipewire-alsa pipewire-pulse wireplumber pulseaudio \
      linux-firmware noto-fonts-cjk noto-fonts-emoji mesa mesa-utils vulkan-tools vulkan-freedreno && \
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ]; then \
      pacman -S --noconfirm --needed \
        sddm plasma-desktop plasma-workspace plasma-x11-session bluedevil plasma-nm kwin kwin-x11 powerdevil kscreen plasma-pa \
        polkit-kde-agent xorg-server xorg-xrandr xorg-xset xorg-xrdb xorg-xhost \
        dolphin konsole kate kinfocenter ark systemsettings kscreenlocker kio-extras upower; \
    fi && \
    if [ "$BUILD_KDE" = "conc" ]; then \
      pacman -S --noconfirm --needed \
        plasma-systemmonitor kfind filelight glmark2 vkmark wayland-utils pciutils dmidecode \
        xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers kimageformats \
        plasma-browser-integration gst-plugins-base gst-plugins-good libcanberra sound-theme-freedesktop; \
    fi && \
    if [ "$ENABLE_srf_ARG" = "true" ]; then pacman -S --noconfirm --needed fcitx5-im; fi && \
    if [ "$ENABLE_srf_ARG" = "true" ] && [ "$ENABLE_zh_tz_ARG" = "true" ]; then pacman -S --noconfirm --needed fcitx5-chinese-addons; fi && \
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then pacman -S --noconfirm --needed base-devel cmake clang llvm python python-pip; fi && \
    if [ "$ENABLE_zip_ARG" = "true" ]; then pacman -S --noconfirm --needed zip unzip p7zip bzip2 tar gzip; fi && \
    if [ "$ENABLE_docker_ARG" = "true" ]; then pacman -S --noconfirm --needed docker docker-compose; fi && \
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe; fi

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
      ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen && \
      locale-gen && echo "LANG=zh_CN.UTF-8" > /etc/locale.conf && echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf; \
    else locale-gen && echo "LANG=en_US.UTF-8" > /etc/locale.conf && echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf; fi && \
    useradd -m -s /bin/bash -G wheel,audio,input,video,render "$USERNAME" && \
    echo "$USERNAME:$PASSWORD" | chpasswd && echo "root:$PASSWORD" | chpasswd && \
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers && \
    ssh-keygen -A && \
    sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

RUN cat > /etc/environment <<'EOF'
XCURSOR_SIZE=48
EOF

RUN if [ "$ENABLE_srf_ARG" = "true" ]; then \
      mkdir -p "/home/$USERNAME/.config/autostart" && \
      printf '[Desktop Entry]\nName=Fcitx5\nExec=fcitx5 -d\nType=Application\nNoDisplay=true\n' > "/home/$USERNAME/.config/autostart/fcitx5.desktop" && \
      printf 'XMODIFIERS=@im=fcitx5\nGTK_IM_MODULE=fcitx5\nQT_IM_MODULE=fcitx5\n' >> /etc/environment; \
    fi && \
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ]; then \
      mkdir -p "/home/$USERNAME/.config" /etc/sddm.conf.d && \
      printf '[Compositing]\nEnabled=false\n' > "/home/$USERNAME/.config/kwinrc" && \
      printf '[Autologin]\nUser=%s\nSession=plasma\nRelogin=false\n' "$USERNAME" > /etc/sddm.conf.d/10-lmi-autologin.conf; \
    fi && \
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

RUN mkdir -p /lib/firmware && cp -a /tmp/lmi-firmware/. /lib/firmware/ 2>/dev/null || true && \
    find /lib/firmware -type f -name '*.zst' -exec zstd -df --rm {} + 2>/dev/null || true && \
    printf 'LMI_USER=%s\nLMI_AUTOLOGIN=true\n' "$USERNAME" > /etc/lmi-native.conf

RUN systemctl enable lmi-native-firstboot.service sshd.service NetworkManager.service systemd-resolved.service systemd-timesyncd.service || true && \
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ]; then systemctl enable sddm.service || true; fi && \
    rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* /tmp/*

FROM scratch AS export
COPY --from=customizer / /
