#!/usr/bin/env bash
# file: lib/common.sh
# Common utilities for ubuntu26-legion5-setup
# 원칙: 폴백 없음, 에러 즉시 종료
set -Eeuo pipefail
set -o errtrace

# ─────────────────────────────────────────────────────────────
# Business: logging / fail-fast
# ─────────────────────────────────────────────────────────────
ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }

log()  { echo "[INFO ][$(ts)] $*"; }
warn() { echo "[WARN ][$(ts)] $*" >&2; }
err()  { echo "[ERROR][$(ts)] $*" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────
# Business: Repo root + state directory (SSOT)
# SideEffect: mkdir -p
# ─────────────────────────────────────────────────────────────
resolve_repo_root_or_throw() {
  if [[ -n "${LEGION_SETUP_ROOT:-}" ]]; then
    [[ -d "${LEGION_SETUP_ROOT}" ]] || err "LEGION_SETUP_ROOT not a directory: ${LEGION_SETUP_ROOT}"
    (cd -- "${LEGION_SETUP_ROOT}" >/dev/null 2>&1 && pwd -P) || err "failed to resolve LEGION_SETUP_ROOT"
    return 0
  fi

  (cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P) \
    || err "failed to resolve repo root from BASH_SOURCE"
}

ensure_state_path_writable_or_throw() {
  local path="${1:?path required}"
  [[ -e "${path}" ]] || err "상태 경로가 없습니다: ${path}"
  if [[ -w "${path}" ]]; then
    return 0
  fi

  local uid=""
  local gid=""
  uid="$(id -u)" || err "현재 사용자 uid 확인 실패"
  gid="$(id -g)" || err "현재 사용자 gid 확인 실패"

  warn "[state] 상태 경로 쓰기 권한 복구: ${path}"
  ensure_sudo_auth_or_throw
  sudo_run_or_throw chown "${uid}:${gid}" "${path}"
  [[ -w "${path}" ]] || err "상태 경로 쓰기 권한 복구 실패: ${path}"
}

init_project_state_dir_or_throw() {
  local xdg_state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
  [[ -n "${xdg_state_home}" ]] || err "XDG_STATE_HOME resolved empty"
  PROJECT_STATE_DIR="${xdg_state_home}/ubuntu26-legion5-setup"
  mkdir -p "${PROJECT_STATE_DIR}"
}

REPO_ROOT="$(resolve_repo_root_or_throw)"
PROJECT_STATE_DIR="" # set by init_project_state_dir_or_throw
init_project_state_dir_or_throw

# ─────────────────────────────────────────────────────────────
# Business: Reboot barrier (SSOT)
# Domain: Contract: Fail-Fast: SideEffect:
#   - 재부팅이 필요한 step은 require_reboot_or_throw(reason) 호출로 barrier를 세우고 즉시 실패한다.
#   - 다음 실행에서 boot_id 변경이 감지되면 barrier를 자동 해제한다.
# SideEffect: barrier file read/write/remove
# ─────────────────────────────────────────────────────────────
REBOOT_REQUIRED_FILE="${PROJECT_STATE_DIR}/reboot.required"

get_linux_boot_id_or_throw() {
  [[ -r /proc/sys/kernel/random/boot_id ]] || err "boot_id not readable: /proc/sys/kernel/random/boot_id"
  cat /proc/sys/kernel/random/boot_id
}

clear_reboot_barrier_if_rebooted() {
  [[ -f "${REBOOT_REQUIRED_FILE}" ]] || return 0

  local prev_boot_id=""
  prev_boot_id="$(grep -E '^boot_id=' "${REBOOT_REQUIRED_FILE}" | head -n1 | cut -d'=' -f2- || true)"
  local cur_boot_id=""
  cur_boot_id="$(get_linux_boot_id_or_throw)"

  # Contract: boot_id가 바뀌면 재부팅이 수행된 것으로 간주하고 barrier를 해제한다.
  if [[ -n "${prev_boot_id}" && "${cur_boot_id}" != "${prev_boot_id}" ]]; then
    log "[reboot] boot_id changed → clear reboot barrier"
    rm -f "${REBOOT_REQUIRED_FILE}"
  fi
}

assert_no_reboot_barrier_or_throw() {
  [[ -f "${REBOOT_REQUIRED_FILE}" ]] || return 0
  local reason=""
  reason="$(grep -E '^reason=' "${REBOOT_REQUIRED_FILE}" | head -n1 | cut -d'=' -f2- || true)"
  err "[reboot] pending reboot barrier detected. reboot required. reason=${reason:-unknown}"
}

require_reboot_or_throw() {
  local reason="${1:-unknown}"

  # SideEffect: barrier file write
  {
    echo "created_at=$(ts)"
    echo "boot_id=$(get_linux_boot_id_or_throw)"
    echo "reason=${reason}"
  } > "${REBOOT_REQUIRED_FILE}"

  err "[reboot] reboot required. reason=${reason}"
}

# ─────────────────────────────────────────────────────────────
# Business: Resume state (SSOT)
# Domain: Contract: Fail-Fast: SideEffect:
#   - resume key는 scope(커맨드) 단위로 관리한다.
#   - 완료 상태는 PROJECT_STATE_DIR 아래 파일로만 기록한다.
#   - 동의는 저장하지 않는다.
# SideEffect: resume file read/write/remove
# ─────────────────────────────────────────────────────────────
resume_file_for_scope_or_throw() {
  local scope="${1:?scope required}"
  # 이미 배포된 26.04 완료 기록의 경로를 유지한다.
  echo "${PROJECT_STATE_DIR}/resume.${scope}.ubuntu-26.04.done"
}

resume_reset_scope() {
  local scope="${1:?scope required}"
  local resume_file=""
  resume_file="$(resume_file_for_scope_or_throw "${scope}")"
  rm -f "${resume_file}"
  log "[resume] reset: scope=${scope}"
}

resume_has_step() {
  local scope="${1:?scope required}"
  local step="${2:?step required}"
  local resume_file=""
  resume_file="$(resume_file_for_scope_or_throw "${scope}")"
  [[ -f "${resume_file}" ]] || return 1
  grep -qxF "${step}" "${resume_file}"
}

resume_mark_step_done_or_throw() {
  local scope="${1:?scope required}"
  local step="${2:?step required}"
  local resume_file=""
  resume_file="$(resume_file_for_scope_or_throw "${scope}")"

  ensure_state_path_writable_or_throw "${PROJECT_STATE_DIR}"
  if [[ -e "${resume_file}" ]]; then
    ensure_state_path_writable_or_throw "${resume_file}"
  fi
  touch "${resume_file}"
  if ! grep -qxF "${step}" "${resume_file}"; then
    echo "${step}" >> "${resume_file}"
  fi
}

resume_step() {
  local scope="${1:?scope required}"
  local step="${2:?step required}"
  shift 2 || err "resume_step requires: scope step -- cmd..."

  # Contract: require "--" delimiter (AGENTS.md)
  if [[ "${1:-}" != "--" ]]; then
    err "[resume] Contract violation: missing '--' delimiter"
  fi
  shift

  if resume_has_step "${scope}" "${step}"; then
    log "[resume] skip: scope=${scope} step=${step}"
    return 0
  fi

  log "[resume] run : scope=${scope} step=${step}"
  "$@"
  resume_mark_step_done_or_throw "${scope}" "${step}"
}

# ─────────────────────────────────────────────────────────────
# IO/Adapter: Prompt helpers
# Domain: Contract: Fail-Fast:
# ─────────────────────────────────────────────────────────────
assume_yes() {
  [[ "${LEGION_ASSUME_YES:-0}" -eq 1 ]]
}

confirm_or_throw() {
  local msg="${1:?msg required}"
  if assume_yes; then
    log "[prompt] --yes: auto-accept: ${msg}"
    return 0
  fi

  local ans=""
  read -r -p "${msg} [y/N] " ans
  case "${ans}" in
    y|Y) return 0 ;;
    *) err "user declined: ${msg}" ;;
  esac
}

