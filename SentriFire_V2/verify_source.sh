#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

(
  cd "${PROJECT_DIR}/backend"
  python -m unittest discover -s tests -v
  python -m compileall -q app tests
)

bash -n "${PROJECT_DIR}/deploy/install_pi.sh" "${PROJECT_DIR}/deploy/enable_services.sh"

if command -v flutter >/dev/null 2>&1; then
  (
    cd "${PROJECT_DIR}/mobile"
    flutter pub get
    flutter analyze
    flutter test
  )
else
  echo "Flutter SDK not found; run flutter pub get, analyze, and test on the build workstation."
fi

