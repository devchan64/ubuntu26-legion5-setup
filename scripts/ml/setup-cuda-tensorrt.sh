#!/usr/bin/env bash
# Ubuntu 26.04 공식 CUDA 패키지와 사용자 TensorRT를 설치한다.
set -Eeuo pipefail
set -o errtrace

ml_cuda_tensorrt_main() {
  source "${LEGION_SETUP_ROOT:?}/lib/common.sh"
  require_supported_ubuntu_or_throw
  [[ "${EUID}" -ne 0 ]] || err "sudo 없이 일반 사용자로 실행하세요."
  [[ -z "${CUDA_LOCAL_DEB_URL:-}${CUDA_PIN_URL:-}${CUDA_LOCAL_REPO_DIR:-}" ]] \
    || err "CUDA 로컬 저장소 설정은 지원하지 않습니다."
  [[ "${INSTALL_NVIDIA_OPEN:-0}" == 0 && "${INSTALL_CUDA_DRIVERS:-0}" == 0 ]] \
    || err "NVIDIA 드라이버는 sys 명령으로 설치하세요."
  must_cmd_or_throw apt-get
  ensure_sudo_auth_or_throw
  sudo_run_or_throw apt-get update
  sudo_run_or_throw apt-get install -y "${CUDA_TOOLKIT_PKG:-cuda-toolkit}" python3-pip
  PYTHON_BIN="${PYTHON_BIN:-python3}"
  TENSORRT_PIP_VERSION="${TENSORRT_PIP_VERSION:-}"
  ml_cuda_tensorrt_install_tensorrt_pip_user_or_throw
  must_cmd_or_throw nvcc
  nvcc --version
  log "[ml] Ubuntu 26.04 CUDA 및 TensorRT 설치 완료"
}

ml_cuda_tensorrt_install_tensorrt_pip_user_or_throw() {
  must_cmd_or_throw "${PYTHON_BIN}"
  "${PYTHON_BIN}" -m pip --version >/dev/null 2>&1 || err "pip not available for: ${PYTHON_BIN} (install python3-pip)"

  log "[ml] TensorRT install: pip --user (PEP668 override via --break-system-packages)"

  local -a pip_args=(--user --break-system-packages)

  "${PYTHON_BIN}" -m pip install "${pip_args[@]}" --upgrade pip wheel setuptools

  if [[ -n "${TENSORRT_PIP_VERSION}" ]]; then
    "${PYTHON_BIN}" -m pip install "${pip_args[@]}" "tensorrt==${TENSORRT_PIP_VERSION}"
  else
    "${PYTHON_BIN}" -m pip install "${pip_args[@]}" "tensorrt"
  fi

  "${PYTHON_BIN}" - <<'PYCHK'
import sys
try:
    import tensorrt as trt
    print(f"[VERIFY] TensorRT Python version: {trt.__version__}")
    sys.exit(0)
except Exception as e:
    print(f"[ERROR] TensorRT import failed: {e}", file=sys.stderr)
    sys.exit(1)
PYCHK
}


ml_cuda_tensorrt_main "$@"
