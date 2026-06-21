#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <rootfs.tar.xz|rootfs.tar> <output.ext4.img> <size, e.g. 12G>" >&2
  exit 1
fi

ROOTFS_TAR=$1
OUT_IMG=$2
SIZE=$3
SPARSE_IMG="${OUT_IMG%.img}.sparse.img"
MNT=

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root because it mounts a loopback ext4 image." >&2
  exit 1
fi

cleanup() {
  if [ -n "${MNT:-}" ] && mountpoint -q "$MNT"; then
    umount "$MNT"
  fi
  [ -n "${MNT:-}" ] && rm -rf "$MNT"
}
trap cleanup EXIT

rm -f "$OUT_IMG" "$SPARSE_IMG"
truncate -s "$SIZE" "$OUT_IMG"
mkfs.ext4 -F -L userdata "$OUT_IMG"

MNT=$(mktemp -d)
mount -o loop "$OUT_IMG" "$MNT"

case "$ROOTFS_TAR" in
  *.tar.xz) tar -xJpf "$ROOTFS_TAR" -C "$MNT" ;;
  *.tar) tar -xpf "$ROOTFS_TAR" -C "$MNT" ;;
  *) echo "Unsupported rootfs archive: $ROOTFS_TAR" >&2; exit 1 ;;
esac

sync
umount "$MNT"

e2fsck -fy "$OUT_IMG" >/dev/null
resize2fs -M "$OUT_IMG" >/dev/null || true

if command -v img2simg >/dev/null 2>&1; then
  img2simg "$OUT_IMG" "$SPARSE_IMG"
  echo "Created $OUT_IMG and $SPARSE_IMG"
else
  echo "Created $OUT_IMG"
  echo "img2simg not found; sparse image was not created"
fi
