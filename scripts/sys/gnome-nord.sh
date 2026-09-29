#!/usr/bin/env bash
# file: scripts/sys/gnome-nord.sh
# GNOME Nord 테마 + 배경 적용 (Wayland 세션 필요)
# Domain:
#   - gsettings 적용은 반드시 '데스크탑 사용자 + 활성 Wayland 세션' 컨텍스트에서 실행해야 한다.
# Contract:
#   - root에서 실행하고, --user <desktopUser> 를 반드시 받는다.
#   - DISPLAY/XAUTHORITY/DBUS는 scripts/sys/_desktop-session-env.sh(SSOT)에서 추출한다.
set -Eeuo pipefail
set -o errtrace

gnome_nord_main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"
  # shellcheck disable=SC1090
  source "${root_dir}/scripts/sys/_desktop-session-env.sh"

  # -------------------------------
  # Contract: privileged 명령은 sudo 인증 후 실행
  # -------------------------------
  ensure_sudo_auth_or_throw

  local desk_user=""
  desk_user="$(parse_required_user_arg_or_throw "$@")"
  id -u "${desk_user}" >/dev/null 2>&1 || err "user not found: ${desk_user}"

  must_cmd_or_throw python3
  must_cmd_or_throw sudo
  must_cmd_or_throw getent
  must_cmd_or_throw cut

  local desk_home=""
  desk_home="$(getent passwd "${desk_user}" | cut -d: -f6)"
  [[ -n "${desk_home}" && -d "${desk_home}" ]] || err "home dir not found: user=${desk_user} home=${desk_home:-unset}"

  # -------------------------------
  # SSOT: Desktop session env
  # SideEffect: exports applied to current shell
  # -------------------------------
  eval "$(_desktop_session_env_exports_or_throw "${desk_user}")"

  local -a user_env=(
    "LEGION_SETUP_ROOT=${LEGION_SETUP_ROOT}"
    "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}"
    "XDG_SESSION_TYPE=${XDG_SESSION_TYPE}"
  )

  # -------------------------------
  # Preconditions
  # -------------------------------
  local nord_py="${root_dir}/scripts/sys/gnome-nord-setup.py"
  [[ -f "${nord_py}" ]] || err "missing: ${nord_py}"

  [[ -d "${root_dir}/background" ]] || err "missing dir: ${root_dir}/background"
  ensure_background_symlink_or_throw "${root_dir}/background"

  # -------------------------------
  # SideEffect: gsettings write (as desktop user)
  # -------------------------------
  log "[sys] gnome nord (as ${desk_user})"
  sudo -u "${desk_user}" env "${user_env[@]}" python3 "${nord_py}"
  log "[sys] gnome nord done"
}

# ─────────────────────────────────────────────────────────────
# Top: Business (contract parsing)
# ─────────────────────────────────────────────────────────────
parse_required_user_arg_or_throw() {
  local -a argv=( "$@" )
  local i=0
  local user=""

  while (( i < ${#argv[@]} )); do
    case "${argv[$i]}" in
      --user)
        i=$((i + 1))
        user="${argv[$i]:-}"
        ;;
      *) ;;
    esac
    i=$((i + 1))
  done

  [[ -n "${user}" ]] || err "--user <desktopUser> required"
  echo "${user}"
}

ensure_background_symlink_or_throw() {
  local bg_dir="${1:?bg_dir required}"

  pushd "${bg_dir}" >/dev/null
  if [[ ! -f "background.jpg" ]]; then
    [[ -f "background1.jpg" ]] || err "missing: background.jpg and background1.jpg"
    ln -sf "background1.jpg" "background.jpg"
  fi
  popd >/dev/null
}

gnome_nord_main "$@"
