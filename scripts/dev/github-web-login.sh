#!/usr/bin/env bash
# file: scripts/dev/github-web-login.sh
# GitHub CLI web login + git credential helper + global git identity
#
# /** Domain: Contract: Fail-Fast: SideEffect: */
# Domain:
#   - dev 도메인에서 GitHub 인증(gh)과 git credential helper를 설정한다.
#   - git identity(user.name/user.email)는 "입력 기반"으로만 설정한다(자동 추정 금지).
# Contract:
#   - Ubuntu 26.04 + network 필요
#   - root 직접 실행 금지(사용자 컨텍스트에서 실행; apt는 sudo 사용)
#   - TTY 필요(입력/장치코드 진행)
# Fail-Fast:
#   - 전제조건 미충족/명령 실패 시 즉시 종료(폴백 없음)
# SideEffect:
#   - apt 패키지 설치, gh 인증 토큰 저장, ~/.gitconfig 변경, credential helper 설정
set -Eeuo pipefail
set -o errtrace

github_web_login_main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  github_web_login_contract_validate_entry_or_throw
  github_web_login_execute_or_throw
  log "[github] done"
}

# ─────────────────────────────────────────────────────────────
# Top: Business
# ─────────────────────────────────────────────────────────────
github_web_login_contract_validate_entry_or_throw() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    err "do not run as root (run as desktop user; apt will use sudo)"
  fi

  require_supported_ubuntu_or_throw
  must_cmd_or_throw sudo
  must_cmd_or_throw git

  # Contract: interactive only (device code + identity input)
  if [[ ! -t 0 ]]; then
    err "TTY required (device-code + git identity input). run in an interactive terminal."
  fi

  ensure_sudo_auth_or_throw
}

github_web_login_execute_or_throw() {
  local github_host="${GITHUB_HOST:-github.com}"

  log "[github] install prerequisites (curl/ca-certificates/git/gh)"
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  # NOTE: repo-wide policy가 있다면 apt_fix_vscode_repo_singleton 재사용 가능(있을 때만)
  if declare -F apt_fix_vscode_repo_singleton >/dev/null 2>&1; then
    apt_fix_vscode_repo_singleton
  fi

  sudo_run_or_throw apt-get update -y
  sudo_run_or_throw apt-get install -y --no-install-recommends curl ca-certificates git gh

  must_cmd_or_throw gh

  if github_web_login_is_gh_authed "${github_host}"; then
    log "[github] already authenticated: host=${github_host}"
  else
    log "[github] not authenticated. start web login (device flow): host=${github_host}"
    GH_BROWSER=none BROWSER=none gh auth login \
      --hostname "${github_host}" \
      --git-protocol https \
      --web
  fi

  log "[github] setup git credential helper via gh"
  gh auth setup-git --hostname "${github_host}"

  github_web_login_prompt_git_identity_or_throw
  github_web_login_print_status "${github_host}"
}

github_web_login_is_gh_authed() {
  local host="${1:?host required}"
  gh auth status --hostname "${host}" >/dev/null 2>&1
}

github_web_login_prompt_git_identity_or_throw() {
  local input_name=""
  local input_email=""

  echo -n "[INPUT] Git user.name: "
  read -r input_name
  echo -n "[INPUT] Git user.email: "
  read -r input_email

  [[ -n "${input_name}" ]] || err "git user.name is empty"
  [[ -n "${input_email}" ]] || err "git user.email is empty"

  git config --global user.name "${input_name}"
  git config --global user.email "${input_email}"

  log "[github] git user.name  = $(git config --global user.name)"
  log "[github] git user.email = $(git config --global user.email)"
}

github_web_login_print_status() {
  local host="${1:?host required}"
  echo "------------------------------------"
  log "[github] auth status:"
  gh auth status --hostname "${host}"
  echo "------------------------------------"
  log "[github] remote test:"
  log "  git ls-remote https://${host}/<owner>/<repo>.git"
  echo "------------------------------------"
}

github_web_login_main "$@"
