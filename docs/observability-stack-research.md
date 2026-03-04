# Observability Stack Research Spike

**Date:** 2026-03-04
**Status:** Complete
**Context:** Critical-path research for Epic 4 (Observability & Monitoring). Resolves all unknowns for `compose.observability.yaml`, OTel Collector pipeline, InfluxDB v1 credential setup, Grafana file-based provisioning, OE CDB init XML, and end-to-end testing strategy.

**Source material:** Observability Exporter package `ncs-6.6.1-observability-exporter-1.6.0.tar.gz` extracted from `packages/`. All artifacts in `observability-exporter/setup/` were inspected directly.

---

## 1. Cisco's Reference Architecture (from OE 1.6.0 Package)

The OE package ships a complete `setup/` directory with a compose file, OTel Collector configs, Grafana provisioning templates, an InfluxDB v1 credential script, and a `setup.sh` orchestrator. The architecture has 7 containers:

| Container | Image | Purpose | Internal Ports |
|-----------|-------|---------|----------------|
| `otelcol` | `otel/opentelemetry-collector-contrib:0.94.0` | Receives OTLP from NSO, routes traces and metrics | 4317 (gRPC), 4318 (HTTP), 9464 (Prometheus exporter) |
| `elasticsearch` | `elasticsearch:7.17.9` | Jaeger trace storage backend | 9200 |
| `jaeger-collector` | `jaegertracing/jaeger-collector:1.43` | Ingests traces from OTel via OTLP | 4317 (OTLP receiver) |
| `jaeger-query` | `jaegertracing/jaeger-query:1.43` | Jaeger UI and query API | 16686 |
| `influxdb` | `influxdb:2.7.1` | Time-series metrics from NSO OE | 8086 |
| `prometheus` | `prom/prometheus:v2.43.0` | Scrapes OTel Collector's Prometheus exporter | 9090 |
| `grafana` | `grafana/grafana:10.1.4` | Dashboards (InfluxDB + Prometheus + Jaeger links) | 3000 |

### Key Observation: Jaeger Architecture

Cisco's setup uses the **distributed Jaeger architecture** with separate collector + query + Elasticsearch. For our dev/lab use case, the **Jaeger all-in-one** image (`jaegertracing/all-in-one`) is simpler — it includes collector, query, and in-memory storage in a single container. This eliminates the Elasticsearch dependency entirely.

**Trade-off:** All-in-one stores traces in memory (lost on restart). For dev/lab this is acceptable and reduces the stack from 7 to 5 containers.

---

## 2. OTel Collector Pipeline Configuration

### Cisco's otelcol.yaml (Non-TLS)

```yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:

exporters:
  otlp/jaeger:
    endpoint: "jaeger-collector:4317"
    tls:
      insecure: true
  prometheus:
    endpoint: "0.0.0.0:9464"

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp/jaeger]
    metrics:
      receivers: [otlp]
      exporters: [prometheus]
```

### Adaptation for Our Stack

With Jaeger all-in-one, the OTLP exporter targets `jaeger:4317` (the all-in-one container name). The rest remains identical.

Our adapted config also adds:
- Explicit endpoint bindings (`0.0.0.0:4317`, `0.0.0.0:4318`) for clarity
- A `batch` processor for performance
- A `health_check` extension for Docker healthcheck

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 2s
    send_batch_size: 512

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
  prometheus:
    endpoint: 0.0.0.0:9464

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/jaeger]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

### Prometheus Exporter vs Remote Write

Cisco uses a `prometheus` exporter (scrape-based) on port 9464, not `prometheusremotwrite`. This means Prometheus must be configured to scrape the OTel Collector. Our existing `config/prometheus/prometheus.yml` already has this but targets port 8889 — it should target port 9464 to match Cisco's config.

---

## 3. InfluxDB v1 Compatibility Credential Setup

### The Problem

