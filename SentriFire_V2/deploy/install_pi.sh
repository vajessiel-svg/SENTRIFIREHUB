#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer with sudo."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="/opt/sentrifire"
MEDIAMTX_VERSION="${MEDIAMTX_VERSION:-1.20.1}"

apt-get update
apt-get install -y python3 python3-venv python3-pip ffmpeg curl ca-certificates

if ! id sentrifire >/dev/null 2>&1; then
  useradd --system --home-dir "${TARGET_DIR}" --shell /usr/sbin/nologin sentrifire
fi
for optional_group in gpio video; do
  if getent group "${optional_group}" >/dev/null; then
    usermod -a -G "${optional_group}" sentrifire
  fi
done

install -d -m 0755 "${TARGET_DIR}" "${TARGET_DIR}/backend" "${TARGET_DIR}/deploy" "${TARGET_DIR}/mediamtx"
cp -a "${PROJECT_DIR}/backend/." "${TARGET_DIR}/backend/"
cp -a "${PROJECT_DIR}/deploy/." "${TARGET_DIR}/deploy/"
install -d -o sentrifire -g sentrifire -m 0750 \
  "${TARGET_DIR}/backend/data" \
  "${TARGET_DIR}/backend/data/snapshots" \
  "${TARGET_DIR}/backend/data/ultralytics"

if [[ ! -f "${TARGET_DIR}/backend/.env" ]]; then
  install -o sentrifire -g sentrifire -m 0600 "${TARGET_DIR}/backend/.env.example" "${TARGET_DIR}/backend/.env"
fi
if [[ ! -f "${TARGET_DIR}/mediamtx/mediamtx.yml" ]]; then
  install -o sentrifire -g sentrifire -m 0600 "${TARGET_DIR}/deploy/mediamtx.yml.example" "${TARGET_DIR}/mediamtx/mediamtx.yml"
fi

python3 -m venv "${TARGET_DIR}/backend/.venv"
"${TARGET_DIR}/backend/.venv/bin/python" -m pip install --upgrade pip wheel
"${TARGET_DIR}/backend/.venv/bin/python" -m pip install -r "${TARGET_DIR}/backend/requirements.txt"

case "$(uname -m)" in
  aarch64|arm64) MEDIAMTX_ARCH="linux_arm64v8" ;;
  armv7l) MEDIAMTX_ARCH="linux_armv7" ;;
  x86_64) MEDIAMTX_ARCH="linux_amd64" ;;
  *) echo "Unsupported MediaMTX architecture: $(uname -m)"; exit 1 ;;
esac

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT
ARCHIVE="mediamtx_v${MEDIAMTX_VERSION}_${MEDIAMTX_ARCH}.tar.gz"
RELEASE_URL="https://github.com/bluenviron/mediamtx/releases/download/v${MEDIAMTX_VERSION}"
curl --fail --location --output "${TEMP_DIR}/${ARCHIVE}" "${RELEASE_URL}/${ARCHIVE}"
curl --fail --location --output "${TEMP_DIR}/checksums.sha256" "${RELEASE_URL}/checksums.sha256"
(
  cd "${TEMP_DIR}"
  grep "  ${ARCHIVE}$" checksums.sha256 > selected-checksum.sha256
  sha256sum --check selected-checksum.sha256
  tar -xzf "${ARCHIVE}"
)
install -m 0755 "${TEMP_DIR}/mediamtx" "${TARGET_DIR}/mediamtx/mediamtx"

install -m 0644 "${TARGET_DIR}/deploy/mediamtx.service" /etc/systemd/system/mediamtx.service
install -m 0644 "${TARGET_DIR}/deploy/sentrifire-api.service" /etc/systemd/system/sentrifire-api.service
systemctl daemon-reload

echo "Installation complete. Edit these two files before enabling services:"
echo "  ${TARGET_DIR}/backend/.env"
echo "  ${TARGET_DIR}/mediamtx/mediamtx.yml"
echo "Then run: sudo bash ${TARGET_DIR}/deploy/enable_services.sh"
