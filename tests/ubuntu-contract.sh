#!/usr/bin/env bash
# 시스템을 수정하지 않고 OS 계약과 재개 상태 분리를 검증한다.
set -Eeuo pipefail
LEGION_SETUP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LEGION_SETUP_ROOT
XDG_STATE_HOME="$(mktemp -d)"
export XDG_STATE_HOME
trap 'rm -rf "${XDG_STATE_HOME}"' EXIT
source "${LEGION_SETUP_ROOT}/lib/common.sh"

# 운영체제 파일 읽기만 대체하고 나머지 source 동작은 유지한다.
source() {
  if [[ "$1" == /etc/os-release ]]; then
    ID="${TEST_ID}"
    VERSION_ID="${TEST_VERSION}"
    VERSION_CODENAME="${TEST_CODENAME}"
  else
    builtin source "$@"
  fi
}
TEST_ID=ubuntu TEST_VERSION=26.04 TEST_CODENAME=resolute
[[ "${PROJECT_STATE_DIR}" == "${XDG_STATE_HOME}/ubuntu26-legion5-setup" ]]
require_supported_ubuntu_or_throw
new_state="$(resume_file_for_scope_or_throw cmd:sys)"
[[ "${new_state}" == */resume.cmd:sys.ubuntu-26.04.done ]]
for pair in 24.04:noble 26.04:noble 24.04:resolute 25.10:questing; do
  TEST_VERSION="${pair%%:*}" TEST_CODENAME="${pair#*:}"
  if (require_supported_ubuntu_or_throw) 2>/dev/null; then
    echo "오류: 지원하지 않는 버전이 허용됐습니다: ${pair}" >&2
    exit 1
  fi
done
TEST_ID=debian TEST_VERSION=26.04 TEST_CODENAME=resolute
if (require_supported_ubuntu_or_throw) 2>/dev/null; then
  exit 1
fi
echo "OS 계약 및 재개 상태 분리 검증 통과"

# 실제 설치를 호출하지 않고 sys가 선택하는 단계만 기록한다.
source() {
  [[ "$1" == "${LEGION_SETUP_ROOT}/lib/common.sh" ]] || builtin source "$@"
}
require_supported_ubuntu_or_throw() { VERSION_ID="${TEST_VERSION}"; }
confirm_or_skip() { return 0; }
ensure_sudo_auth_or_throw() { return 0; }
resume_step() { shift 3; "$@"; }
must_run_or_throw() { printf '%s\n' "$1"; }
TEST_VERSION=26.04
result="$(builtin source "${LEGION_SETUP_ROOT}/scripts/cmd/sys.sh")"
[[ "${result}" == *scripts/sys/wayland-setup.sh* ]]
[[ "${result}" != *scripts/sys/xorg-ensure.sh* ]]
[[ "${result}" == *scripts/sys/nvidia-stack.sh* ]]
[[ "${result}" != *legion-hdmi* ]]
echo "26.04 전용 sys 단계 검증 통과"
