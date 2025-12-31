#!/usr/bin/env bash
set -euo pipefail

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

mk_outdir() {
  local prefix="$1"
  local ts
  ts="$(date -u +"%Y%m%dT%H%M%SZ")"
  local tag="${EXP_TAG:-}"
  # 仅保留安全字符，避免目录名混乱
  if [[ -n "${tag}" ]]; then
    tag="$(echo "${tag}" | tr -cd 'A-Za-z0-9._-')"
  fi
  local dir="bin/metrics/runs/${prefix}${tag:+-${tag}}-${ts}"
  mkdir -p "${dir}"
  echo "${dir}"
}

write_meta() {
  local outdir="$1"
  {
    echo "time_utc=$(now_utc)"
    echo "hostname=$(hostname || true)"
    echo "uname=$(uname -a || true)"
    echo "kernel=$(uname -r || true)"
    echo "cpu_count=$(nproc 2>/dev/null || true)"
    echo "ip_addr="
    (ip addr show || true)
    echo
    echo "ip_route="
    (ip route show || true)
    echo
    echo "sysctl_selected="
    (sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.core.netdev_max_backlog 2>/dev/null || true)
    (sysctl net.core.rmem_default net.core.wmem_default net.ipv4.tcp_rmem net.ipv4.tcp_wmem 2>/dev/null || true)
  } > "${outdir}/meta.txt"
}

require_cmd() {
  local c="$1"
  command -v "${c}" >/dev/null 2>&1 || {
    echo "missing command: ${c}" >&2
    exit 1
  }
}

# Read /proc/net/dev counters for one interface.
# Output: rx_bytes,rx_packets,tx_bytes,tx_packets
read_netdev_iface() {
  local iface="$1"
  # /proc/net/dev columns:
  # face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed
  awk -v ifc="${iface}:" '
    $1==ifc {
      rx_bytes=$2; rx_packets=$3;
      tx_bytes=$10; tx_packets=$11;
      print rx_bytes "," rx_packets "," tx_bytes "," tx_packets;
      exit
    }
  ' /proc/net/dev
}

# Read /proc/stat high-level counters (monotonic).
# Output: ctxt,intr
read_proc_stat() {
  awk '
    $1=="ctxt" { ctxt=$2 }
    $1=="intr" { intr=$2 }
    END { print ctxt "," intr }
  ' /proc/stat
}

# Read /proc/softirqs totals for NET_RX and NET_TX (monotonic).
# Output: net_rx,net_tx
read_softirqs_net() {
  awk '
    function sum_fields(start,   i,s) { s=0; for (i=start; i<=NF; i++) s += $i; return s }
    $1=="NET_RX:" { rx=sum_fields(2) }
    $1=="NET_TX:" { tx=sum_fields(2) }
    END { print rx+0 "," tx+0 }
  ' /proc/softirqs
}

# Read /proc/net/snmp TCP counters (monotonic).
# Output: TcpInSegs,TcpOutSegs,TcpRetransSegs
read_tcp_snmp() {
  awk '
    $1=="Tcp:" {
      if (stage==0) {
        for (i=2; i<=NF; i++) h[i]=$i
        stage=1
      } else if (stage==1) {
        for (i=2; i<=NF; i++) v[h[i]]=$i
        stage=2
      }
    }
    END {
      print (v["InSegs"]+0) "," (v["OutSegs"]+0) "," (v["RetransSegs"]+0)
    }
  ' /proc/net/snmp
}

# Best-effort TCP ESTAB count for a port (server-side).
tcp_estab_count() {
  local port="$1"
  # ss output can vary; this is intentionally simple.
  ss -ant 2>/dev/null | awk -v p=":${port}" '$1=="ESTAB" && $4 ~ p {c++} END{print c+0}'
}


