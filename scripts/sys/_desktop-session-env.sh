#!/usr/bin/env bash
# file: scripts/sys/_desktop-session-env.sh
# GNOME Wayland 세션에서 gsettings를 실행하기 위한 환경 추출 유틸
# 정책:
#   - Fail-Fast: 조건 불충족 시 즉시 err
#   - SSOT: 세션/ENV 해석 로직은 여기 한 곳에만 둔다.
# 사용:
#   eval "$(_desktop_session_env_exports_or_throw <desktopUser>)"
#
# /** Domain: Contract: Fail-Fast: SideEffect: */
set -Eeuo pipefail
set -o errtrace

_desktop_session_env_exports_or_throw() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"
  require_supported_ubuntu_or_throw
  local expected_type=wayland

  # -------------------------------
  # Contract: privileged 명령은 sudo 인증 후 실행
  # -------------------------------
  ensure_sudo_auth_or_throw >&2

  local desk_user="${1:-}"
  [[ -n "${desk_user}" ]] || err "desktop user required: _desktop_session_env_exports_or_throw <user>"
  id -u "${desk_user}" >/dev/null 2>&1 || err "user not found: ${desk_user}"

  must_cmd_or_throw loginctl

  local desk_uid=""
  desk_uid="$(id -u "${desk_user}")" || err "failed to resolve uid: ${desk_user}"

  # -------------------------------
  # Contract: 활성 Wayland 세션
  # -------------------------------
  local session_id=""
  local session_type=""
  local session_state=""

  while read -r sid uid user _; do
    [[ "${uid:-}" == "${desk_uid}" ]] || continue
    [[ "${user:-}" == "${desk_user}" ]] || continue

    session_type="$(loginctl show-session "${sid}" -p Type --value 2>/dev/null || true)"
    session_state="$(loginctl show-session "${sid}" -p State --value 2>/dev/null || true)"

    if [[ "${session_type}" == "${expected_type}" && "${session_state}" == "active" ]]; then
      session_id="${sid}"
      break
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)

  [[ -n "${session_id}" ]] || err "활성 ${expected_type} 세션이 없습니다. 데스크톱에 로그인하세요."
  [[ -S "/run/user/${desk_uid}/bus" ]] || err "사용자 DBus 소켓이 없습니다."
  printf 'export %s=%q\n' XDG_RUNTIME_DIR "/run/user/${desk_uid}" DBUS_SESSION_BUS_ADDRESS "unix:path=/run/user/${desk_uid}/bus" XDG_SESSION_TYPE wayland
}
