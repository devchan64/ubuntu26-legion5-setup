#!/usr/bin/env bash
# file: scripts/ml/setup-cuda-tensorrt.sh
# Ubuntu 24.04 (Noble)
# CUDA 13.0.2 (local repo .deb) + TensorRT (pip --user only) + optional drivers
#
# /** Domain: Contract: Fail-Fast: SideEffect: */
# Domain:
#   - CUDA는 NVIDIA local-repo(.deb) + pin(600) 플로우로만 설치한다.
#   - TensorRT는 항상 "pip --user"로만 설치한다(venv/apt 금지).
# Contract:
#   - Ubuntu 24.04만 지원한다.
#   - root로 직접 실행 금지(사용자 컨텍스트에서 실행; apt는 sudo 사용).
#   - 실패 시 CUDA APT 소스/키링/pin/캐시를 정리하고 즉시 종료한다.
# Fail-Fast:
#   - 전제조건 미충족/명령 실패 시 즉시 err(throw), 폴백 없음.
# SideEffect:
#   - apt repo(pin/로컬deb) 등록, apt 패키지 설치, pip --user 설치, 파일 생성/삭제.
set -Eeuo pipefail
set -o errtrace

ml_cuda_tensorrt_main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  ml_cuda_tensorrt_contract_validate_entry_or_throw
  if [[ "${VERSION_ID}" == 26.04 ]]; then
    # 26.04는 Ubuntu 공식 CUDA 패키지를 사용한다. 기존 로컬 저장소는 변경하지 않는다.
    [[ -z "${CUDA_LOCAL_DEB_URL:-}${CUDA_PIN_URL:-}${CUDA_LOCAL_REPO_DIR:-}" ]] \
      || err "26.04에서는 CUDA 로컬 저장소 설정을 사용할 수 없습니다."
    [[ "${INSTALL_NVIDIA_OPEN:-0}" == 0 && "${INSTALL_CUDA_DRIVERS:-0}" == 0 ]] \
      || err "26.04 NVIDIA 드라이버는 sys 명령으로 설치하세요."
    sudo_run_or_throw apt-get update
    sudo_run_or_throw apt-get install -y "${CUDA_TOOLKIT_PKG:-cuda-toolkit}" python3-pip
    PYTHON_BIN="${PYTHON_BIN:-python3}"
    TENSORRT_PIP_VERSION="${TENSORRT_PIP_VERSION:-}"
    ml_cuda_tensorrt_install_tensorrt_pip_user_or_throw
    must_cmd_or_throw nvcc
    nvcc --version
    log "[ml] Ubuntu 26.04 CUDA 및 TensorRT 설치 완료"
    return
  fi
  ml_cuda_tensorrt_trap_install_cleanup_on_error

  ml_cuda_tensorrt_execute_or_throw
  log "[ml] cuda+tensorrt done"
}

# ─────────────────────────────────────────────────────────────
# Top: Business
# ─────────────────────────────────────────────────────────────
ml_cuda_tensorrt_contract_validate_entry_or_throw() {
  ml_cuda_tensorrt_contract_reject_root_or_throw
  require_supported_ubuntu_or_throw

  must_cmd_or_throw sudo
  must_cmd_or_throw curl
  must_cmd_or_throw dpkg
  must_cmd_or_throw apt-get
  must_cmd_or_throw awk
  must_cmd_or_throw grep

  ensure_sudo_auth_or_throw
}

ml_cuda_tensorrt_execute_or_throw() {
  # SSOT: defaults
  ml_cuda_tensorrt_config_defaults

  ml_cuda_tensorrt_log_driver_state_best_effort

  ml_cuda_tensorrt_maybe_install_driver_packages_or_throw

  ml_cuda_tensorrt_install_cuda_local_repo_or_throw
  ml_cuda_tensorrt_install_cuda_toolkit_or_throw

  ml_cuda_tensorrt_install_tensorrt_pip_user_or_throw
  ml_cuda_tensorrt_verify_installations_best_effort
  ml_cuda_tensorrt_print_env_guide_best_effort
}

