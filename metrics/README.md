# 指标采集（学术口径 / 可画曲线 / 低复现成本）

本目录提供一套**可复核、可脚本化、可生成曲线**的指标采集方法，用于 ApexMQTT 的吞吐/延迟/C1M 实验。

核心原则：

- **主口径使用 Linux 内核计数器**（/proc），而不是 UI 工具（如 `nload`、`htop`）。
- 采集输出为 **时间序列 CSV**，便于画曲线与复核。
- 速率（bytes/s、pps 等）由**相邻采样点差分**得到（monotonic counters → rates）。

## 采集哪些数据（默认全部进 CSV）

来自内核与系统的“公识口径”：

- **网卡 bytes/packets**：`/proc/net/dev`
- **上下文切换 / 中断总数**：`/proc/stat`（`ctxt`、`intr`）
- **softirq（NET_RX / NET_TX）**：`/proc/softirqs`
- **TCP In/Out/Retrans Segs**：`/proc/net/snmp`（`InSegs`/`OutSegs`/`RetransSegs`）
- **连接数（ESTAB）**：`ss`（仅 Broker 脚本采集）
- **进程 RSS/VSZ**：`ps`（仅 Broker 脚本可选采集）

## 依赖（Ubuntu 24.04）

本目录脚本默认只依赖系统自带工具（`bash`/`awk`/`ss`/`ps`）。

如果你希望同时记录 CPU/softirq 的标准报表，可安装 `sysstat`（可选）：

```bash
sudo apt-get update
sudo apt-get install -y sysstat
```

## 三台机器分别怎么采（建议）

先启动采集，再开始压测；压测结束后再停止采集并做后处理。

### 1) Broker (SUT) 上采集（吞吐/连接数/内核网络压力）

```bash
PID=$(pgrep ApexMQTT | head -n 1)
# EXP_TAG 用于把“这次实验是什么”编码进目录名，便于归档与画图（强烈建议）
# 例：A-axmq-qos0-256-1to10 或 B-emqx-qos2-4096-m2m
EXP_TAG="A-axmq-qos0-256-1to10" INTERFACE=eth0 PORT=1883 PID="${PID}" INTERVAL_SEC=1 ./bin/metrics/collect_broker.sh
```

### 2) LoadGen (Tester) 上采集（证明负载机不饱和 + 证明探测隔离）

```bash
EXP_TAG="A-axmq-qos0-256-1to10" INTERFACE=eth0 INTERVAL_SEC=1 ./bin/metrics/collect_loadgen.sh
```

### 3) Prober (Latency Probe) 上采集（证明 P99 探测端未被污染）

```bash
EXP_TAG="A-axmq-qos0-256-1to10" INTERFACE=eth0 INTERVAL_SEC=1 ./bin/metrics/collect_prober.sh
```

## 输出与后处理

每次运行会生成一个目录（按 UTC 时间戳）：

- `bin/metrics/runs/<role>-<timestamp>/raw.csv`：单调计数器时间序列
- `bin/metrics/runs/<role>-<timestamp>/meta.txt`：环境信息（用于复现与审稿复核）

将 `raw.csv` 转为可画曲线的 `rates.csv`：

```bash
python3 ./bin/metrics/postprocess_rates.py bin/metrics/runs/<role>-<timestamp>/raw.csv
```

输出：

- `rates.csv`：所有“单调列”都会生成 `<col>_per_s`，例如：
  - `tx_bytes_per_s`（带宽）
  - `tx_packets_per_s`（PPS）
  - `tcp_retranssegs_per_s`（重传速率）
  - `ctxt_per_s`（上下文切换速率）
  - `softirq_net_rx_per_s` / `softirq_net_tx_per_s`

## 采样时长控制（可选）

采集脚本支持用环境变量限制采集时长：

- `DURATION_SEC=300`：采集 300 秒后自动退出（例如 5 分钟稳态测试）
- `INTERVAL_SEC=1`：每秒采样一次（建议默认 1）

示例（采集 5 分钟）：

```bash
EXP_TAG="A-axmq-qos0-256-1to10-run1" DURATION_SEC=300 INTERVAL_SEC=1 ./bin/metrics/collect_loadgen.sh
```

## 数据存放位置（你最终会“收集到哪里”）

采集脚本的默认落盘位置是**相对仓库根目录**的：

- `bin/metrics/runs/`

目录命名规则：

- `<role>`：`broker` / `loadgen` / `prober`
- `<timestamp>`：UTC 时间戳（例如 `20251230T012345Z`）

因此一次完整实验通常会在三台机器分别生成三个目录，例如：

- Broker 上：`bin/metrics/runs/broker-20251230T012345Z/`
- LoadGen 上：`bin/metrics/runs/loadgen-20251230T012345Z/`
- Prober 上：`bin/metrics/runs/prober-20251230T012345Z/`

每个目录包含：

- `meta.txt`：环境信息（机器/内核/路由/关键 sysctl 片段）
- `raw-<run_id>.csv`：原始单调计数器时间序列（**文件名可直接看出实验点**）
- `rates-<run_id>.csv`：由 `postprocess_rates.py` 生成的速率时间序列（**文件名可直接看出实验点**）
- `meta-<run_id>.txt`：环境信息副本（文件名含实验点，便于归档/AI 分析）

同时脚本也会生成固定文件名（便于人工快速打开）：

- `raw.csv`（与 `raw-<run_id>.csv` 同内容）
- `rates.csv`（若你对 `raw.csv` 做后处理）

### 推荐的汇总方式（便于画图与归档）

为了把三台机器的数据放到同一台电脑统一画图，建议在你的本地/分析机建立一个实验目录（举例）：

- `~/axmq-data/exp-<实验名>-<日期>/`
  - `broker/`（拷贝 Broker 的整个 run 目录）
  - `loadgen/`
  - `prober/`

拷贝策略建议“整目录拷贝”，确保 `meta.txt` 与原始 `raw.csv` 一并留存，便于后续复核与追溯。