The NSO Observability Exporter uses the Python `influxdb` v1 client library to write metrics directly to InfluxDB. InfluxDB 2.x doesn't natively support v1 username/password auth — it must be explicitly created.

### Cisco's Solution: Docker Entrypoint Init Script

The OE package includes `influxdb_scripts/influxdb_v1_setup.sh`:

```bash
#!/bin/bash
set -e
nso_bucket_id=`influx bucket find --name ${DOCKER_INFLUXDB_INIT_BUCKET} --hide-headers | awk '{print $1}'`
influx v1 auth create \
  --username ${V1_AUTH_USERNAME} \
  --password ${V1_AUTH_PASSWORD} \
  --write-bucket ${nso_bucket_id} \
  --org ${DOCKER_INFLUXDB_INIT_ORG}
```

This script runs automatically because it's mounted into `/docker-entrypoint-initdb.d/`. InfluxDB's Docker image executes all scripts in that directory after initial setup.

### Environment Variables Required

The InfluxDB container needs these environment variables:

| Variable | Purpose | Our `.env` mapping |
|----------|---------|-------------------|
| `DOCKER_INFLUXDB_INIT_MODE` | Trigger auto-setup | Hardcoded: `setup` |
| `DOCKER_INFLUXDB_INIT_USERNAME` | InfluxDB 2.x admin user | `${INFLUXDB_USERNAME}` |
| `DOCKER_INFLUXDB_INIT_PASSWORD` | InfluxDB 2.x admin password | `${INFLUXDB_PASSWORD}` |
| `DOCKER_INFLUXDB_INIT_ORG` | Organization name | `${INFLUXDB_ORG}` |
| `DOCKER_INFLUXDB_INIT_BUCKET` | Bucket name | `${INFLUXDB_BUCKET}` |
| `DOCKER_INFLUXDB_INIT_ADMIN_TOKEN` | API token | `${INFLUXDB_ADMIN_TOKEN}` |
| `V1_AUTH_USERNAME` | v1 compat username (for OE) | `${INFLUXDB_USERNAME}` |
| `V1_AUTH_PASSWORD` | v1 compat password (for OE) | `${INFLUXDB_PASSWORD}` |

### Implementation for Our Project

1. Copy `influxdb_v1_setup.sh` to a project-level directory (e.g., `config/influxdb/influxdb_v1_setup.sh`)
2. Bind-mount that directory into the InfluxDB container at `/docker-entrypoint-initdb.d/`
3. The v1 auth creation runs once on first init — InfluxDB skips init scripts on subsequent starts

---

## 4. Grafana File-Based Provisioning

### Cisco's Provisioning Structure

The OE package uses 3 provisioning artifacts:

**1. Datasource template** (`grafana_datasource_template.yaml`):
```yaml
apiVersion: 1
datasources:
  - name: InfluxDB
    type: influxdb
    uid: P951FEA4DE68E13C5
    access: proxy
    editable: true
    url: http://influxdb:8086
    jsonData:
      version: Flux
      organization: myorg
      defaultBucket: nso
      tlsSkipVerify: true
    secureJsonData:
      token: {TOKEN}

  - name: Prometheus
    type: prometheus
    uid: PBFA97CFB590B2093
    access: proxy
    url: http://prometheus:9090
    basicAuth: false
    isDefault: false
    version: 1
    editable: true
    jsonData:
      httpMethod: GET
```

