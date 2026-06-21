# check=skip=SecretsUsedInArgOrEnv
ARG BASE_IMAGE=ubuntu:26.04
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

ENV DEBIAN_FRONTEND=noninteractive

COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh
COPY scripts/lmi-native-firstboot.sh /usr/local/sbin/lmi-native-firstboot
COPY scripts/lmi-native-firstboot.service /etc/systemd/system/lmi-native-firstboot.service
COPY firmware/lmi/ /tmp/lmi-firmware/

RUN chmod +x /usr/local/sbin/lmi-native-firstboot /etc/profile.d/ds-aliases.sh && \
    (sed -i 's/Components: main/Components: main restricted universe multiverse/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true)

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      bash bash-completion ca-certificates coreutils curl dbus dbus-user-session dialog fastfetch \
      file findutils gawk git grep jq kmod locales nano openssh-server procps sed sudo systemd-resolved systemd-timesyncd \
      systemd-sysv tzdata udev wget xz-utils \
      e2fsprogs \
      iproute2 iptables iputils-ping net-tools network-manager wpasupplicant iw dnsutils rfkill wireless-regdb \
      usbutils usbmuxd libimobiledevice-utils \
      bluez bluetooth pulseaudio-utils pipewire pipewire-alsa pipewire-pulse wireplumber \
      linux-firmware zstd \
      fonts-noto-cjk fonts-noto-color-emoji mesa-utils mesa-vulkan-drivers vulkan-tools libgl1-mesa-dri && \
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ]; then \
      apt-get install -y --no-install-recommends \
        sddm kde-plasma-desktop plasma-session-x11 plasma-workspace powerdevil kscreen plasma-pa \
        polkit-kde-agent-1 kwin-x11 xserver-xorg dbus-x11 x11-xserver-utils \
        dolphin konsole kate kinfocenter ark systemsettings kde-config-screenlocker kio-extras \
        kubuntu-settings-desktop kubuntu-wallpapers upower; \
    fi && \
    if [ "$BUILD_KDE" = "conc" ]; then \
      apt-get install -y --no-install-recommends \
        plasma-systemmonitor kfind filelight glmark2 vkmark wayland-utils pciutils dmidecode \
        xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers kimageformat6-plugins \
        plasma-browser-integration gstreamer1.0-plugins-base gstreamer1.0-plugins-good libcanberra-pulse; \
    fi && \
    if [ "$ENABLE_srf_ARG" = "true" ]; then \
      apt-get install -y --no-install-recommends fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-qt5 fcitx5-frontend-qt6; \
    fi && \
    if [ "$ENABLE_srf_ARG" = "true" ] && [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
      apt-get install -y --no-install-recommends fcitx5-chinese-addons; \
    fi && \
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then \
      apt-get install -y --no-install-recommends build-essential clang cmake gcc g++ llvm make pkg-config python3 python3-dev python3-pip python3-venv; \
    fi && \
    if [ "$ENABLE_zip_ARG" = "true" ]; then \
      apt-get install -y --no-install-recommends bzip2 gzip p7zip-full tar unzip zip; \
    fi && \
    if [ "$ENABLE_docker_ARG" = "true" ]; then \
      apt-get install -y --no-install-recommends docker.io docker-compose-v2; \
    fi && \
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then \
      git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && \
      ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe && chmod -R 755 /usr/local/etc/tmoe-linux; \
    fi

RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
      ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone && \
      sed -i '/zh_CN.UTF-8/s/^# //' /etc/locale.gen && locale-gen && update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; \
    else \
      locale-gen && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    fi && \
    deluser --remove-home ubuntu 2>/dev/null || true && \
    useradd -m -s /bin/bash -G sudo,adm,audio,input,video,render,plugdev,users,netdev "$USERNAME" && \
    echo "$USERNAME:$PASSWORD" | chpasswd && echo "root:$PASSWORD" | chpasswd && \
    mkdir -p /etc/sudoers.d && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-lmi-user && chmod 0440 /etc/sudoers.d/90-lmi-user

RUN printf 'XCURSOR_SIZE=48\nQT_QPA_PLATFORMTHEME=qt5ct\n' > /etc/environment

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

RUN mkdir -p /etc/lmi-native /lib/firmware && \
    if [ -d /tmp/lmi-firmware ]; then cp -a /tmp/lmi-firmware/. /lib/firmware/; fi && \
    mkdir -p /lib/firmware/rtw88 && \
    if [ ! -e /lib/firmware/rtw88/rtw8821c_fw.bin ]; then \
      curl -fsSL -o /lib/firmware/rtw88/rtw8821c_fw.bin https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtw88/rtw8821c_fw.bin; \
    fi && \
    find /lib/firmware -type f -name '*.zst' -exec zstd -df --rm {} + 2>/dev/null || true && \
    cat > /etc/lmi-native.conf <<EOF
LMI_USER=$USERNAME
LMI_AUTOLOGIN=true
EOF

RUN systemctl enable lmi-native-firstboot.service ssh.service NetworkManager.service systemd-resolved.service systemd-timesyncd.service || true && \
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ]; then systemctl enable sddm.service || true; fi && \
    systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

FROM scratch AS export
COPY --from=customizer / /
