#!/usr/bin/env bash
# file: scripts/dev/node/install.sh
#
# /** Domain: Contract: Fail-Fast: SideEffect: */
# - Domain: NVM 기반으로 Node.js 툴체인을 설치하고 corepack(pnpm/yarn)을 활성화한다.
# - Contract:
#   - Ubuntu(resolute) 사용자 환경에서 동작(다른 배포판은 즉시 실패)
#   - 패키지 설치(apt)는 여기서 하지 않는다(SSOT: scripts/sys/bootstrap.sh)
#   - 네트워크 필요(github raw 접근)
#   - root로 실행 금지(NVM은 유저 홈에 설치)
# - Fail-Fast: 전제조건 불충족/명령 부재/다운로드 실패 시 즉시 종료(폴백 없음)
# - SideEffect: ~/.nvm 생성 및 수정, 셸 프로파일 변경(NVM installer), node/npm/corepack 설치 상태 변경

set -Eeuo pipefail
set -o errtrace

_ts(){ date +'%F %T'; }
log(){ printf "[INFO ][%s] %s\n" "$(_ts)" "$*"; }
err(){ printf "[ERR  ][%s] %s\n" "$(_ts)" "$*" >&2; exit 1; }

NODE_VERSION="${NODE_VERSION:-22}"
NVM_VERSION="${NVM_VERSION:-0.39.7}"

# -------------------------------
# Contract: root 금지
# -------------------------------
if [[ "${EUID}" -eq 0 ]]; then
  err "root로 NVM/Node 설치 금지. sudo 없이 일반 유저로 실행하세요."
fi

# -------------------------------
# Contract: Ubuntu only (no fallback)
# -------------------------------
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  err "/etc/os-release not found"
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
  err "unsupported distro: ID=${ID:-} (ubuntu only)"
fi

# -------------------------------
# Contract: prerequisites (SSOT 외부에서 설치 금지)
# -------------------------------
for c in curl; do
  command -v "$c" >/dev/null 2>&1 || err "required command not found: $c (SSOT: scripts/sys/bootstrap.sh 에서 설치)"
done

# -------------------------------
# Domain: NVM 설치/로드
# -------------------------------
install_nvm_if_missing_or_throw() {
  if [[ -d "${HOME}/.nvm" ]]; then
    log "NVM already installed: ${HOME}/.nvm"
    return
  fi

  log "Installing NVM v${NVM_VERSION}"
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
  [[ -d "${HOME}/.nvm" ]] || err "NVM install finished but ~/.nvm not found"
}

load_nvm_or_throw() {
  export NVM_DIR="${HOME}/.nvm"
  [[ -s "${NVM_DIR}/nvm.sh" ]] || err "nvm.sh not found: ${NVM_DIR}/nvm.sh"

  # shellcheck disable=SC1090
  . "${NVM_DIR}/nvm.sh"

  command -v nvm >/dev/null 2>&1 || err "nvm command not available after sourcing nvm.sh"
}

install_node_or_throw() {
  log "Installing Node v${NODE_VERSION}"
  nvm install "${NODE_VERSION}"
  nvm alias default "${NODE_VERSION}"
  nvm use default
}

enable_corepack_or_throw() {
  command -v corepack >/dev/null 2>&1 || err "corepack not found (Node 16.10+ required)"
  log "Enabling corepack (pnpm/yarn)"
  corepack enable
}

# -------------------------------
# Execute (SideEffect grouped)
# -------------------------------
install_nvm_if_missing_or_throw
load_nvm_or_throw
install_node_or_throw
enable_corepack_or_throw

log "Installed versions:"
node -v
npm -v