**2. Dashboard provider** (`dashboard.yaml`):
```yaml
apiVersion: 1
providers:
  - name: "Dashboard provider"
    orgId: 1
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

**3. Dashboard JSON template** (`nso_dashboard_template.json`):
- ~4200 lines, 120KB
- References datasource UIDs: `P951FEA4DE68E13C5` (InfluxDB) and `PBFA97CFB590B2093` (Prometheus)
- Uses Grafana variable `${jaeger_base_url}` for trace deep-links
- Template has a `{JAEGER_PORT}` placeholder at line 4207 that must be replaced

### Token and Port Substitution

Cisco's `setup.sh` generates final files by running `sed` on the templates:
```bash
sed "s/{JAEGER_PORT}/${jaeger_port}/" ./grafana/nso_dashboard_template.json > ./grafana/dashboards/nso_dashboard.json
sed "s/{TOKEN}/${influxdb_token}/" ./grafana/grafana_datasource_template.yaml > ./grafana/grafana_datasource.yaml
```

### Adaptation for Our Project

Since our ports and tokens are fixed (defined in `.env`), we can pre-generate the final files rather than using templates at runtime:

1. **Datasource YAML** — Copy the template, replace `{TOKEN}` with `${INFLUXDB_ADMIN_TOKEN}`, replace `myorg` with `${INFLUXDB_ORG}`. However, Grafana provisioning doesn't do env var interpolation in YAML files. Options:
   - **Option A:** Hardcode the token in the provisioning file (it's a lab/dev setup)
   - **Option B:** Use Grafana's `GF_*` environment variable support for datasource config
   - **Option C:** Use a Docker entrypoint wrapper that does `envsubst` before Grafana starts

   **Recommendation:** Option A — store the pre-rendered file at `grafana/provisioning/datasources/datasource.yaml` with the actual token value from `.env`. Since `.env` values like `nso-admin-token` are lab defaults, hardcoding them in the provisioning file is acceptable. If the user changes the token in `.env`, they'd also update the Grafana file.

   **Alternative (better):** Use Grafana's environment variable support. Grafana since v9.x supports `$__env{}` syntax in provisioning:
   ```yaml
   secureJsonData:
     token: $__env{INFLUXDB_ADMIN_TOKEN}
   ```
   This is the cleanest approach — the datasource file references the env var, and Compose passes it through.

2. **Dashboard JSON** — Replace `{JAEGER_PORT}` with our actual Jaeger port (16686). Store the processed file at `grafana/dashboards/nso-dashboard.json`.

3. **Dashboard provider YAML** — Use Cisco's file as-is at `grafana/provisioning/dashboards/dashboard-provider.yaml`.

### Grafana Environment Variables

Cisco's compose sets these for anonymous admin access:
```yaml
environment:
  GF_AUTH_ANONYMOUS_ENABLED: "true"
  GF_AUTH_ANONYMOUS_ORG_NAME: "Main Org."
  GF_AUTH_ANONYMOUS_ORG_ROLE: Admin
  GF_AUTH_DISABLE_LOGIN_FORM: "true"
  GF_AUTH_DISABLE_SIGNOUT_MENU: "true"
  GF_DASHBOARDS_JSON_ENABLED: "true"
```

This allows zero-login access to Grafana — appropriate for dev/lab.

### Volume Mounts for Grafana

```yaml
volumes:
  - type: bind
    source: ./grafana/provisioning/datasources/datasource.yaml
    target: /etc/grafana/provisioning/datasources/datasource.yaml
  - type: bind
    source: ./grafana/provisioning/dashboards/dashboard-provider.yaml
    target: /etc/grafana/provisioning/dashboards/main.yaml
  - type: bind
    source: ./grafana/dashboards
    target: /var/lib/grafana/dashboards
