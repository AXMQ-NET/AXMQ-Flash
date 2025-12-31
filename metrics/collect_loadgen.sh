#!/usr/bin/env bash
set -euo pipefail

# LoadGen collector (optional but recommended for methodology):
# - proves load generator saturation isn't the bottleneck
# - helps justify that Prober isolation removes measurement contamination

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=collect_common.sh
source "${SCRIPT_DIR}/collect_common.sh"

require_cmd awk

INTERFACE="${INTERFACE:-eth0}"
INTERVAL_SEC="${INTERVAL_SEC:-1}"
DURATION_SEC="${DURATION_SEC:-0}"  # 0 => run forever

OUTDIR="$(mk_outdir "loadgen")"
write_meta "${OUTDIR}"

RUN_ID="$(basename "${OUTDIR}")"
RAW="${OUTDIR}/raw-${RUN_ID}.csv"
RAW_LATEST="${OUTDIR}/raw.csv"

echo "time_utc,iface,rx_bytes,rx_packets,tx_bytes,tx_packets,ctxt,intr,softirq_net_rx,softirq_net_tx,tcp_insegs,tcp_outsegs,tcp_retranssegs" > "${RAW}"
cp -f "${RAW}" "${RAW_LATEST}"

start_ts="$(date +%s)"
while true; do
  t="$(now_utc)"
  net="$(read_netdev_iface "${INTERFACE}")"
  ps1="$(read_proc_stat)"
  soft="$(read_softirqs_net)"
  tcp="$(read_tcp_snmp)"
  echo "${t},${INTERFACE},${net},${ps1},${soft},${tcp}" >> "${RAW}"
  echo "${t},${INTERFACE},${net},${ps1},${soft},${tcp}" >> "${RAW_LATEST}"

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