confirm_or_skip() {
  local msg="${1:?msg required}"
  if assume_yes; then
    log "[prompt] --yes: auto-accept: ${msg}"
    return 0
  fi

  local ans=""
  read -r -p "${msg} [y/N] " ans
  case "${ans}" in
    y|Y) return 0 ;;
    *)
      warn "[prompt] 사용자가 거절하여 단계를 건너뜁니다: ${msg}"
      return 1
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────
# IO/Adapter: Command helpers
# Domain: Contract: Fail-Fast:
# ─────────────────────────────────────────────────────────────
must_cmd_or_throw() {
  local cmd="${1:?cmd required}"
  command -v "${cmd}" >/dev/null 2>&1 || err "required command not found: ${cmd}"
}

must_run_or_throw() {
  local rel="${1:?script required}"
  shift || true
  local script="${REPO_ROOT}/${rel}"

  [[ -x "${script}" ]] || err "script not executable: ${script}"
  log "run: ${rel} $*"
  bash "${script}" "$@"
}

# ─────────────────────────────────────────────────────────────
# Business: APT 저장소 정리
# SideEffect: /etc/apt/sources.list, /etc/apt/sources.list.d/*.list 수정 가능
# ─────────────────────────────────────────────────────────────
apt_remove_repo_lines_globally() {
  local pattern="${1:?repository pattern required}"
  local -a files=(/etc/apt/sources.list /etc/apt/sources.list.d/*.list)
  local file=""

  for file in "${files[@]}"; do
    [[ -f "${file}" ]] || continue
    if grep -Fq "${pattern}" "${file}"; then
      log "[apt] 저장소 정리: ${file}에서 '${pattern}' 항목 제거"
      sudo_run_or_throw sed -i "\\|${pattern}|d" "${file}"
    fi
  done
}

# ─────────────────────────────────────────────────────────────
# Business: VS Code APT 저장소/keyring 단일화
# Contract: Microsoft 저장소는 vscode.sources Deb822 파일 하나로 관리한다.
# SideEffect: /usr/share/keyrings, /etc/apt/sources.list.d 수정
# ─────────────────────────────────────────────────────────────
apt_fix_vscode_repo_singleton() {
  must_cmd_or_throw dpkg
  must_cmd_or_throw wget
  must_cmd_or_throw gpg
  must_cmd_or_throw mktemp

  local keyring_path="/usr/share/keyrings/microsoft.gpg"
  local sources_path="/etc/apt/sources.list.d/vscode.sources"
  local gnupg_home=""
  local keyring_tmp=""
  local sources_tmp=""
  local arch=""

  ensure_sudo_auth_or_throw
  sudo_run_or_throw install -d -m 0755 -o root -g root /usr/share/keyrings

  gnupg_home="$(mktemp -d /tmp/legion-vscode-gnupg-XXXXXX)"
  keyring_tmp="$(mktemp /tmp/legion-microsoft-keyring-XXXXXX.gpg)"
  sources_tmp="$(mktemp /tmp/legion-vscode-sources-XXXXXX.sources)"
  chmod 0700 "${gnupg_home}"
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | GNUPGHOME="${gnupg_home}" gpg --dearmor --yes --output "${keyring_tmp}"
  rm -rf "${gnupg_home}"
  sudo_run_or_throw install -m 0644 -o root -g root "${keyring_tmp}" "${keyring_path}"
  rm -f "${keyring_tmp}"

  apt_remove_repo_lines_globally "https://packages.microsoft.com/repos/code"
  sudo_run_or_throw rm -f /etc/apt/sources.list.d/vscode.list "${sources_path}"

  arch="$(dpkg --print-architecture)"
  [[ -n "${arch}" ]] || err "[apt] dpkg 아키텍처 확인 실패"

  {
    echo "Architectures: ${arch}"
    echo "Types: deb"
    echo "URIs: https://packages.microsoft.com/repos/code"
    echo "Suites: stable"
    echo "Components: main"
    echo "Signed-By: ${keyring_path}"
  } > "${sources_tmp}"
  sudo_run_or_throw install -m 0644 -o root -g root "${sources_tmp}" "${sources_path}"
  rm -f "${sources_tmp}"
}

# ─────────────────────────────────────────────────────────────
# Business: 명령 단위 권한 상승 / 플랫폼 계약 (SSOT)
# Domain: Contract: Fail-Fast:
# ─────────────────────────────────────────────────────────────
ensure_sudo_auth_or_throw() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi

  must_cmd_or_throw sudo
  log "[sudo] 시스템 변경 권한 인증"
  sudo -v || err "[sudo] 인증 실패"
}

sudo_run_or_throw() {
  [[ "$#" -gt 0 ]] || err "sudo_run_or_throw에 실행할 명령이 필요합니다"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return
  fi

  must_cmd_or_throw sudo
  sudo "$@"
}
require_supported_ubuntu_or_throw() {
  [[ -r /etc/os-release ]] || err "missing /etc/os-release"
  # shellcheck disable=SC1091
  source /etc/os-release

  [[ "${ID:-}" == "ubuntu" ]] || err "unsupported distro: ID=${ID:-unknown} (required: ubuntu)"
  case "${VERSION_ID:-}:${VERSION_CODENAME:-}" in
    26.04:resolute) ;;
    *) err "지원하지 않는 Ubuntu 버전: ${VERSION_ID:-unknown}/${VERSION_CODENAME:-unknown} (26.04/resolute 필요)" ;;
  esac
}
