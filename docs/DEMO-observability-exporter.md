# NSO Observability Exporter — Demo Guide

> **Goal**: Walk through the Cisco NSO Observability Exporter end-to-end — from
> installation to live traces in Jaeger, metrics in InfluxDB/Prometheus, and
> dashboards in Grafana — using the dockerised lab in this repo.

---

## 0 — Set up the environment

### 0.1 Clone and configure

```shell
git clone <repo-url> && cd NSO-docker
cp .env.example .env
```

### 0.2 Place NSO images, NEDs and packages

Either pre-load images manually:

```shell
docker load -i nso-6.6.1.container-image-prod.tar.gz
docker load -i nso-6.6.1.container-image-dev.tar.gz
```

*Or place the `.tar.gz` tarballs in `images/` and `make build` will load them automatically.*

Drop NED `.signed.bin` files into `neds/`:

```shell
cp ncs-6.6.1-cisco-ios-6.112.signed.bin neds/
cp ncs-6.6.1-cisco-iosxr-7.74.11.signed.bin neds/
cp ncs-6.6.1-juniper-junos-4.18.30.signed.bin neds/
```

For the observability stack, extract the Observability Exporter package into `packages/`:

```shell
tar -xzf ncs-6.6.1-observability-exporter-1.6.0.tar.gz -C packages/
```

### 0.3 Build and run

```bash
make build       # Compile packages inside the build container
make up-all      # Full stack: NSO + Netsim + Observability
```

### 0.4 Verify all containers are running

```bash
docker compose -f compose.yaml -f compose.netsim.yaml -f compose.observability.yaml ps
```

All services should show **healthy** / **running**:
`nso`, `netsim`, `otel-collector`, `jaeger`, `influxdb`, `prometheus`, `grafana`.

### 0.5 Access services