```

---

## 5. OE CDB Init XML Configuration

### YANG Model Structure

The OE augments `/progress:progress` with an `export` container. The full config path is:
```
/progress/export/enabled
/progress/export/influxdb/{host,port,username,password,database}
/progress/export/otlp/{host,port,transport,metrics/{host,port,export-interval}}
/progress/export/jaeger-base-url
```

### CDB Init XML for Our Docker Stack

For our compose overlay where NSO, InfluxDB, and OTel Collector are all on `nso-net`:

```xml
<config xmlns="http://tail-f.com/ns/config/1.0">
  <progress xmlns="http://tail-f.com/ns/progress">
    <export xmlns="http://tail-f.com/ns/observability-exporter">
      <enabled>true</enabled>
      <influxdb>
        <host>influxdb</host>
        <port>8086</port>
        <username>nso</username>
        <password>nso-influx-pass</password>
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
</config>
```

**Key details:**
- `influxdb` host uses Docker DNS name `influxdb` (the compose service name)
- `influxdb` port is the container-internal port `8086`, not the host-mapped port
- `influxdb` username/password must match the v1 auth credentials created by the init script
- `otlp` host uses Docker DNS name `otel-collector`
- `otlp` port `4318` is the HTTP receiver (OE defaults to HTTP transport)
- `metrics` endpoint mirrors the OTLP endpoint (both traces and metrics go through OTel Collector)
- `jaeger-base-url` uses `localhost:16686` because it's for browser deep-links from Grafana (user's browser, not container-to-container)
- Password in CDB init XML is plaintext — NSO encrypts it upon loading into CDB

### Credential Alignment

The InfluxDB username/password in the OE config must match exactly:
- `.env`: `INFLUXDB_USERNAME=nso`, `INFLUXDB_PASSWORD=nso-influx-pass`
- InfluxDB v1 auth script: creates v1 auth with these credentials
- OE CDB init XML: references the same username/password

---

## 6. Service Port Map and Inter-Container Communication

### Internal Communication (Container-to-Container via Docker DNS)

| Source | Destination | Protocol | Port | Purpose |
|--------|-------------|----------|------|---------|
| NSO (OE) | otel-collector | HTTP | 4318 | OTLP traces + metrics |
| NSO (OE) | influxdb | HTTP | 8086 | InfluxDB v1 API metrics |
| otel-collector | jaeger | gRPC | 4317 | OTLP traces to Jaeger |
| prometheus | otel-collector | HTTP | 9464 | Scrape Prometheus metrics |
| grafana | influxdb | HTTP | 8086 | Flux queries for dashboards |
| grafana | prometheus | HTTP | 9090 | PromQL queries for dashboards |

### Host-Exposed Ports (for Browser Access)

| Service | Host Port | Container Port | URL |
|---------|-----------|----------------|-----|
| Jaeger UI | 16686 | 16686 | http://localhost:16686 |
| Grafana | 3000 | 3000 | http://localhost:3000 |
| Prometheus | 9090 | 9090 | http://localhost:9090 |
| InfluxDB | 8086 | 8086 | http://localhost:8086 |

### Ports NOT Exposed to Host

| Service | Port | Reason |
|---------|------|--------|
| OTel Collector gRPC | 4317 | Internal only (NSO→OTel, OTel→Jaeger) |
| OTel Collector HTTP | 4318 | Internal only (NSO→OTel) |
| OTel Collector Prometheus | 9464 | Internal only (Prometheus scrapes OTel) |
| Jaeger OTLP | 4317 | Internal only (OTel→Jaeger) |

---

## 7. Simplified Architecture Decision: Jaeger All-in-One

### Cisco's Architecture (7 containers)
```
NSO → OTel Collector → Jaeger Collector → Elasticsearch (storage)
                                        → Jaeger Query (UI)
```

### Our Architecture (5 containers)
```
NSO → OTel Collector → Jaeger All-in-One (collector + query + in-memory storage)
NSO → InfluxDB (direct metrics write via v1 API)
      Prometheus ← scrapes ← OTel Collector
      Grafana ← reads ← InfluxDB + Prometheus (+ Jaeger deep-links)