# ─────────────────────────────────────────────────────────────
# Mid: Adapters / IO
# ─────────────────────────────────────────────────────────────
ml_cuda_tensorrt_config_defaults() {
  # CUDA 13.0.2 local repo defaults (Ubuntu 24.04, driver 580.95.05)
  CUDA_PIN_URL="${CUDA_PIN_URL:-https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin}"
  CUDA_LOCAL_DEB_URL="${CUDA_LOCAL_DEB_URL:-https://developer.download.nvidia.com/compute/cuda/13.0.2/local_installers/cuda-repo-ubuntu2404-13-0-local_13.0.2-580.95.05-1_amd64.deb}"
  CUDA_LOCAL_REPO_DIR_DEFAULT="/var/cuda-repo-ubuntu2404-13-0-local"
  CUDA_TOOLKIT_PKG="${CUDA_TOOLKIT_PKG:-cuda-toolkit-13-0}"

  # Optional drivers (OFF by default; explicit enable only)
  INSTALL_NVIDIA_OPEN="${INSTALL_NVIDIA_OPEN:-0}"     # 1 => apt install nvidia-open
  INSTALL_CUDA_DRIVERS="${INSTALL_CUDA_DRIVERS:-0}"   # 1 => apt install cuda-drivers

  # TensorRT (pip --user only)
  TENSORRT_PIP_VERSION="${TENSORRT_PIP_VERSION:-}"    # e.g., 10.2.0 (empty = latest)
  PYTHON_BIN="${PYTHON_BIN:-python3}"

  # Non-interactive APT
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  # Download dir (resume) — avoid $HOME/Downloads under sudo/root
  local dl_root="${PROJECT_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/ubuntu26-legion5-setup}/downloads"
  DOWNLOAD_DIR="${DOWNLOAD_DIR:-${dl_root}/cuda}"
  mkdir -p "${DOWNLOAD_DIR}"
}

ml_cuda_tensorrt_log_driver_state_best_effort() {
  log "[ml] NVIDIA driver state (best-effort)"
  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
      local drv
      drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)"
      log "[ml] nvidia-smi OK (driver=${drv:-unknown})"
      return 0
    fi
    warn "[ml] nvidia-smi exists but failed (driver not loaded?)"
  else
    warn "[ml] nvidia-smi not found"
  fi
}

ml_cuda_tensorrt_maybe_install_driver_packages_or_throw() {
  if [[ "${INSTALL_NVIDIA_OPEN}" != "1" && "${INSTALL_CUDA_DRIVERS}" != "1" ]]; then
    log "[ml] driver packages: skipped (explicit enable only)"
    return 0
  fi

  log "[ml] driver packages install requested"
  sudo_run_or_throw apt-get update -y

  if [[ "${INSTALL_NVIDIA_OPEN}" == "1" ]]; then
    log "[ml] install: nvidia-open"
    sudo_run_or_throw apt-get install -y nvidia-open
  fi

  if [[ "${INSTALL_CUDA_DRIVERS}" == "1" ]]; then
    log "[ml] install: cuda-drivers"
    sudo_run_or_throw apt-get install -y cuda-drivers
  fi

  warn "[ml] driver packages installed/updated; reboot may be required"
}

ml_cuda_tensorrt_install_cuda_local_repo_or_throw() {
  log "[ml] CUDA local repo setup (pin + local deb)"

  ml_cuda_tensorrt_purge_cuda_apt_sources_best_effort

  local pin_tmp="${DOWNLOAD_DIR}/$(basename "${CUDA_PIN_URL}")"
  ml_cuda_tensorrt_download_resume_or_throw "${CUDA_PIN_URL}" "${pin_tmp}"
  sudo_run_or_throw mv -f "${pin_tmp}" /etc/apt/preferences.d/cuda-repository-pin-600
  sudo_run_or_throw chmod 0644 /etc/apt/preferences.d/cuda-repository-pin-600

  local deb_tmp="${DOWNLOAD_DIR}/$(basename "${CUDA_LOCAL_DEB_URL}")"
  ml_cuda_tensorrt_download_resume_or_throw "${CUDA_LOCAL_DEB_URL}" "${deb_tmp}"
  sudo_run_or_throw dpkg -i "${deb_tmp}"

  local repo_dir="${CUDA_LOCAL_REPO_DIR:-${CUDA_LOCAL_REPO_DIR_DEFAULT}}"
  [[ -d "${repo_dir}" ]] || err "cuda local repo dir not found: ${repo_dir}"

  sudo_run_or_throw cp "${repo_dir}"/cuda-*-keyring.gpg /usr/share/keyrings/ \
    || err "failed to copy cuda keyring from: ${repo_dir}"

  sudo_run_or_throw apt-get update -y
}

