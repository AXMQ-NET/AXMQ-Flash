import os
import csv
from datetime import datetime

def process_file(file_path):
    with open(file_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        return None

    data = []
    for i in range(1, len(rows)):
        try:
            t1 = datetime.strptime(rows[i-1]['time_utc'], '%Y-%m-%dT%H:%M:%SZ')
            t2 = datetime.strptime(rows[i]['time_utc'], '%Y-%m-%dT%H:%M:%SZ')
            dt = (t2 - t1).total_seconds()
            if dt == 0: continue
            
            ctxt_rate = (float(rows[i]['ctxt']) - float(rows[i-1]['ctxt'])) / dt
            data.append({
                'rss': float(rows[i]['proc_rss_kb']) / 1024.0,
                'vsz': float(rows[i]['proc_vsz_kb']) / 1024.0,
                'ctxt_rate': ctxt_rate,
                'estab': int(rows[i]['tcp_estab'])
            })
        except:
            continue

    if not data: return None

    # Steady state average (skip 20% start and 10% end)
    n = len(data)
    steady = data[int(n*0.2):int(n*0.9)]
    if not steady: steady = data

    avg_rss = sum(d['rss'] for d in steady) / len(steady)
    avg_vsz = sum(d['vsz'] for d in steady) / len(steady)
    avg_ctxt = sum(d['ctxt_rate'] for d in steady) / len(steady)
    max_conn = max(d['estab'] for d in steady)

    return {
        'avg_rss': avg_rss,
        'avg_vsz': avg_vsz,
        'avg_ctxt': avg_ctxt,
        'max_conn': max_conn
    }

runs_dir = "bin/metrics/runs"
brokers = ["ApexMQTT", "EMQX"]
scales = ["Baseline", "100k", "500k", "1M"]
table = {}

# CRITICAL: sort to ensure latest folder (by timestamp) processes last
for run_folder in sorted(os.listdir(runs_dir)):
    raw_path = os.path.join(runs_dir, run_folder, "raw.csv")
    if os.path.exists(raw_path):
        broker = "ApexMQTT" if "axmq" in run_folder else "EMQX"
        scale = "Baseline"
        if "100k" in run_folder: scale = "100k"
        elif "500k" in run_folder: scale = "500k"
        elif "1000k" in run_folder: scale = "1M"
        
        stats = process_file(raw_path)
        if stats:
            if broker not in table: table[broker] = {}
            table[broker][scale] = stats

print("| Broker | Scale | RSS (MB) | VSZ (MB) | Ctxt/s | Conn |")
print("| :--- | :--- | :--- | :--- | :--- | :--- |")
for b in brokers:
    for s in scales:
        if b in table and s in table[b]:
            st = table[b][s]
            print(f"| {b} | {s} | {st['avg_rss']:.2f} | {st['avg_vsz']:.2f} | {st['avg_ctxt']:.0f} | {st['max_conn']} |")