```

**Rationale:** Eliminates Elasticsearch (heavy, ~1GB image, requires tuning) and the separate Jaeger Collector/Query split. All-in-one stores traces in memory which is fine for dev/lab. If trace persistence is needed later, Jaeger all-in-one supports Badger disk storage via environment variable.

---

## 8. OE Package as a Custom Package

The OE package (`ncs-6.6.1-observability-exporter-1.6.0.tar.gz`) is a pre-compiled tar.gz in the `packages/` directory. Our `build-packages.sh` handles `.bin` files (NED binaries) but the OE package is a `.tar.gz` — it's handled by the `copy_custom_packages()` function which copies directories from `packages/` to the output volume.

**However:** The tar.gz needs to be extracted first. Currently `build-packages.sh` only copies directories from `packages/`. Options:

1. **Extract the tar.gz on the host** before running `make build` — user extracts it manually into `packages/observability-exporter/`
2. **Update `build-packages.sh`** to handle `.tar.gz` files in `packages/` — extract them before compilation
3. **Pre-extract and commit** the `packages/observability-exporter/` directory (large, may not be desirable)

**Recommendation:** Option 1 for now — document that users must extract tar.gz packages into `packages/`. The OE package is pre-compiled (has `load-dir/*.fxs`), so it doesn't need compilation — it just needs to be present in `/nso/run/packages/`.

**Future improvement:** Update `build-packages.sh` to detect and extract `.tar.gz` files in `packages/`.

---

## 9. Updated `.env` Variables for Observability

Current `.env` already has:
```
INFLUXDB_ORG=nso
INFLUXDB_BUCKET=nso
INFLUXDB_ADMIN_TOKEN=nso-admin-token
INFLUXDB_USERNAME=nso
INFLUXDB_PASSWORD=nso-influx-pass
```

No new `.env` variables needed. All observability config is either:
- Derived from existing `.env` variables (InfluxDB config)
- Hardcoded in service-specific config files (OTel pipeline, Grafana provisioning)
- Fixed in the CDB init XML (OE endpoints use Docker DNS names)

---

## 10. End-to-End Testing Strategy

### Static Validation (before functional test)

1. `docker compose -f compose.yaml -f compose.observability.yaml config` — validates merged compose
2. Verify all referenced config files exist: `config/otelcol.yaml`, `config/influxdb/influxdb_v1_setup.sh`, `grafana/provisioning/datasources/datasource.yaml`, `grafana/provisioning/dashboards/dashboard-provider.yaml`, `grafana/dashboards/nso-dashboard.json`, `init/observability-exporter-config.xml`
3. XML well-formedness of `init/observability-exporter-config.xml`
4. YAML syntax of all config files
5. Verify Grafana datasource UIDs match dashboard JSON references

### Functional Test Sequence

1. `make clean && make build` — fresh build with OE package
2. `make up-obs` — start NSO + full observability stack
3. Wait for all services healthy (healthchecks on all containers)
4. Verify Jaeger UI accessible: `curl -s http://localhost:16686/api/services`
5. Verify Grafana UI accessible: `curl -s http://localhost:3000/api/health`
6. Verify Prometheus targets: `curl -s http://localhost:9090/api/v1/targets`
7. Verify InfluxDB: `curl -s http://localhost:8086/health`
8. In NSO CLI: `show packages package observability-exporter` — verify OE loaded
9. In NSO CLI: `show progress export` — verify OE config loaded from CDB init
10. Perform a transaction: `devices device device0 config ...` (if netsim available) or any config change
11. Check Jaeger: `curl -s http://localhost:16686/api/traces?service=NSO&limit=1` — verify trace exists
12. Check InfluxDB: query the `nso` bucket for metrics
13. Check Grafana dashboards: verify panels show data

### Failure Scenarios to Test

- NSO starts before InfluxDB is ready → `depends_on` with healthcheck prevents this
- OTel Collector unreachable → OE logs errors but NSO continues operating
- Grafana datasource token mismatch → dashboards show "No data"
- InfluxDB v1 auth not created → OE metrics writes fail with 401

---

## 11. Compose Overlay Structure for Our Project

### Services in `compose.observability.yaml`

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.94.0
    # Mount our adapted otelcol.yaml
    # Healthcheck on :13133
    # On nso-net

  jaeger:
    image: jaegertracing/all-in-one:1.54
    # Expose 16686 (UI) and 4317 (OTLP receiver)
    # COLLECTOR_OTLP_ENABLED=true
    # On nso-net

  influxdb:
    image: influxdb:2.7.1
    # Auto-setup via DOCKER_INFLUXDB_INIT_* env vars
    # Mount influxdb_v1_setup.sh to /docker-entrypoint-initdb.d/
    # On nso-net

  prometheus:
    image: prom/prometheus:v2.43.0
    # Mount prometheus.yml
    # On nso-net

  grafana:
    image: grafana/grafana:10.1.4
    # Anonymous admin access
    # File-based provisioning (datasources, dashboards)
    # On nso-net

  nso:
    # Additional volumes for OE CDB init XML
    # depends_on otel-collector and influxdb (healthy)
```

### Startup Ordering

```
influxdb (must init + create v1 auth first)
    ↓ healthy
otel-collector (must be ready for NSO traces)
    ↓ healthy
jaeger (OTel routes traces here)
prometheus (scrapes OTel)
grafana (reads InfluxDB + Prometheus)
    ↓ all healthy
nso (OE starts sending traces + metrics)
```

Use `depends_on` with `condition: service_healthy`:
- `otel-collector` depends on `jaeger` (healthy)
- `nso` depends on `otel-collector` (healthy) and `influxdb` (healthy)
- `grafana` depends on `influxdb` (healthy) and `prometheus` (healthy)

---

## 12. File Inventory for Epic 4

### New Files to Create

| File | Source | Purpose |
|------|--------|---------|
| `compose.observability.yaml` | Build from scratch | Replace placeholder; define 5 services |
| `config/influxdb/influxdb_v1_setup.sh` | Adapt from OE package | InfluxDB v1 auth creation |
| `grafana/provisioning/datasources/datasource.yaml` | Adapt from OE template | InfluxDB + Prometheus datasources |
| `grafana/provisioning/dashboards/dashboard-provider.yaml` | Copy from OE package | Dashboard auto-discovery config |
| `grafana/dashboards/nso-dashboard.json` | Process from OE template | Pre-built NSO dashboard (replace `{JAEGER_PORT}`) |
| `init/observability-exporter-config.xml` | Build from YANG model + research | OE CDB init XML |

### Files to Update

| File | Change |
|------|--------|
| `config/otelcol.yaml` | Update prometheus exporter port to 9464 (match Cisco's config) |
| `config/prometheus/prometheus.yml` | Update scrape target to `otel-collector:9464` |
| `Makefile` | Add `up-obs` target |

### Files Unchanged

| File | Reason |
|------|--------|
| `.env` / `.env.example` | Already has all required InfluxDB variables |
| `images/Dockerfile.prod` | Already installs OE pip dependencies |
| `compose.yaml` | Base file unchanged; overlay adds to `nso` service |

---

## Sources

- `observability-exporter/setup/compose.yaml` — Cisco's reference compose (from OE 1.6.0 tar.gz)
- `observability-exporter/setup/otelcol.yaml` — OTel Collector pipeline config
- `observability-exporter/setup/influxdb_scripts/influxdb_v1_setup.sh` — v1 auth creation
- `observability-exporter/setup/grafana/` — Datasource template, dashboard provider, dashboard JSON template
- `observability-exporter/src/yang/observability-exporter.yang` — OE YANG model (config schema)
- `observability-exporter/setup/README.md` — Setup documentation
- `observability-exporter/src/requirements.txt` — Python dependency versions
- `observability-exporter/CHANGES.txt` — Release notes (v1.0.0 through v1.6.0)
- [InfluxDB v1 compatibility API](https://docs.influxdata.com/influxdb/v2/api-guide/influxdb-1x/)
- [Grafana provisioning docs](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Jaeger all-in-one](https://www.jaegertracing.io/docs/latest/getting-started/#all-in-one)
