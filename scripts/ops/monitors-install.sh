#!/usr/bin/env bash
# file: scripts/ops/monitors-install.sh
# Monitoring toolchain bundle (Ubuntu 26.04)
# Policy: no fallbacks, fail-fast
set -Eeuo pipefail
set -o errtrace

main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  ensure_sudo_auth_or_throw

  require_supported_ubuntu_or_throw
  must_cmd_or_throw apt-get
  must_cmd_or_throw systemctl

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  # SideEffect: apt sources may be rewritten (repo/keyring singleton)
  apt_fix_vscode_repo_singleton

  local -a pkgs_common=(
    btop
    htop

    iotop
    iftop
    duf
    nmon

    lm-sensors
    smartmontools
    sysstat
  )

  local -a pkgs_gpu=(
    nvtop
  )

  log "[ops] install packages"
  sudo_run_or_throw apt-get update -y
  sudo_run_or_throw apt-get install -y --no-install-recommends "${pkgs_common[@]}"
  sudo_run_or_throw apt-get install -y --no-install-recommends "${pkgs_gpu[@]}"

  ops_configure_sysstat_or_throw
  ops_configure_smartmontools_or_throw

  ops_contract_validate_binaries_or_throw
  ops_log_versions_best_effort

  ops_print_quick_tips
  log "[ops] done"
}

# ─────────────────────────────────────────────
# Business: services/config
# SideEffect: writes /etc/default/sysstat, systemctl enable/restart
# ─────────────────────────────────────────────
ops_configure_sysstat_or_throw() {
  if [[ -f /etc/default/sysstat ]]; then
    sudo_run_or_throw sed -Ei 's/^\s*ENABLED\s*=.*/ENABLED="true"/' /etc/default/sysstat
  fi

  sudo_run_or_throw systemctl enable sysstat
  sudo_run_or_throw systemctl restart sysstat
  sudo_run_or_throw systemctl is-active --quiet sysstat || err "sysstat not active"
}

ops_configure_smartmontools_or_throw() {
  if systemctl list-unit-files | grep -q '^smartmontools\.service'; then
    sudo_run_or_throw systemctl enable smartmontools.service
    sudo_run_or_throw systemctl restart smartmontools.service
    sudo_run_or_throw systemctl is-active --quiet smartmontools.service || err "smartmontools.service not active"
    return 0
  fi

  err "smartmontools.service unit not found. check smartmontools package state."
}

# ─────────────────────────────────────────────
# Business: contract validation
# ─────────────────────────────────────────────
ops_contract_validate_binaries_or_throw() {
  local check_cmd=""
  check_cmd() { command -v "$1" >/dev/null 2>&1 || err "missing command after install: $1"; }

  check_cmd btop
  check_cmd htop
  check_cmd iotop
  check_cmd iftop
  check_cmd duf
  check_cmd nmon
  check_cmd sensors
  check_cmd smartctl
  check_cmd sar
  check_cmd iostat
  check_cmd mpstat
  check_cmd nvtop
}

# ─────────────────────────────────────────────
# IO: best-effort logging (never throw)
# ─────────────────────────────────────────────
ops_log_versions_best_effort() {
  {
    log "[ops] btop: $(btop --version 2>&1 | head -n1 || true)"
    log "[ops] htop: $(htop --version 2>&1 | head -n1 || true)"
    log "[ops] iotop: $(iotop --version 2>&1 | head -n1 || true)"
    log "[ops] iftop: $(iftop -h 2>&1 | head -n1 || true)"
    log "[ops] duf: $(duf --version 2>&1 | head -n1 || true)"
    log "[ops] nmon: $(nmon -V 2>&1 | head -n1 || true)"
    log "[ops] lm-sensors: $(sensors -v 2>&1 | head -n1 || true)"
    log "[ops] smartmontools: $(smartctl -V 2>&1 | head -n1 || true)"
    log "[ops] sysstat(sar): $(sar -V 2>&1 | head -n1 || true)"
    if command -v nvidia-smi >/dev/null 2>&1; then
      log "[ops] NVIDIA: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true)"
    else
      warn "[ops] nvidia-smi not found (no NVIDIA GPU or driver missing)"
    fi
  } || true
}

ops_print_quick_tips() {
  cat <<'TIP'
[Quick usage]
  • all-in-one:       btop
  • CPU/mem:          htop
  • GPU:              nvtop
  • disk IO:          iotop
  • network:          sudo iftop -i <iface>   # e.g. iftop -i wlan0
  • disk usage:       duf
  • SMART health:     sudo smartctl -H /dev/nvme0
  • sensors:          sensors
  • stats (sar):      sar -u 1 5 | sar -n DEV 1 5 | iostat -xz 1 3
TIP
}

main "$@"
