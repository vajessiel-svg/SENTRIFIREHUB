#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this command with sudo."
  exit 1
fi

BACKEND_ENV="/opt/sentrifire/backend/.env"
MEDIAMTX_CONFIG="/opt/sentrifire/mediamtx/mediamtx.yml"

for required_file in "${BACKEND_ENV}" "${MEDIAMTX_CONFIG}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Missing required file: ${required_file}"
    exit 1
  fi
  if grep -q "CHANGE_ME" "${required_file}"; then
    echo "Replace every CHANGE_ME value in ${required_file} first."
    exit 1
  fi
done

chown sentrifire:sentrifire "${BACKEND_ENV}" "${MEDIAMTX_CONFIG}"
chmod 0600 "${BACKEND_ENV}" "${MEDIAMTX_CONFIG}"
systemctl enable --now mediamtx.service
systemctl enable --now sentrifire-api.service

sleep 2
systemctl --no-pager --full status mediamtx.service sentrifire-api.service
echo "Check API health at http://PI_ADDRESS:8000/health"

