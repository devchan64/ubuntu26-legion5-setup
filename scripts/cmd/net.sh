#!/usr/bin/env bash
# file: scripts/cmd/net.sh
set -Eeuo pipefail
set -o errtrace

net_main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  local resume_scope="${RESUME_SCOPE_KEY:-cmd:net}"

  resume_step "${resume_scope}" "net:tools:install" \
    -- \
    must_run_or_throw "scripts/net/tools-install.sh"

  log "[net] GUI 파일 탐색기: python3 ${root_dir}/scripts/net/file-explorer.py"
  log "[net] done"
}

net_main "$@"
