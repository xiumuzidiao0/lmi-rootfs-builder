# check=skip=SecretsUsedInArgOrEnv
ARG BASE_IMAGE=opensuse/tumbleweed:latest
FROM ${BASE_IMAGE} AS customizer

ARG ENABLE_zh_tz_ARG=true
ARG ENABLE_kfgj_ARG=false
ARG ENABLE_zip_ARG=true
ARG ENABLE_docker_ARG=false
ARG ENABLE_tmoe_ARG=false
ARG ALLOW_ROOT_SSH_ARG=false
ARG USERNAME=xmzd
ARG PASSWORD=1

COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh
COPY scripts/lmi-native-firstboot.sh /usr/local/sbin/lmi-native-firstboot
COPY scripts/lmi-native-firstboot.service /etc/systemd/system/lmi-native-firstboot.service
COPY firmware/lmi/ /tmp/lmi-firmware/

RUN chmod +x /usr/local/sbin/lmi-native-firstboot /etc/profile.d/ds-aliases.sh && \
    zypper --non-interactive refresh && \
    zypper --non-interactive update && \
    zypper --non-interactive install --no-recommends \
      bash bash-completion ca-certificates coreutils curl dbus-1 dialog \
      e2fsprogs file findutils gawk git grep jq kmod nano openssh procps sed sudo systemd timezone \
      wget xz zstd \
      iproute2 iptables iputils net-tools NetworkManager wpa_supplicant iw bind-utils rfkill wireless-regdb && \
    if zypper --non-interactive search --match-exact fastfetch | grep -q '^i\\? | fastfetch '; then zypper --non-interactive install --no-recommends fastfetch; fi && \
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then zypper --non-interactive install --no-recommends gcc gcc-c++ make cmake clang llvm python3 python3-pip python3-devel; fi && \
    if [ "$ENABLE_zip_ARG" = "true" ]; then zypper --non-interactive install --no-recommends zip unzip p7zip bzip2 tar gzip; fi && \
    if [ "$ENABLE_docker_ARG" = "true" ]; then zypper --non-interactive install --no-recommends docker docker-compose; fi && \
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe; fi

RUN if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
      ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "LANG=zh_CN.UTF-8" > /etc/locale.conf && echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf; \
    else \
      echo "LANG=en_US.UTF-8" > /etc/locale.conf && echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf; \
    fi && \
    groupadd -f wheel && groupadd -f render && groupadd -f input && groupadd -f video && groupadd -f audio && groupadd -f netdev && \
    useradd -m -s /bin/bash -G wheel,audio,input,video,render,netdev "$USERNAME" && \
    echo "$USERNAME:$PASSWORD" | chpasswd && echo "root:$PASSWORD" | chpasswd && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-lmi-wheel && chmod 0440 /etc/sudoers.d/90-lmi-wheel && \
    mkdir -p /etc/ssh && ssh-keygen -A && \
    if [ ! -f /etc/ssh/sshd_config ] && [ -f /usr/etc/ssh/sshd_config ]; then cp /usr/etc/ssh/sshd_config /etc/ssh/sshd_config; fi && \
    touch /etc/ssh/sshd_config && \
    sed -i '/^#*PermitRootLogin /d; /^#*PasswordAuthentication /d' /etc/ssh/sshd_config && \
    if [ "$ALLOW_ROOT_SSH_ARG" = "true" ]; then \
      printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' >> /etc/ssh/sshd_config; \
    else \
      printf 'PermitRootLogin no\nPasswordAuthentication yes\n' >> /etc/ssh/sshd_config; \
    fi

RUN mkdir -p /lib/firmware && cp -a /tmp/lmi-firmware/. /lib/firmware/ 2>/dev/null || true && \
    find /lib/firmware -type f -name '*.zst' -exec zstd -df --rm {} + 2>/dev/null || true && \
    printf 'LMI_USER=%s\nLMI_AUTOLOGIN=false\n' "$USERNAME" > /etc/lmi-native.conf

RUN systemctl enable lmi-native-firstboot.service sshd.service NetworkManager.service systemd-resolved.service || true && \
    zypper clean --all && rm -rf /var/cache/zypp/* /tmp/*

FROM scratch AS export
COPY --from=customizer / /
