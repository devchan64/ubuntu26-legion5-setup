#!/usr/bin/env bash
# file: scripts/dev/python/install.sh
# Python toolchain install for Ubuntu 26.04
# - Installs python3, python3-venv, python3-pip
# Policy: no fallbacks, exit on error
set -Eeuo pipefail
set -o errtrace

main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  ensure_sudo_auth_or_throw

  require_supported_ubuntu_or_throw
  must_cmd_or_throw apt-get
  must_cmd_or_throw python3 || true # 설치 전이므로 best-effort (설치 후 검증에서 엄격)

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  log "[python] apt-get update"
  sudo_run_or_throw apt-get update -y

  log "[python] install: python3 python3-venv python3-pip"
  sudo_run_or_throw apt-get install -y --no-install-recommends python3 python3-venv python3-pip

  must_cmd_or_throw python3
  log "[python] python: $(python3 --version)"
  log "[python] pip: $(python3 -m pip --version)"
  log "[python] done"
}

main "$@"
