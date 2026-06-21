#!/usr/bin/env bash
set -euo pipefail

MARKER=/var/lib/lmi-native-firstboot.done
[ -e "$MARKER" ] && exit 0

if [ -r /etc/lmi-native.conf ]; then
  # shellcheck disable=SC1091
  . /etc/lmi-native.conf
fi

USER_NAME="${LMI_USER:-xmzd}"

log() {
  printf '[lmi-native-firstboot] %s\n' "$*"
}

add_user_to_existing_groups() {
  local user=$1
  shift

  id "$user" >/dev/null 2>&1 || return 0

  for group in "$@"; do
    if getent group "$group" >/dev/null 2>&1; then
      usermod -aG "$group" "$user" || true
    fi
  done
}

enable_if_exists() {
  local unit=$1

  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    systemctl enable "$unit" >/dev/null 2>&1 || true
  fi
}

disable_if_exists() {
  local unit=$1

  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    systemctl disable "$unit" >/dev/null 2>&1 || true
  fi
}

mask_if_exists() {
  local unit=$1

  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    systemctl mask "$unit" >/dev/null 2>&1 || true
  fi
}

grow_rootfs_if_possible() {
  local source fstype

  source=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  fstype=$(findmnt -n -o FSTYPE / 2>/dev/null || true)

  if [ -z "$source" ] || [ -z "$fstype" ]; then
    return 0
  fi

  case "$fstype" in
    ext2|ext3|ext4)
      if command -v resize2fs >/dev/null 2>&1; then
        log "growing root filesystem on $source"
        resize2fs "$source" >/dev/null 2>&1 || true
      else
        log "resize2fs not available; root filesystem was not grown"
      fi
      ;;
  esac
}

log "configuring native boot defaults"

hostnamectl set-hostname lmi-native >/dev/null 2>&1 || true
grow_rootfs_if_possible

mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-lmi-native.conf <<'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-lmi-native.conf <<'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
EOF

add_user_to_existing_groups "$USER_NAME" \
  adm audio input plugdev render sudo users video wheel netdev lpadmin cdrom dip

add_user_to_existing_groups root audio input render video

enable_if_exists ssh.service
enable_if_exists sshd.service
enable_if_exists NetworkManager.service
enable_if_exists systemd-resolved.service
enable_if_exists systemd-timesyncd.service
enable_if_exists chronyd.service
enable_if_exists usbmuxd.service
enable_if_exists sddm.service

disable_if_exists systemd-networkd-wait-online.service
mask_if_exists systemd-networkd-wait-online.service
disable_if_exists cloud-init.service
disable_if_exists cloud-config.service
disable_if_exists cloud-final.service
disable_if_exists snapd.service

if [ -d /etc/sddm.conf.d ] && [ -n "$USER_NAME" ] && [ "${LMI_AUTOLOGIN:-true}" = "true" ]; then
  cat > /etc/sddm.conf.d/10-lmi-autologin.conf <<EOF
[Autologin]
User=$USER_NAME
Session=plasma
Relogin=false
EOF
fi

mkdir -p /var/lib
date -Iseconds > "$MARKER"
log "done"
