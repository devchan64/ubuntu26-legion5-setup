#!/usr/bin/env bash
# file: scripts/net/tools-install.sh
# Network diagnostics/tooling bundle (Ubuntu 26.04)
# Policy: no fallbacks, fail-fast
set -Eeuo pipefail
set -o errtrace

main() {
  local root_dir="${LEGION_SETUP_ROOT:?LEGION_SETUP_ROOT required}"
  # shellcheck disable=SC1090
  source "${root_dir}/lib/common.sh"

  ensure_sudo_auth_or_throw

  require_supported_ubuntu_or_throw
  must_cmd_or_throw apt-get

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  # SideEffect: apt sources may be rewritten (repo/keyring singleton)
  apt_fix_vscode_repo_singleton

  local -a pkgs=(
    # basic networking / transport
    curl
    wget
    iproute2
    iputils-ping
    net-tools
    ethtool
    whois
    traceroute
    mtr-tiny
    tcpdump
    nmap

    # DNS / resolver tools
    bind9-dnsutils

    # perf / throughput
    iperf3

    # HTTP client
    httpie

    # Wi-Fi (legacy helper)
    wireless-tools
  )

  log "[net] install packages"
  sudo_run_or_throw apt-get update -y
  sudo_run_or_throw apt-get install -y --no-install-recommends "${pkgs[@]}"

  net_tools_contract_validate_binaries_or_throw
  net_tools_log_versions_best_effort

  log "[net] done"
  net_tools_print_quick_tips
}

# ─────────────────────────────────────────────────────────────
# Business: contract validation
# ─────────────────────────────────────────────────────────────
net_tools_contract_validate_binaries_or_throw() {
  local check_cmd=""
  check_cmd() { command -v "$1" >/dev/null 2>&1 || err "missing command after install: $1"; }

  check_cmd ip
  check_cmd ss
  check_cmd ping
  check_cmd dig
  check_cmd traceroute
  check_cmd mtr
  check_cmd tcpdump
  check_cmd nmap
  check_cmd iperf3
  check_cmd curl
  check_cmd http
}

# ─────────────────────────────────────────────────────────────
# IO: best-effort logging
# ─────────────────────────────────────────────────────────────
net_tools_log_versions_best_effort() {
  {
    log "[net] iproute2: $(ip -V || true)"
    log "[net] ping: $(ping -V 2>&1 | head -n1 || true)"
    log "[net] dig: $(dig +short -v 2>&1 | head -n1 || true)"
    log "[net] traceroute: $(traceroute --version 2>&1 | head -n1 || true)"
    log "[net] mtr: $(mtr --version 2>&1 | head -n1 || true)"
    log "[net] tcpdump: $(tcpdump --version 2>&1 | head -n1 || true)"
    log "[net] nmap: $(nmap --version 2>&1 | head -n1 || true)"
    log "[net] iperf3: $(iperf3 --version 2>&1 | head -n1 || true)"
    log "[net] curl: $(curl --version 2>/dev/null | head -n1 || true)"
    log "[net] httpie: $(http --version 2>&1 | head -n1 || true)"
  } || true
}

net_tools_print_quick_tips() {
  cat <<'TIP'
[Quick usage]
  • IP/route:        ip a    | ip r
  • sockets/ports:   ss -tulpn
  • DNS:             dig example.com +trace
  • traceroute:      traceroute 8.8.8.8
  • latency (mtr):   mtr -rw 1.1.1.1
  • capture:         sudo tcpdump -i any -nn port 443
  • scan:            nmap -sV -Pn example.com
  • bandwidth:       iperf3 -s  / iperf3 -c <server-ip>
  • HTTP:            http GET https://example.com
TIP
}

main "$@"
