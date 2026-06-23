#!/usr/bin/env bash
set -euo pipefail

VERSION=${VERSION:-dev}
DATE=${DATE:-$(date +%Y%m%d)}
PLATFORM=${PLATFORM:-linux/arm64}
ARCH_NAME=${ARCH_NAME:-arm64}
BUILDER=${BUILDER:-lmi-native-builder}
BUILD_KDE=${BUILD_KDE:-conc}
ENABLE_zh_tz=${ENABLE_zh_tz:-true}
ENABLE_kfgj=${ENABLE_kfgj:-false}
ENABLE_zip=${ENABLE_zip:-true}
ENABLE_docker=${ENABLE_docker:-false}
ENABLE_srf=${ENABLE_srf:-true}
ENABLE_tmoe=${ENABLE_tmoe:-false}
ALLOW_ROOT_SSH=${ALLOW_ROOT_SSH:-false}
USERNAME=${USERNAME:-xmzd}
PASSWORD=${PASSWORD:-1}
BASE_IMAGE=${BASE_IMAGE:-}
MAKE_EXT4=false
IMAGE_SIZE=${IMAGE_SIZE:-12G}

usage() {
  cat <<'EOF'
Usage:
  ./build_rootfs-lmi-native.sh -i <LMI-Native.Dockerfile> [options]

Options:
  -i FILE     Dockerfile to build, for example Ubuntu-26-LMI-Native.Dockerfile
  -v VERSION  Version suffix for output name, default: dev
  -K MODE     KDE profile: false, min, conc. default: conc
  -g BOOL     Chinese locale/timezone support, default: true
  -d BOOL     Developer toolchain, default: false
  -e BOOL     Archive tools, default: true
  -f BOOL     Docker packages inside rootfs, default: false
  -h BOOL     Fcitx5 input method, default: true
  -j BOOL     tmoe helper, default: false
  -r BOOL     Allow root SSH password login, default: false
  -u USER     Default user, default: xmzd
  -p PASS     Password for root and user, default: 1
  -B IMAGE    Override base image, useful when Docker Hub is rate-limited
  -s SIZE     Also create ext4 image with this size, for example 12G
  -E          Also create ext4 image, using IMAGE_SIZE/default 12G

Environment:
  PLATFORM=linux/arm64       Docker build platform
  BUILDER=lmi-native-builder Buildx builder name
EOF
}

while getopts "i:v:K:g:d:e:f:h:j:r:u:p:B:s:E" opt; do
  case "$opt" in
    i) DOCKERFILE=$OPTARG ;;
    v) VERSION=$OPTARG ;;
    K) BUILD_KDE=$OPTARG ;;
    g) ENABLE_zh_tz=$OPTARG ;;
    d) ENABLE_kfgj=$OPTARG ;;
    e) ENABLE_zip=$OPTARG ;;
    f) ENABLE_docker=$OPTARG ;;
    h) ENABLE_srf=$OPTARG ;;
    j) ENABLE_tmoe=$OPTARG ;;
    r) ALLOW_ROOT_SSH=$OPTARG ;;
    u) USERNAME=$OPTARG ;;
    p) PASSWORD=$OPTARG ;;
    B) BASE_IMAGE=$OPTARG ;;
    s) IMAGE_SIZE=$OPTARG; MAKE_EXT4=true ;;
    E) MAKE_EXT4=true ;;
    *) usage; exit 1 ;;
  esac
done

if [ -z "${DOCKERFILE:-}" ]; then
  usage >&2
  exit 1
fi

if [ ! -f "$DOCKERFILE" ]; then
  echo "Dockerfile not found: $DOCKERFILE" >&2
  exit 1
fi

PREFIX=${OUTPUT_PREFIX:-$(basename "$DOCKERFILE" .Dockerfile)}
TEMP_TAR="custom-${PREFIX}-rootfs.tar"
FINAL_TAR="${PREFIX}-rootfs-${ARCH_NAME}-${DATE}-${VERSION}.tar.xz"
FINAL_IMG="${PREFIX}-rootfs-${ARCH_NAME}-${DATE}-${VERSION}.ext4.img"

echo "========================================================="
echo " LMI native rootfs build"
echo " Dockerfile : $DOCKERFILE"
echo " Platform   : $PLATFORM"
echo " KDE        : $BUILD_KDE"
echo " User       : $USERNAME"
[ -n "$BASE_IMAGE" ] && echo " Base image : $BASE_IMAGE"
echo " Output     : $FINAL_TAR"
echo "========================================================="

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER" --driver docker-container --use
else
  docker buildx use "$BUILDER"
fi

docker buildx inspect --bootstrap >/dev/null

rm -f "$TEMP_TAR" "$FINAL_TAR"

BUILD_ARGS=(
  --build-arg "BUILD_KDE=$BUILD_KDE"
  --build-arg "ENABLE_zh_tz_ARG=$ENABLE_zh_tz"
  --build-arg "ENABLE_kfgj_ARG=$ENABLE_kfgj"
  --build-arg "ENABLE_zip_ARG=$ENABLE_zip"
  --build-arg "ENABLE_docker_ARG=$ENABLE_docker"
  --build-arg "ENABLE_srf_ARG=$ENABLE_srf"
  --build-arg "ENABLE_tmoe_ARG=$ENABLE_tmoe"
  --build-arg "ALLOW_ROOT_SSH_ARG=$ALLOW_ROOT_SSH"
  --build-arg "USERNAME=$USERNAME"
  --build-arg "PASSWORD=$PASSWORD"
)

if [ -n "$BASE_IMAGE" ]; then
  BUILD_ARGS+=(--build-arg "BASE_IMAGE=$BASE_IMAGE")
fi

docker buildx build \
  --platform "$PLATFORM" \
  --target export \
  --output type=tar,dest="$TEMP_TAR" \
  "${BUILD_ARGS[@]}" \
  -f "$DOCKERFILE" \
  .

xz -T0 -9 -f "$TEMP_TAR"
mv "${TEMP_TAR}.xz" "$FINAL_TAR"

if [ "$MAKE_EXT4" = "true" ]; then
  sudo scripts/lmi-make-ext4-image.sh "$FINAL_TAR" "$FINAL_IMG" "$IMAGE_SIZE"
fi

echo "========================================================="
echo " Build complete: $FINAL_TAR"
if [ "$MAKE_EXT4" = "true" ]; then
  echo " Image output : $FINAL_IMG"
  echo " Sparse output: ${FINAL_IMG%.img}.sparse.img, if img2simg is installed"
fi
echo "========================================================="
