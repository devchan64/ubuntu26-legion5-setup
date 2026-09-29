#!/usr/bin/env bash
# file: scripts/dev/docker/nvidia-toolkit.sh
#
# /** Domain: Contract: Fail-Fast: SideEffect: */
# - Domain: Docker에서 NVIDIA GPU 런타임(nvidia-container-toolkit)을 설치/활성화한다.
# - Contract:
#   - apt/daemon 설정 명령은 sudo 인증 후 실행
#   - Ubuntu 26.04(resolute) 기준. 다른 배포판/버전이면 즉시 실패(폴백 없음)
#   - Docker 엔진이 이미 설치되어 있어야 한다(SSOT: scripts/dev/docker/install.sh)
# - Fail-Fast: 전제조건 불충족/명령 부재/리포 등록 실패 시 즉시 종료
# - SideEffect: apt repo 추가, apt install, docker daemon 설정 변경, docker 서비스 재시작
set -Eeuo pipefail
set -o errtrace

# -------------------------------
# Privilege Contract
# -------------------------------
root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
# shellcheck disable=SC1090
source "${root_dir}/lib/common.sh"
ensure_sudo_auth_or_throw
# -------------------------------
# Contract: minimal commands
# -------------------------------
for c in apt-get curl gpg sed tee systemctl; do
  command -v "$c" >/dev/null 2>&1 || { echo "[ERR ] required command not found: $c" >&2; exit 1; }
done
command -v docker >/dev/null 2>&1 || { echo "[ERR ] docker not found. SSOT: scripts/dev/docker/install.sh 를 먼저 실행하세요." >&2; exit 1; }

# -------------------------------
# Contract: Ubuntu 26.04 (resolute)
# -------------------------------
require_supported_ubuntu_or_throw

log() { echo "[INFO] $*"; }

nvidia_toolkit_main() {
  log "nvidia-container-toolkit install (stub)"
  # TODO: 실제 구현은 아래 단계로 확장
  # 1) NVIDIA libnvidia-container repo 추가
  # 2) apt-get update
  # 3) apt-get install -y nvidia-container-toolkit
  # 4) nvidia-ctk runtime configure --runtime=docker
  # 5) systemctl restart docker
  # 6) (선택) nvidia-smi / docker run --gpus all ... 검증
}

nvidia_toolkit_main "$@"