| Service                  | URL / Command                                      | Credentials      |
| ------------------------ | -------------------------------------------------- | ----------------- |
| NSO Web UI               | [http://localhost:8080](http://localhost:8080)      | `admin` / `admin` |
| NSO CLI                  | `make cli`                                         | —                 |
| Jaeger (traces)          | [http://localhost:16686](http://localhost:16686)    | —                 |
| Grafana (dashboards)     | [http://localhost:3000](http://localhost:3000)      | Anonymous access  |
| Prometheus (metrics)     | [http://localhost:9090](http://localhost:9090)      | —                 |
| InfluxDB                 | [http://localhost:8086](http://localhost:8086)      | See `.env`        |

---

## 1 — Understand what the Observability Exporter does

The **Observability Exporter (OE)** is an NSO add-on package that exports observability data using industry-standard formats and protocols. It plugs into NSO's built-in **progress trace** mechanism and ships data out via two channels:

| Channel | What it exports | Where it goes |
| ------- | --------------- | ------------- |
| **OTLP** (OpenTelemetry Protocol) | Transaction **traces** (spans) and optional **gauge/counter metrics** | OpenTelemetry Collector → Jaeger, Prometheus, etc. |
| **InfluxDB** (v1 API) | Derived **transaction metrics** (span durations, counts, lock times) | InfluxDB → Grafana dashboards |

### 1.1 The three pillars of observability

| Pillar | Purpose | Tool in this stack |
| ------ | ------- | ------------------ |
| **Traces** | Follow a single transaction through every phase of NSO (validation, service create, push config, etc.) | Jaeger |
| **Metrics** | Aggregate numeric data — throughput, duration averages, lock contention | InfluxDB + Prometheus via Grafana |
| **Logs** | Detailed per-subsystem diagnostic text | NSO logs (not covered by OE, but complements it) |

### 1.2 InfluxDB measurements exported by the OE

The OE calculates and exports **four measurement types** into InfluxDB:

| Measurement | Description |
| ----------- | ----------- |
| `span` | Duration and metadata for each individual phase (span) of a transaction |
| `span-count` | Number of concurrent spans — e.g. how many transactions are in the *prepare* phase simultaneously |
| `transaction` | Cumulative span durations per transaction — e.g. total time spent in *service create* across all services in one commit |
| `transaction-lock` | Details about the transaction lock — queue length when acquiring or releasing the lock |

---

## 2 — Verify the Observability Exporter installation

### 2.1 Check the package is loaded

```
make cli
```

Inside the NSO CLI:

```
admin@ncs# show packages package observability-exporter
```

Expected output includes `oper-status up` and the package version.

### 2.2 Show the running configuration

The `progress` node is not visible in the standard NSO CLI tree. Use `ncs_load` to dump it:

```bash
docker exec nso-docker-nso-1 ncs_load -Fxml -p /progress/export
```

Or query individual values from the NSO CLI:

```
admin@ncs# progress export enabled
admin@ncs# progress export otlp host
```

You should see the config that was auto-loaded from `init/observability-exporter-config.xml`:

```xml
<progress xmlns="http://tail-f.com/ns/progress">
  <export xmlns="http://tail-f.com/ns/observability-exporter">
    <enabled>true</enabled>
    <influxdb>
      <host>influxdb</host>
      <port>8086</port>
      <username>nso</username>
      <password>$9$...</password>
    </influxdb>
    <otlp>
      <host>otel-collector</host>
      <port>4318</port>
      <transport>http</transport>
      <metrics>
        <host>otel-collector</host>
        <port>4318</port>
      </metrics>
    </otlp>
    <jaeger-base-url>http://localhost:16686/</jaeger-base-url>
  </export>
</progress>
```

Key points to call out:

- **`enabled true`** — the exporter is active.
- **OTLP** → sends traces to `otel-collector:4318` over HTTP. The OTel Collector then forwards to Jaeger and Prometheus.
- **InfluxDB** → sends derived metrics directly to `influxdb:8086`.
- **`jaeger-base-url`** — makes the NSO commit annotation include a clickable link to the Jaeger trace.
- **OTLP metrics** → also enabled, the OE pushes gauge/counter metrics over OTLP to the collector which exposes them for Prometheus scraping.

---

## 3 — Explore the architecture (data flow)

Explain the data pipeline to the audience:

```
NSO (Observability Exporter)
 ├── OTLP traces  ──► OTel Collector ──► Jaeger     (trace visualisation)
 ├── OTLP metrics ──► OTel Collector ──► Prometheus  (metric scraping)
 └── InfluxDB API ──► InfluxDB       ──► Grafana     (dashboards)
                                          ▲
                     Prometheus ──────────┘ (also a Grafana datasource)
```

### 3.1 Show the OTel Collector config

The file `config/otelcol.yaml` wires it together:

- **Receivers**: OTLP on gRPC (`:4317`) and HTTP (`:4318`).
- **Exporters**: traces → Jaeger via OTLP; metrics → Prometheus exporter on `:9464`.
- **Processor**: batch (2 s window, 512 batch size).

### 3.2 Show the Prometheus scrape config

The file `config/prometheus/prometheus.yml` scrapes the OTel Collector's Prometheus endpoint:

```yaml
- job_name: nso-metrics
  static_configs:
    - targets:
        - otel-collector:9464
```

---

## 4 — Generate transaction traces

Traces only appear when NSO processes transactions. Let's generate some.

### 4.1 Trivial configuration change (quick smoke test)

```
make cli
```

```
admin@ncs# config
admin@ncs(config)# session idle-timeout 100001
admin@ncs(config)# commit
admin@ncs(config)# end
```

### 4.2 Fetch SSH keys from netsim devices

```
admin@ncs# devices fetch-ssh-host-keys
```

### 4.3 Sync config from devices

```
admin@ncs# devices sync-from
```

### 4.4 Deploy a loopback-demo service instance

This generates a realistic multi-phase transaction (validation → service create → device push):

```
admin@ncs# config
admin@ncs(config)# services loopback-demo test1 device ios-0 loopback-number 1100 ip-address 10.100.1.1
admin@ncs(config-loopback-demo-test1)# commit dry-run outformat native
admin@ncs(config-loopback-demo-test1)# commit
admin@ncs(config-loopback-demo-test1)# end
```

### 4.5 Deploy more service instances (bulk activity)

```
admin@ncs# config
admin@ncs(config)# services loopback-demo test2 device ios-1 loopback-number 1101 ip-address 10.100.2.1
admin@ncs(config-loopback-demo-test2)# top
admin@ncs(config)# services loopback-demo test3 device iosxr-0 loopback-number 1102 ip-address 10.100.3.1
admin@ncs(config-loopback-demo-test3)# commit
admin@ncs(config-loopback-demo-test3)# end
```

### 4.6 Re-deploy a service (shows a re-deploy trace)

```
admin@ncs# services loopback-demo test1 re-deploy
```

### 4.7 Delete a service

```
admin@ncs# config
admin@ncs(config)# no services loopback-demo test3
admin@ncs(config)# commit
admin@ncs(config)# end
```

---

## 5 — Explore traces in Jaeger

Open [http://localhost:16686](http://localhost:16686).

### 5.1 Find traces

1. In the **Service** dropdown, select **NSO**.
2. Click **Find Traces**.
3. You will see a list of recent transactions — each one corresponds to a `commit` you performed.

### 5.2 Inspect a single trace

Click on one of the traces (e.g. the loopback-demo commit). You will see:

- **Spans** arranged as a timeline waterfall.
- Each span represents a phase of the transaction — examples:
  - `creating service` — the service create callback (FASTMAP)
  - `validation` — commit validation
  - `preparing` — the prepare phase
  - `pushing the configuration` — pushing config to devices
  - `grabbing transaction lock` — acquiring the write lock

### 5.3 What to point out

| What to show | Why it matters |
| ------------ | -------------- |
| **Span durations** | Identify which phase took the longest |
| **Parent-child hierarchy** | Understand the nesting — e.g. "creating service" is a child of the overall transaction span |
| **Tags/attributes** | Each span carries metadata like device name, service path, user |
| **`trace-id`** | Unique identifier that can be correlated with NSO logs |

### 5.4 Compare traces

Select two different traces (e.g. a single-service commit vs. a multi-service commit) and compare the waterfall. The multi-service commit will show parallel `creating service` spans.

---

## 6 — Explore metrics in Prometheus

Open [http://localhost:9090](http://localhost:9090).

### 6.1 Check targets are UP

Navigate to **Status → Targets**. You should see:

- `nso-metrics` (otel-collector:9464) — **UP**

### 6.2 Run PromQL queries

In the **Graph** tab, try these queries:

**Total traces received by the collector:**

```promql
otelcol_receiver_accepted_spans_total
```

**NSO-specific metrics (exported by OE via OTLP metrics):**

```promql
{job="nso-metrics"}
```

Browse the available metric names — the OE exports NSO gauge and counter metrics (e.g. transaction counts, CDB subscribers, etc.) via the OTLP metrics pipeline.

---

## 7 — Explore metrics in InfluxDB

Open [http://localhost:8086](http://localhost:8086) and log in (see `.env` for credentials: `nso` / `nso-influx-pass`).

### 7.1 Open the Data Explorer

1. Click **Data Explorer** in the left-hand menu.
2. Select the **nso** bucket.

### 7.2 Query span durations

1. Select measurement: **`span`**
2. Select field: **`duration`**
3. Click **Submit**.

This graphs the average (mean) duration of the various transaction phases over time.

### 7.3 Filter by span name

Add a filter for the **`name`** tag to isolate a specific phase:

- `creating service` — how long FASTMAP takes
- `grabbing transaction lock` — lock contention
- `pushing the configuration` — device push time
- `validation` — validation duration

### 7.4 Explore other measurements

Switch between the four measurement types to show different views:

| Query | What it shows |
| ----- | ------------- |
| `span` → `duration` | How long each phase took |
| `span-count` → `count` | How many concurrent operations were in a given phase |
| `transaction` → `duration` | Total transaction time |
| `transaction-lock` → `queue-length` | Lock contention — how many transactions were waiting for the lock |

---

## 8 — Explore dashboards in Grafana

Open [http://localhost:3000](http://localhost:3000) (anonymous access, no login required).

### 8.1 Open the NSO dashboard

Navigate to **Dashboards** and open the **NSO** dashboard (pre-provisioned).

### 8.2 Transaction panels

The dashboard includes panels for:

| Panel | Description |
| ----- | ----------- |
| **Transaction Throughput** | Number of transactions per time interval |
| **Longest Transactions** | Identifies the slowest transactions |
| **Transaction Lock Held** | Duration the transaction lock was held |
| **Queue Length** | Number of transactions waiting for the lock |

### 8.3 Service panels

| Panel | Description |
| ----- | ----------- |
| **Mean / Max Duration for Create Service** | Average and peak time for the FASTMAP `create` callback |
| **Mean Duration for Run Service** | Time for the full service run |
| **Service's Longest Spans** | Which service instances took the most time |

### 8.4 Device panels

| Panel | Description |
| ----- | ----------- |
| **Device Locks Held** | Duration device locks were held |
| **Longest Device Connection** | Slowest device connection establishment |
| **Longest Device Sync-From** | Which `sync-from` took the longest |
| **Concurrent Device Operations** | How many device operations ran in parallel |

### 8.5 Generate more data and watch live

Leave Grafana open and go back to the NSO CLI to create/modify/delete services. The dashboard updates in near real-time (default refresh is 10 s).

```
admin@ncs# config
admin@ncs(config)# services loopback-demo bulk1 device ios-0 loopback-number 1110 ip-address 10.110.1.1
admin@ncs(config-loopback-demo-bulk1)# top
admin@ncs(config)# services loopback-demo bulk2 device ios-1 loopback-number 1111 ip-address 10.110.2.1
admin@ncs(config-loopback-demo-bulk2)# top
admin@ncs(config)# services loopback-demo bulk3 device iosxr-1 loopback-number 1112 ip-address 10.110.3.1
admin@ncs(config-loopback-demo-bulk3)# commit
```

Switch back to Grafana — you should see the new data points appear.

---

## 9 — Jaeger link in commit annotations

The OE adds a Jaeger deep-link to each commit annotation in NSO.

### 9.1 Show the annotation

```
admin@ncs# show configuration commit list | head 20
```

Pick a recent commit and show its changes:

```
admin@ncs# show configuration commit changes <commit-id>
```

The annotation includes a URL like:

```
http://localhost:16686/trace/<trace-id>
```

Click it (or paste into browser) to jump directly to the trace for that specific commit.

---

## 10 — Modify the Observability Exporter configuration live

Show that the OE configuration is dynamic — changes take effect without restart.

### 10.1 Enable the diffset export

This includes the actual configuration diff in exported span data (useful for auditing, has performance implications):

```
admin@ncs# config
admin@ncs(config)# progress export include-diffset true
admin@ncs(config)# commit
admin@ncs(config)# end
```

Now make a change and check Jaeger — the span attributes will include the config diff.

### 10.2 Add extra tags

Add custom tags that appear on every exported span (useful for multi-NSO environments):

```
admin@ncs# config
admin@ncs(config)# progress export extra-tags lab-environment value demo-lab
admin@ncs(config)# progress export extra-tags nso-cluster value cluster-west
admin@ncs(config)# commit
admin@ncs(config)# end
```

Perform another commit, then check the span in Jaeger — the extra tags will be visible as span attributes.

### 10.3 Toggle export on/off

```
admin@ncs# config
admin@ncs(config)# progress export enabled false
admin@ncs(config)# commit
```

Show that Jaeger stops receiving new traces. Then re-enable:

```
admin@ncs(config)# progress export enabled true
admin@ncs(config)# commit
admin@ncs(config)# end
```

### 10.4 Restart the exporter

If something seems stuck, the OE provides an action to restart:

```
admin@ncs# progress export restart
```

---

## 11 — Use case: Troubleshooting a slow transaction

Walk through a realistic troubleshooting scenario.

### 11.1 Scenario

"Users report that service deployments are slow."

### 11.2 Step 1 — Check Grafana for the big picture

Open the NSO dashboard in Grafana. Look at:

- **Transaction Throughput** — is the system overloaded?
- **Longest Transactions** — which transactions are slow?
- **Queue Length** — is there lock contention?

### 11.3 Step 2 — Drill into a specific slow transaction in Jaeger

From the Grafana panel (or from a commit annotation), open the trace in Jaeger.

Look at the waterfall:
- Is `creating service` slow? → Problem in service code (FASTMAP).
- Is `pushing the configuration` slow? → Problem with device communication.
- Is `grabbing transaction lock` long? → Lock contention from concurrent transactions.
- Is `validation` slow? → Heavy validation logic.

### 11.4 Step 3 — Correlate with NSO logs

Use the `trace-id` from Jaeger to search NSO logs:

```bash
docker compose logs nso | grep "<trace-id>"
```

This completes the three-pillar observability approach: **metrics → traces → logs**.

---

## 12 — Cleanup

### 12.1 Delete demo services

```
admin@ncs# config
admin@ncs(config)# no services loopback-demo
admin@ncs(config)# commit
admin@ncs(config)# end
```

### 12.2 Tear down the stack

Preserve volumes (data persists for next demo):

```bash
make down
```

Full reset (destroys all data):

```bash
make clean
```

---

## Quick reference — Configuration knobs

| Config path | Type | Default | Description |
| ----------- | ---- | ------- | ----------- |
| `progress export enabled` | boolean | `true` | Master on/off switch |
| `progress export include-diffset` | boolean | `false` | Include config diff in spans (performance impact) |
| `progress export otlp host` | inet:host | `localhost` | OTel Collector host |
| `progress export otlp port` | port | `4318` (http), `4317` (grpc) | OTel Collector port |
| `progress export otlp transport` | enum | `http` | `http`, `grpc`, `https`, `grpc-secure` |
| `progress export otlp buffer-time` | uint32 | `100` | Buffer time in ms to reorder events (100–10000) |
| `progress export otlp service-name` | string | `NSO` | Service name shown in Jaeger |
| `progress export otlp compression` | enum | `none` | `none` or `gzip` |
| `progress export otlp metrics export-interval` | uint16 | `60` | Seconds between OTLP metric exports |
| `progress export influxdb host` | inet:host | — | InfluxDB host (presence enables export) |
| `progress export influxdb port` | port | `8086` | InfluxDB port |
| `progress export influxdb database` | string | `nso` | InfluxDB database / bucket name |
| `progress export extra-tags` | list | — | Custom key-value tags added to all spans |
| `progress export jaeger-base-url` | string | — | Base URL for Jaeger links in commit annotations |
| `progress export logging` | boolean | `false` | Enable Python logging of the exporter itself |

---

## Appendix A — Docker stack architecture

```
┌─────────────────────────────────────────────────────────┐
│                      nso-net (Docker network)           │
│                                                         │
│  ┌──────────┐    OTLP     ┌────────────────┐           │
│  │          │ ──────────► │  OTel Collector │           │
│  │   NSO    │             │  :4317 (gRPC)  │           │
│  │          │             │  :4318 (HTTP)  │           │
│  │          │             └───────┬────────┘           │
│  │          │                     │                     │
│  │          │   InfluxDB v1 API   │  OTLP    Prometheus │
│  │          │ ─────────────┐      ├────────► :9464      │
│  └──────────┘              │      │                     │
│       │                    ▼      ▼                     │
│  ┌──────────┐       ┌──────────┐ ┌──────────┐          │
│  │  Netsim  │       │ InfluxDB │ │  Jaeger  │          │
│  │ (devices)│       │  :8086   │ │  :16686  │          │
│  └──────────┘       └────┬─────┘ └──────────┘          │
│                          │                              │
│                    ┌─────┴──────┐ ┌──────────┐          │
│                    │  Grafana   │◄│Prometheus │          │
│                    │   :3000    │ │  :9090   │          │
│                    └────────────┘ └──────────┘          │
└─────────────────────────────────────────────────────────┘
```

## Appendix B — Useful NSO CLI commands

```bash
# Show OE package status (NSO CLI)
show packages package observability-exporter

# Show full OE config (from host — progress is hidden in CLI)
docker exec nso-docker-nso-1 ncs_load -Fxml -p /progress/export

# Restart the OE exporter (NSO CLI)
progress export restart

# Restart the OE reader (notification consumer, NSO CLI)
progress export restart-reader

# Show recent commit list (NSO CLI)
show configuration commit list

# Show commit changes and annotation (NSO CLI)
show configuration commit changes <id>
```
