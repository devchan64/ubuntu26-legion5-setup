#!/usr/bin/env bash
# file: scripts/cmd/sys.sh
# Ubuntu 26.04 GNOME Wayland 시스템 설정
# 정책:
#   - 동의는 저장하지 않음. 실행 시마다 "전체 동의" 1회만 질의
#   - --yes 이면 프롬프트 없이 진행
#   - 전제조건 불충족 시 즉시 실패(err), 폴백 없음
set -Eeuo pipefail
set -o errtrace

sys_main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"
  require_supported_ubuntu_or_throw

  # ─────────────────────────────────────────────────────────────
  # IO: Desktop user resolve (SSOT)
  # ─────────────────────────────────────────────────────────────
  local desk_user="${USER:?USER required}"
  if [[ "${1:-}" == "--user" ]]; then
    desk_user="${2:?--user requires value}"
    shift 2
  fi

  if ! confirm_or_skip "[sys] 이 단계는 시스템 설정을 변경합니다. 계속할까요?"; then
    log "[sys] skipped"
    return 0
  fi

  # ─────────────────────────────────────────────────────────────
  # Privilege Contract
  # ─────────────────────────────────────────────────────────────
  ensure_sudo_auth_or_throw

  # ─────────────────────────────────────────────────────────────
  # Business: Orchestration (resume scope: cmd:sys)
  # ─────────────────────────────────────────────────────────────
  local resume_scope="cmd:sys"
  if [[ -n "${RESUME_SCOPE_KEY:-}" ]]; then
    resume_scope="${RESUME_SCOPE_KEY}"
  fi

  # ① Wayland 설정
  resume_step "${resume_scope}" "sys:wayland:ensure" \
    -- must_run_or_throw "scripts/sys/wayland-setup.sh"

  # ② GNOME basic
  resume_step "${resume_scope}" "sys:gnome:basic" \
    -- \
    must_run_or_throw "scripts/sys/bootstrap.sh" --user "${desk_user}"

  # ③ GNOME Nord (run once or it will reapply theme every time)
  resume_step "${resume_scope}" "sys:gnome:nord" \
    -- \
    must_run_or_throw "scripts/sys/gnome-nord.sh" --user "${desk_user}"

  # ④ Legion HDMI
  resume_step "${resume_scope}" "sys:nvidia:driver" \
    -- must_run_or_throw "scripts/sys/nvidia-stack.sh"
  log "[sys] 화면 확장·배치는 GNOME 설정 → 디스플레이에서 설정하세요."

  log "[sys] done"
}

# Contract: scripts/install-all.sh expects <domain>_main
sys_main "$@"
