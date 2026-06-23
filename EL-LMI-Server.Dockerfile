# check=skip=SecretsUsedInArgOrEnv
ARG BASE_IMAGE=almalinux:10
FROM ${BASE_IMAGE} AS customizer

ARG ENABLE_zh_tz_ARG=true
ARG ENABLE_kfgj_ARG=false
ARG ENABLE_zip_ARG=true
ARG ENABLE_docker_ARG=false
ARG ENABLE_tmoe_ARG=false
ARG USERNAME=xmzd
ARG PASSWORD=1

COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh
COPY scripts/lmi-native-firstboot.sh /usr/local/sbin/lmi-native-firstboot
COPY scripts/lmi-native-firstboot.service /etc/systemd/system/lmi-native-firstboot.service
COPY firmware/lmi/ /tmp/lmi-firmware/

RUN chmod +x /usr/local/sbin/lmi-native-firstboot /etc/profile.d/ds-aliases.sh && \
    dnf -y update && \
    dnf install -y --setopt=install_weak_deps=False \
      bash bash-completion ca-certificates coreutils curl dbus-daemon e2fsprogs \
      file findutils gawk git grep gzip jq kmod nano openssh-server procps-ng sed sudo systemd \
      tzdata wget xz zstd \
      iproute iptables iputils net-tools NetworkManager wpa_supplicant iw bind-utils rfkill && \
    dnf install -y --setopt=install_weak_deps=False wireless-regdb || true && \
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then \
      dnf install -y --setopt=install_weak_deps=False gcc gcc-c++ make cmake clang llvm python3 python3-pip python3-devel; \
    fi && \
    if [ "$ENABLE_zip_ARG" = "true" ]; then \
      dnf install -y --setopt=install_weak_deps=False zip unzip bzip2 tar gzip; \
    fi && \
    if [ "$ENABLE_docker_ARG" = "true" ]; then \
      dnf install -y --setopt=install_weak_deps=False moby-engine docker-compose docker-cli || \
      dnf install -y --setopt=install_weak_deps=False docker; \
    fi && \
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then \
      git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && \
      ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe; \
    fi

RUN if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
      ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "LANG=zh_CN.UTF-8" > /etc/locale.conf && echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf; \
    else \
      echo "LANG=en_US.UTF-8" > /etc/locale.conf && echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf; \
    fi && \
    groupadd -f wheel && groupadd -f render && groupadd -f input && groupadd -f video && groupadd -f audio && groupadd -f netdev && \
    useradd -m -s /bin/bash -G wheel,audio,input,video,render,netdev "$USERNAME" && \
    echo "$USERNAME:$PASSWORD" | chpasswd && echo "root:$PASSWORD" | chpasswd && \
    mkdir -p /etc/sudoers.d && echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-lmi-wheel && chmod 0440 /etc/sudoers.d/90-lmi-wheel && \
    mkdir -p /etc/ssh && ssh-keygen -A && \
    touch /etc/ssh/sshd_config && \
    sed -i '/^#*PermitRootLogin /d; /^#*PasswordAuthentication /d' /etc/ssh/sshd_config && \
    printf 'PermitRootLogin no\nPasswordAuthentication yes\n' >> /etc/ssh/sshd_config

RUN mkdir -p /lib/firmware && cp -a /tmp/lmi-firmware/. /lib/firmware/ 2>/dev/null || true && \
    find /lib/firmware -type f -name '*.zst' -exec zstd -df --rm {} + 2>/dev/null || true && \
    printf 'LMI_USER=%s\nLMI_AUTOLOGIN=false\n' "$USERNAME" > /etc/lmi-native.conf

RUN systemctl enable lmi-native-firstboot.service sshd.service NetworkManager.service || true && \
    dnf clean all && rm -rf /var/cache/dnf/* /tmp/*

FROM scratch AS export
COPY --from=customizer / /
