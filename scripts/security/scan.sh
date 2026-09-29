#!/usr/bin/env bash
# file: scripts/security/scan.sh
# Security scan runner (Ubuntu 26.04)
# - ClamAV: scan targets (default: sudo user's home), report infected only
# - rkhunter: rootkit check (non-interactive)
# - lynis: system audit (quick)
# Policy: no fallbacks, fail-fast. requires explicit consent per run.
set -Eeuo pipefail
set -o errtrace

main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  ensure_sudo_auth_or_throw
  require_supported_ubuntu_or_throw

  must_cmd_or_throw clamscan
  must_cmd_or_throw rkhunter
  must_cmd_or_throw lynis

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  local auto_yes=0
  if [[ "${1:-}" == "--yes" ]]; then
    auto_yes=1
    shift || true
  fi

  security_scan_require_consent_or_throw "${auto_yes}"

  local sec_state_dir="${PROJECT_STATE_DIR:?PROJECT_STATE_DIR required}/security"
  mkdir -p "${sec_state_dir}"

  local ts=""
  ts="$(date +'%Y%m%d_%H%M%S')"

  local -a clam_targets=()
  resolve_clam_targets_or_throw clam_targets

  local clam_log="${sec_state_dir}/clamav_${ts}.log"
  local rkh_log="${sec_state_dir}/rkhunter_${ts}.log"

  security_scan_run_clamav_or_throw "${clam_log}" "${clam_targets[@]}"
  security_scan_run_rkhunter_or_throw "${rkh_log}"
  security_scan_run_lynis_best_effort

  security_scan_print_summary "${clam_log}" "${rkh_log}"

  log "[scan] done"
}

# ─────────────────────────────────────────────────────────────
# Top: Business
# ─────────────────────────────────────────────────────────────
security_scan_require_consent_or_throw() {
  local auto_yes="${1:?auto_yes required}"

  if [[ "${auto_yes}" -eq 1 ]]; then
    log "[scan] --yes: proceed without prompt"
    return 0
  fi

  if [[ ! -r /dev/tty ]]; then
    err "consent required but no TTY available. rerun with --yes"
  fi

  log "[scan] this scan may take a while"
  printf "Run security scan now? [y/N] " > /dev/tty
  local ans=""
  read -r ans < /dev/tty || err "failed to read from tty"
  case "${ans}" in
    y|Y) return 0 ;;
    *) warn "[scan] cancelled by user"; exit 0 ;;
  esac
}

resolve_clam_targets_or_throw() {
  local -n out_targets="${1:?out_targets required}"

  if [[ -n "${SEC_CLAM_TARGETS:-}" ]]; then
    # Contract: space-delimited paths; no normalization
    # shellcheck disable=SC2206
    out_targets=( ${SEC_CLAM_TARGETS} )
    [[ "${#out_targets[@]}" -gt 0 ]] || err "SEC_CLAM_TARGETS is set but empty"
    return 0
  fi


  local home_dir="${HOME:?HOME required}"
  [[ -d "${home_dir}" ]] || err "home dir not found: ${home_dir}"
  out_targets=( "${home_dir}" )
}

security_scan_run_clamav_or_throw() {
  local clam_log="${1:?clam_log required}"
  shift || true
  local -a targets=( "$@" )
  [[ "${#targets[@]}" -gt 0 ]] || err "clamav targets required"

  log "[scan] clamav start: ${targets[*]}"
  set +e
  clamscan \
    --infected \
    --recursive \
    --scan-archive=yes \
    --cross-fs=no \
    --log="${clam_log}" \
    "${targets[@]}"
  local ec=$?
  set -e

  if [[ "${ec}" -eq 0 ]]; then
    log "[scan] clamav OK (no infections) log=${clam_log}"
    return 0
  fi

  if [[ "${ec}" -eq 1 ]]; then
    warn "[scan] clamav infections found log=${clam_log}"
    return 0
  fi

  err "clamav scan failed (exit=${ec}) log=${clam_log}"
}

security_scan_run_rkhunter_or_throw() {
  local rkh_log="${1:?rkh_log required}"

  log "[scan] rkhunter update (best-effort)"
  sudo_run_or_throw rkhunter --update || warn "[scan] rkhunter update warned; continue"

  log "[scan] rkhunter check"
  set +o pipefail
  sudo_run_or_throw rkhunter --check --sk --rwo --nocolors --quiet | tee "${rkh_log}" >/dev/null
  local rc=${PIPESTATUS[0]}
  set -o pipefail

  if [[ "${rc}" -eq 0 ]]; then
    log "[scan] rkhunter OK log=${rkh_log}"
    return 0
  fi

  if [[ "${rc}" -eq 1 ]]; then
    warn "[scan] rkhunter warnings log=${rkh_log}"
    return 0
  fi

  err "rkhunter failed (rc=${rc}) log=${rkh_log}"
}

security_scan_run_lynis_best_effort() {
  log "[scan] lynis audit (quick)"
  if sudo_run_or_throw lynis audit system --quick --no-colors --quiet; then
    log "[scan] lynis done (reports under /var/log/lynis)"
  else
    warn "[scan] lynis reported warnings/errors (see /var/log/lynis)"
  fi
}

security_scan_print_summary() {
  local clam_log="${1:?clam_log required}"
  local rkh_log="${2:?rkh_log required}"

  cat <<EOF
[Security scan finished]

• ClamAV log:         ${clam_log}
  - If infections found, paths are listed. Quarantine/remove manually as needed.

• rkhunter log:       ${rkh_log}
  - Review warnings first.

• Lynis report:       /var/log/lynis/report.dat
• Lynis log:          /var/log/lynis/lynis.log
EOF
}

main "$@"
