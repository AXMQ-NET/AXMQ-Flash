#!/usr/bin/env python3
import csv
import sys
from datetime import datetime, timezone
from pathlib import Path


def parse_time_utc(s: str) -> float:
    # Expects RFC3339-like: 2025-12-29T12:34:56Z
    dt = datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return dt.timestamp()


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <raw.csv>", file=sys.stderr)
        return 2

    raw_path = sys.argv[1]
    p = Path(raw_path)
    name = p.name
    if name == "raw.csv":
        out_name = "rates.csv"
    elif name.startswith("raw-"):
        out_name = "rates-" + name[len("raw-") :]
    else:
        out_name = name + ".rates.csv"
    out_path = str(p.with_name(out_name))

    with open(raw_path, newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if len(rows) < 2:
        print("not enough samples to compute rates (need >= 2)", file=sys.stderr)
        return 1

    # Columns that should be treated as gauges (not differenced).
    gauge_cols = {"time_utc", "iface", "tcp_estab", "proc_rss_kb", "proc_vsz_kb"}

    # All numeric counter columns (monotonic) will be differenced into *_per_s.
    header = list(rows[0].keys())
    counter_cols = [c for c in header if c not in gauge_cols]

    out_fields = ["time_utc", "iface"]
    for c in counter_cols:
        out_fields.append(f"{c}_per_s")
    # Preserve gauges if present.
    for g in ["tcp_estab", "proc_rss_kb", "proc_vsz_kb"]:
        if g in header:
            out_fields.append(g)

    with open(out_path, "w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=out_fields)
        writer.writeheader()

        prev = rows[0]
        prev_t = parse_time_utc(prev["time_utc"])
        for cur in rows[1:]:
            cur_t = parse_time_utc(cur["time_utc"])
            dt = cur_t - prev_t
            if dt <= 0:
                prev = cur
                prev_t = cur_t
                continue

            def as_int(row: dict, key: str) -> int:
                v = (row.get(key, "") or "0").strip()
                if v == "":
                    return 0
                try:
                    return int(v)
                except ValueError:
                    return 0

            out_row = {"time_utc": cur["time_utc"], "iface": cur.get("iface", "")}
            for c in counter_cols:
                dv = as_int(cur, c) - as_int(prev, c)
                out_row[f"{c}_per_s"] = f"{(dv / dt):.2f}"

            # Gauges
            for g in ["tcp_estab", "proc_rss_kb", "proc_vsz_kb"]:
                if g in header:
                    out_row[g] = cur.get(g, "")

            writer.writerow(out_row)

            prev = cur
            prev_t = cur_t

    print(f"Wrote: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


