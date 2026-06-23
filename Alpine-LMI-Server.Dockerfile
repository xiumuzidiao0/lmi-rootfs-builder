# check=skip=SecretsUsedInArgOrEnv
ARG BASE_IMAGE=alpine:3.22
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
COPY firmware/lmi/ /tmp/lmi-firmware/

RUN chmod +x /usr/local/sbin/lmi-native-firstboot /etc/profile.d/ds-aliases.sh && \
    apk update && \
    apk add --no-cache \
      alpine-base bash bash-completion ca-certificates coreutils curl dbus dialog \
      e2fsprogs file findutils gawk git grep jq kmod nano openssh openrc procps-ng sed sudo \
      tzdata wget xz zstd \
      iproute2 iptables iputils networkmanager wpa_supplicant iw bind-tools && \
    if apk info -e fastfetch >/dev/null 2>&1 || apk search -q '^fastfetch$' | grep -qx fastfetch; then apk add --no-cache fastfetch; fi && \
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then apk add --no-cache build-base clang cmake llvm make pkgconf python3 py3-pip; fi && \
    if [ "$ENABLE_zip_ARG" = "true" ]; then apk add --no-cache bzip2 gzip p7zip tar unzip zip; fi && \
    if [ "$ENABLE_docker_ARG" = "true" ]; then apk add --no-cache docker docker-cli-compose; fi && \
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe; fi

RUN if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
      cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone && \
      echo "LANG=zh_CN.UTF-8" > /etc/profile.d/locale.sh; \
    else \
      echo "LANG=en_US.UTF-8" > /etc/profile.d/locale.sh; \
    fi && \
    addgroup -S "$USERNAME" 2>/dev/null || true && \
    adduser -D -s /bin/bash -G "$USERNAME" "$USERNAME" && \
    for group in wheel audio input video render netdev plugdev users; do addgroup "$group" 2>/dev/null || true; addgroup "$USERNAME" "$group" 2>/dev/null || true; done && \
    echo "$USERNAME:$PASSWORD" | chpasswd && echo "root:$PASSWORD" | chpasswd && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-lmi-wheel && chmod 0440 /etc/sudoers.d/90-lmi-wheel && \
    ssh-keygen -A && \
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config

RUN mkdir -p /lib/firmware && cp -a /tmp/lmi-firmware/. /lib/firmware/ 2>/dev/null || true && \
    find /lib/firmware -type f -name '*.zst' -exec zstd -df --rm {} + 2>/dev/null || true && \
    printf 'LMI_USER=%s\nLMI_AUTOLOGIN=false\n' "$USERNAME" > /etc/lmi-native.conf

RUN rc-update add dbus default 2>/dev/null || true && \
    rc-update add sshd default 2>/dev/null || true && \
    rc-update add networkmanager default 2>/dev/null || true && \
    rm -rf /var/cache/apk/* /tmp/*

FROM scratch AS export
COPY --from=customizer / /
