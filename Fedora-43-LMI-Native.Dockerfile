# check=skip=SecretsUsedInArgOrEnv
ARG BASE_IMAGE=fedora:43
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

RUN chmod +x /usr/local/sbin/lmi-native-firstboot /etc/profile.d/ds-aliases.sh

RUN dnf install -y --setopt=install_weak_deps=False \
      bash bash-completion ca-certificates coreutils curl dbus-daemon dialog fastfetch \
      file findutils gawk git grep jq kmod nano openssh-server procps-ng sed sudo systemd \
      systemd-resolved systemd-udev tzdata wget xz zstd \
      iproute iptables iputils net-tools NetworkManager wpa_supplicant iw bind-utils rfkill wireless-regdb \
      usbutils usbmuxd libimobiledevice-utils \
      bluez pipewire pipewire-alsa pipewire-pulseaudio wireplumber pulseaudio-utils \
      linux-firmware google-noto-cjk-fonts google-noto-emoji-color-fonts \
      mesa-dri-drivers mesa-vulkan-drivers glx-utils vulkan-tools && \
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ]; then \
      dnf install -y --setopt=install_weak_deps=False \
        sddm plasma-desktop plasma-workspace plasma-workspace-x11 kwin kwin-x11 powerdevil kscreen plasma-pa \
        polkit-kde dbus-x11 xorg-x11-server-Xorg xrandr xset xrdb xhost \
        dolphin konsole kate kinfocenter ark systemsettings kscreenlocker kio-extras upower; \
    fi && \
    if [ "$BUILD_KDE" = "conc" ]; then \
      dnf install -y --setopt=install_weak_deps=False \
        plasma-systemmonitor kfind filelight glmark2 vkmark wayland-utils pciutils dmidecode \
        xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers kf6-kimageformats \
        plasma-browser-integration gstreamer1-plugins-base gstreamer1-plugins-good libcanberra-gtk3 sound-theme-freedesktop; \
    fi && \
    if [ "$ENABLE_srf_ARG" = "true" ]; then dnf install -y --setopt=install_weak_deps=False fcitx5 fcitx5-gtk fcitx5-qt; fi && \
    if [ "$ENABLE_srf_ARG" = "true" ] && [ "$ENABLE_zh_tz_ARG" = "true" ]; then dnf install -y --setopt=install_weak_deps=False fcitx5-chinese-addons; fi && \
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then dnf install -y --setopt=install_weak_deps=False gcc gcc-c++ make cmake autoconf automake libtool pkgconf clang llvm python3 python3-pip python3-devel; fi && \
    if [ "$ENABLE_zip_ARG" = "true" ]; then dnf install -y --setopt=install_weak_deps=False zip unzip p7zip p7zip-plugins bzip2 tar gzip; fi && \
    if [ "$ENABLE_docker_ARG" = "true" ]; then dnf install -y --setopt=install_weak_deps=False moby-engine docker-compose docker-cli; fi && \
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe; fi

RUN if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
      ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "LANG=zh_CN.UTF-8" > /etc/locale.conf && echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf; \
    else echo "LANG=en_US.UTF-8" > /etc/locale.conf && echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf; fi && \
    useradd -m -s /bin/bash -G wheel,audio,input,video,render "$USERNAME" && \
    echo "$USERNAME:$PASSWORD" | chpasswd && echo "root:$PASSWORD" | chpasswd && \
    sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers && \
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

RUN systemctl enable lmi-native-firstboot.service sshd.service NetworkManager.service systemd-resolved.service || true && \
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ]; then systemctl enable sddm.service || true; fi && \
    dnf clean all && rm -rf /var/cache/dnf/* /tmp/*

FROM scratch AS export
COPY --from=customizer / /
