#!/usr/bin/env bash
# file: scripts/sys/bootstrap.sh
# Ubuntu 26.04(resolute) 공통 부트스트랩 (비대화형, 폴백 없음)
#
# /** Domain: Contract: Fail-Fast: SideEffect: */
# - Domain: sys 도메인 공통 전제(apt 가능, 기본 패키지, universe enable)를 만족시키는 부트스트랩 단계
# - Contract: Ubuntu 26.04(resolute)만 지원, 일반 사용자 실행 + privileged 명령 단위 sudo, bash + strict mode
# - Fail-Fast: 전제조건/명령 실패 시 즉시 err(throw)
# - SideEffect: apt index 갱신, 패키지 설치, apt repo(universe) 활성화
set -Eeuo pipefail
set -o errtrace

bootstrap_main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  # -------------------------------
  # Contract: sudo + OS + required commands
  # -------------------------------
  ensure_sudo_auth_or_throw
  require_supported_ubuntu_or_throw
  must_cmd_or_throw apt-get
  must_cmd_or_throw add-apt-repository

  # -------------------------------
  # Contract: non-interactive (SSOT)
  # -------------------------------
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  # -------------------------------
  # SideEffect: enable universe (idempotent)
  # -------------------------------
  log "[bootstrap] enable universe"
  sudo_run_or_throw add-apt-repository -y universe

  # -------------------------------
  # SideEffect: apt index update
  # -------------------------------
  log "[bootstrap] apt-get update"
  sudo_run_or_throw apt-get update -y

  # -------------------------------
  # SideEffect: install common packages (idempotent)
  # -------------------------------
  log "[bootstrap] install common packages"
  sudo_run_or_throw apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    unzip \
    jq \
    gnupg \
    software-properties-common \
    build-essential \
    xclip \
    fonts-firacode \
    fonts-jetbrains-mono \
    gnome-themes-extra
  # Nord 터미널 팔레트 대상은 기본 터미널과 별도로 설치한다.
  sudo_run_or_throw apt-get install -y gnome-terminal wl-clipboard

  log "[bootstrap] done"
}

bootstrap_main "$@"