ml_cuda_tensorrt_install_cuda_toolkit_or_throw() {
  log "[ml] CUDA toolkit install: ${CUDA_TOOLKIT_PKG}"

  local cand_ver=""
  cand_ver="$(LC_ALL=C apt-cache policy "${CUDA_TOOLKIT_PKG}" | awk -F': ' '/^  Candidate:|^Candidate:/ {print $2; exit}' || true)"
  if [[ -z "${cand_ver}" || "${cand_ver}" == "(none)" ]]; then
    warn "[ml] no candidate for: ${CUDA_TOOLKIT_PKG}"
    warn "[ml] hint: available meta packages (best-effort):"
    apt-cache search -n '^cuda-toolkit-[0-9]+-[0-9]+$' 2>/dev/null | awk '{print "  - "$1}' >&2 || true
    err "CUDA toolkit candidate not found: ${CUDA_TOOLKIT_PKG}"
  fi

  log "[ml] candidate: ${cand_ver}"
  sudo_run_or_throw apt-get install -y --no-install-recommends "${CUDA_TOOLKIT_PKG}"
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

ml_cuda_tensorrt_verify_installations_best_effort() {
  log "[ml] verify (best-effort)"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || true
  fi
  if command -v nvcc >/dev/null 2>&1; then
    nvcc --version || true
  else
    warn "[ml] nvcc not found (PATH may need CUDA_HOME/bin)"
  fi

  if ! echo "${PATH}" | grep -q "${HOME}/.local/bin"; then
    warn "[ml] ~/.local/bin not in PATH (pip --user scripts may be missing)"
    warn "[ml] add: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

ml_cuda_tensorrt_print_env_guide_best_effort() {
  local cuda_home="/usr/local/cuda"
  if [[ -d "${cuda_home}" ]]; then
    cat <<EOF
[GUIDE] shell env (e.g., ~/.bashrc):
  export CUDA_HOME=${cuda_home}
  export PATH="\$CUDA_HOME/bin:\$PATH"
  export LD_LIBRARY_PATH="\$CUDA_HOME/lib64:\${LD_LIBRARY_PATH:-}"
EOF
  fi
}

ml_cuda_tensorrt_download_resume_or_throw() {
  local url="${1:?url required}"
  local dest="${2:?dest required}"
  log "[ml] download (resume): ${url}"
  curl -fL --retry 3 --retry-all-errors -C - -o "${dest}" "${url}"
  [[ -f "${dest}" ]] || err "download failed (missing file): ${dest}"
}

# ─────────────────────────────────────────────────────────────
# Bottom: Contract / Cleanup
# ─────────────────────────────────────────────────────────────
ml_cuda_tensorrt_contract_reject_root_or_throw() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    err "do not run as root (run as desktop user; apt will use sudo)"
  fi
}

ml_cuda_tensorrt_trap_install_cleanup_on_error() {
  trap 'ml_cuda_tensorrt_cleanup_cuda_apt_on_error "$?" "$BASH_COMMAND"' ERR
}

ml_cuda_tensorrt_cleanup_cuda_apt_on_error() {
  local ec="${1:?exit_code required}"
  local failed_cmd="${2:-unknown}"

  echo >&2
  echo "------------------------------------" >&2
  echo "[CLEANUP] CUDA APT/Keyring cleanup (exit=${ec})" >&2
  echo "[CLEANUP] failed command: ${failed_cmd}" >&2

  ml_cuda_tensorrt_purge_cuda_apt_sources_best_effort || true
  sudo_run_or_throw apt-get clean || true
  sudo_run_or_throw rm -rf /var/lib/apt/lists/* || true

  echo "[CLEANUP] done. check network/proxy then rerun." >&2
  echo "------------------------------------" >&2

  exit "${ec}"
}

ml_cuda_tensorrt_purge_cuda_apt_sources_best_effort() {
  sudo_run_or_throw rm -f \
    /etc/apt/sources.list.d/cuda-*.list \
    /etc/apt/sources.list.d/nvidia*cuda*.list \
    /etc/apt/sources.list.d/*cuda*.list \
    /usr/share/keyrings/cuda-archive-keyring.gpg \
    /etc/apt/preferences.d/cuda-repository-pin-600 \
    || true
}

ml_cuda_tensorrt_main "$@"

# [ReleaseNote] breaking: reject root; use sudo+PROJECT_STATE_DIR downloads; unify logging/contract/cleanup
