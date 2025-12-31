#!/usr/bin/env bash
set -euo pipefail

# Academic-grade Broker (SUT) collector.
# Writes monotonic counters to CSV (plot-ready after postprocess).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=collect_common.sh
source "${SCRIPT_DIR}/collect_common.sh"

require_cmd awk
require_cmd ss

INTERFACE="${INTERFACE:-eth0}"
PORT="${PORT:-1883}"
PID="${PID:-}"            # optional: ApexMQTT PID
INTERVAL_SEC="${INTERVAL_SEC:-1}"
DURATION_SEC="${DURATION_SEC:-0}"  # 0 => run forever

OUTDIR="$(mk_outdir "broker")"
write_meta "${OUTDIR}"

RUN_ID="$(basename "${OUTDIR}")"
RAW="${OUTDIR}/raw-${RUN_ID}.csv"
# 同时保留一个“固定文件名”便于人工查看
RAW_LATEST="${OUTDIR}/raw.csv"

echo "time_utc,iface,rx_bytes,rx_packets,tx_bytes,tx_packets,ctxt,intr,softirq_net_rx,softirq_net_tx,tcp_insegs,tcp_outsegs,tcp_retranssegs,tcp_estab,proc_rss_kb,proc_vsz_kb" > "${RAW}"
cp -f "${RAW}" "${RAW_LATEST}"

start_ts="$(date +%s)"
while true; do
  t="$(now_utc)"
  net="$(read_netdev_iface "${INTERFACE}")"
  ps1="$(read_proc_stat)"
  soft="$(read_softirqs_net)"
  tcp="$(read_tcp_snmp)"
  estab="$(tcp_estab_count "${PORT}")"

  rss_kb=""
  vsz_kb=""
  if [[ -n "${PID}" ]]; then
    # ps RSS/VSZ are in KB on Linux by default with these flags.
    read -r rss_kb vsz_kb < <(ps -o rss=,vsz= -p "${PID}" 2>/dev/null | awk '{print $1, $2}' || true)
  fi

  echo "${t},${INTERFACE},${net},${ps1},${soft},${tcp},${estab},${rss_kb},${vsz_kb}" >> "${RAW}"
  echo "${t},${INTERFACE},${net},${ps1},${soft},${tcp},${estab},${rss_kb},${vsz_kb}" >> "${RAW_LATEST}"

  if [[ "${DURATION_SEC}" != "0" ]]; then
    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= DURATION_SEC )); then
      break
    fi
  fi

  sleep "${INTERVAL_SEC}"
done

cp -f "${OUTDIR}/meta.txt" "${OUTDIR}/meta-${RUN_ID}.txt" 2>/dev/null || true
echo "Wrote: ${RAW}"
echo "Next: python3 ${SCRIPT_DIR}/postprocess_rates.py ${RAW}"


