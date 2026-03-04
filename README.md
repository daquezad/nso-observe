<h1 align="center">🔭 NSO Observe<br /><br />
<div align="center">

<img src="https://img.shields.io/badge/Cisco-NSO_6.6-049fd9?style=flat-square&logo=cisco&logoColor=white" alt="Cisco NSO">
<img src="https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white" alt="Docker Compose">
<img src="https://img.shields.io/badge/OpenTelemetry-Traces-4B0082?style=flat-square&logo=opentelemetry&logoColor=white" alt="OpenTelemetry">
<img src="https://img.shields.io/badge/Jaeger-Tracing-66CFE3?style=flat-square&logo=jaeger&logoColor=black" alt="Jaeger">
<img src="https://img.shields.io/badge/Grafana-Dashboards-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
<img src="https://img.shields.io/badge/Prometheus-Metrics-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus">
<img src="https://img.shields.io/badge/InfluxDB-TimeSeries-22ADF6?style=flat-square&logo=influxdb&logoColor=white" alt="InfluxDB">
<img src="https://img.shields.io/badge/Netsim-Simulation-00BCEB?style=flat-square&logo=cisco&logoColor=white" alt="Netsim">

</div>
</h1>

<div align="center">
A <strong>containerized Cisco NSO development environment</strong> with composable topologies and a full observability stack baked in. Spin up NSO with simulated network devices and end-to-end telemetry — traces, metrics, and dashboards — in a single command.
<br /><br />
Built with <a href="https://docs.docker.com/compose/"><strong>Docker Compose overlays</strong></a> for modular topology selection, <a href="https://opentelemetry.io/"><strong>OpenTelemetry</strong></a> for distributed tracing, and <a href="https://grafana.com/"><strong>Grafana</strong></a> for pre-built NSO performance dashboards.
<br /><br />
</div>

> **⚠️ Disclaimer**: This project was developed for **experimentation, testing, and learning purposes only**. It is not intended for production deployments. Default credentials are used throughout for convenience in lab environments. Always follow your organization's security policies for production use.

---

## 🚀 Overview

This platform provides a **batteries-included development environment** for Cisco NSO, designed to get you from zero to a fully observable network automation lab in minutes. Choose your topology, run one command, and start building.

The project follows a composable architecture using Docker Compose overlays: **Base NSO → Add Netsim Devices → Add Observability Stack**, with complete visibility into NSO internals through transaction tracing, performance metrics, and pre-built Grafana dashboards.

## ⚙️ Features

### Core Capabilities
- 🐳 **One-Command Deployment** — `make build && make up` gets you a running NSO instance
- 🔀 **Composable Topologies** — Mix and match single-node, netsim, and observability overlays
- 📡 **Netsim Simulation** — Auto-created, auto-started, and auto-onboarded simulated devices
- 🔭 **Full Observability** — Distributed tracing, time-series metrics, and pre-built dashboards
- 📊 **Grafana Dashboards** — Transaction throughput, lock contention, service timings, device operations
- 🔄 **Version Agility** — Change one variable to upgrade NSO; no file edits needed

### Observability Stack
- 📡 **OpenTelemetry Collector** — Receives OTLP traces and exports to backends
- 🔍 **Jaeger** — Distributed trace visualization for NSO transactions
- 📈 **Prometheus** — Metrics scraping from OTel Collector
- 💾 **InfluxDB** — Time-series storage for NSO span and transaction data
- 📊 **Grafana** — Pre-provisioned datasources and NSO performance dashboard

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Docker Compose Overlays                        │
│                                                                         │
│  compose.yaml          compose.netsim.yaml     compose.observability.yaml
│  ┌──────────┐          ┌──────────────┐        ┌─────────────────────┐  │
│  │          │          │              │        │  OTel    Jaeger     │  │
│  │   NSO    │◄─────────│   Netsim     │        │  Collector  ▲      │  │
│  │          │  device  │  (N devices) │        │    ▲        │      │  │
│  │  :8080   │  onboard │  :830/device │        │    │    :16686     │  │
│  │  :2024   │          │              │        │    │               │  │
│  │  :2022   │          └──────────────┘        │  ┌┴──────────┐    │  │
│  │          │─── OTLP traces ──────────────────│──│ NSO OE    │    │  │
│  │          │─── metrics ──────────────────────│──│ Package   │    │  │
│  └──────────┘                                  │  └───────────┘    │  │
│       │                                        │                    │  │
│       │ build                                  │  InfluxDB          │  │
│  ┌──────────┐                                  │    :8086           │  │
│  │ NSO Build│                                  │                    │  │
│  │ Container│                                  │  Prometheus        │  │
│  │ (compile)│                                  │    :9090           │  │
│  └──────────┘                                  │                    │  │
│                                                │  Grafana           │  │
│                                                │    :3000           │  │
│                                                └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## 🧰 Topologies

| Topology | Command | Services | Use Case |
|----------|---------|----------|----------|
| **Single-Node** | `make up` | NSO | Package development, NETCONF/RESTCONF testing |
| **Netsim** | `make up-netsim` | NSO + Netsim | Service package testing with simulated devices |
| **Observability** | `make up-obs` | NSO + OTel + Jaeger + InfluxDB + Prometheus + Grafana | Performance analysis, transaction tracing |
| **Full Stack** | `make up-all` | NSO + Netsim + All observability | Complete dev/test environment |

## 🧩 Prerequisites

- **Docker Engine** 20.10+ or Docker Desktop
- **Docker Compose** v2 (the `docker compose` plugin)
- **Cisco NSO image tarballs** (`cisco-nso-build` and `cisco-nso-prod`) matching the version in `.env`
- **At least one NED** `.signed.bin` file (for netsim or device management)

## 🛠️ Installation

### 1. Clone and configure

```bash
git clone <repo-url> && cd NSO-docker
cp .env.example .env
```

Edit `.env` to set `NSO_VERSION` to match your NSO image tarballs. The defaults work for `6.6.1`.

### 2. Place NSO images

Either pre-load images manually:

```bash
docker load -i nso-6.6.1.container-image-prod.tar.gz
docker load -i nso-6.6.1.container-image-dev.tar.gz
```

Or place the `.tar.gz` tarballs in `images/` and `make build` will load them automatically.

### 3. Place NEDs and packages

Drop NED `.signed.bin` files into `neds/`:

```bash
cp ncs-6.6.1-cisco-ios-6.106.signed.bin neds/
```

For the observability stack, extract the Observability Exporter package into `packages/`:

```bash
tar -xzf ncs-6.6.1-observability-exporter-1.6.0.tar.gz -C packages/
```

### 4. Build and run

```bash
make build
make up-all    # Full stack: NSO + Netsim + Observability
```

### 5. Access services

| Service | URL | Credentials |
|---------|-----|-------------|
| 🌐 NSO Web UI | http://localhost:8080 | `admin` / `admin` |
| 🖥️ NSO CLI | `make cli` | — |
| 🔍 Jaeger (traces) | http://localhost:16686 | — |
| 📊 Grafana (dashboards) | http://localhost:3000 | Anonymous access |
| 📈 Prometheus (metrics) | http://localhost:9090 | — |
| 💾 InfluxDB | http://localhost:8086 | See `.env` |

## 📋 Make Targets

| Target | Description |
|--------|-------------|
| `make build` | 🔨 Build custom image, unpack NEDs, compile all packages |
| `make up` | ▶️ Start NSO in single-node topology |
| `make up-netsim` | 📡 Start NSO with netsim simulated devices |
| `make up-obs` | 🔭 Start NSO with full observability stack |
| `make up-all` | 🚀 Start NSO with netsim + observability |
| `make down` | ⏹️ Stop and remove all containers (preserves volumes) |
| `make cli` | 🖥️ Open NSO CLI (Cisco-style) |
| `make logs` | 📜 Stream container logs |
| `make clean` | 🧹 Stop all containers and destroy volumes (full reset) |

## ⚙️ Configuration

All configuration lives in a single `.env` file. Copy `.env.example` to `.env` before starting.

### NSO Version

| Variable | Default | Description |
|----------|---------|-------------|
| `NSO_VERSION` | `6.6.1` | Cisco NSO image tag — change this single value for version upgrades |

### NSO Credentials

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_USERNAME` | `admin` | Admin user created by NSO on startup |
| `ADMIN_PASSWORD` | `admin` | Admin password |

An operator user (`oper` / `oper`) is also created via `init/users.xml` on first boot.

### Northbound Interfaces

| Variable | Default | Description |
|----------|---------|-------------|
| `NCS_CLI_SSH` | `true` | SSH CLI access (port 2024) |
| `NCS_WEBUI_TRANSPORT_TCP` | `true` | HTTP Web UI (port 8080) |
| `NCS_WEBUI_TRANSPORT_SSL` | `true` | HTTPS Web UI (port 8888) |
| `NCS_NETCONF_TRANSPORT_SSH` | `true` | NETCONF over SSH (port 2022) |
| `NCS_NETCONF_TRANSPORT_TCP` | `false` | NETCONF over TCP |

### Netsim

| Variable | Default | Description |
|----------|---------|-------------|
| `NETSIM_DEVICE_COUNT` | `3` | Number of simulated network devices to create |

### Observability (InfluxDB)

| Variable | Default | Description |
|----------|---------|-------------|
| `INFLUXDB_ORG` | `nso` | InfluxDB organization |
| `INFLUXDB_BUCKET` | `nso` | InfluxDB bucket for NSO metrics |
| `INFLUXDB_ADMIN_TOKEN` | `nso-admin-token` | InfluxDB API token |
| `INFLUXDB_USERNAME` | `nso` | InfluxDB username (also used for v1 compat) |
| `INFLUXDB_PASSWORD` | `nso-influx-pass` | InfluxDB password (also used for v1 compat) |

## 📁 Project Structure

```
NSO-docker/
├── .env.example                         # Environment variable template
├── Makefile                             # Primary user interface
├── compose.yaml                         # Base: NSO + build service
├── compose.netsim.yaml                  # Overlay: netsim devices
├── compose.observability.yaml           # Overlay: telemetry stack
├── images/
│   └── Dockerfile.prod                  # Custom NSO production image
├── scripts/
│   ├── build-packages.sh               # NED unpacking & compilation
│   └── pre-ncs-start/
│       └── 01-enable-local-auth.sh      # Enables local auth before NCS starts
├── init/
│   ├── users.xml                        # Admin + operator users (CDB init)
│   ├── authgroups.xml                   # Netsim device auth groups
│   └── observability-exporter-config.xml # OE telemetry config
├── neds/                                # Drop NED .signed.bin files here
├── packages/                            # Drop custom/OE packages here
├── netsim/
│   ├── netsim-start.sh                  # Netsim container entrypoint
│   └── post-ncs-start/
│       └── 01-load-netsim-devices.sh    # Auto-onboards devices into NSO
├── config/
│   ├── otelcol.yaml                     # OTel Collector pipeline config
│   ├── prometheus/
│   │   └── prometheus.yml               # Prometheus scrape targets
│   └── influxdb/
│       └── influxdb_v1_setup.sh         # InfluxDB v1 auth init script
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasource.yaml          # InfluxDB + Prometheus datasources
│   │   └── dashboards/
│   │       └── dashboard-provider.yaml
│   └── dashboards/
│       └── nso-dashboard.json           # Pre-built NSO performance dashboard
└── tests/                               # Static validation test suite
```

## 🔄 Version Upgrade

Upgrading NSO requires only one variable change:

1. Update `NSO_VERSION` in `.env` to the new version
2. Place the new NSO image tarballs in `images/` (or `docker load` them)
3. Reset and rebuild:

```bash
make clean
make build
make up
```

No changes to Dockerfiles, compose files, or scripts are needed.

## 🔧 Troubleshooting

### NSO container won't start / unhealthy

**Symptoms:** `make up` hangs or container shows `unhealthy`.

**Cause:** Usually missing packages or a bad CDB state.

**Fix:**
```bash
make logs          # Check NSO startup output for errors
make clean         # Full reset (destroys volumes)
make build && make up
```

### "Required NSO images not found"

**Symptoms:** `make build` fails with image-not-found error.

**Cause:** NSO Docker images aren't loaded locally.

**Fix:** Either place `.tar.gz` tarballs in `images/` or load manually:
```bash
docker load -i nso-6.6.1.container-image-prod.tar.gz
docker load -i nso-6.6.1.container-image-dev.tar.gz
```

### Netsim devices not appearing in NSO

**Symptoms:** `show devices list` is empty after `make up-netsim`.

**Cause:** Build step was skipped or packages weren't compiled.

**Fix:**
```bash
make clean
make build         # Recompile NEDs — netsim needs them
make up-netsim
```

### Observability stack shows no data

**Symptoms:** Grafana dashboards are empty, Jaeger shows no traces.

**Cause:** The Observability Exporter package isn't loaded, or data hasn't been generated yet.

**Fix:**
1. Verify the OE package was extracted into `packages/observability-exporter/` before `make build`
2. Verify in NSO CLI: `show packages package observability-exporter oper-status`
3. Generate telemetry by performing NSO operations: `devices sync-from`, config changes, commits
4. In Grafana, set time range to **"Last 1 hour"** and refresh

### Stale volumes after version change

**Symptoms:** NSO starts but behaves unexpectedly after changing `NSO_VERSION`.

**Cause:** Old CDB data from a previous version persists in named volumes.

**Fix:**
```bash
make clean         # Destroys all volumes
make build         # Rebuild with new version
make up
```

`make down` preserves volumes intentionally. Use `make clean` for a full reset.

## 📚 Tech Stack

| Layer | Technologies |
|-------|-------------|
| **Orchestration** | Cisco NSO 6.6, Docker Compose (overlays) |
| **Simulation** | NSO Netsim (IOS, IOS-XR NEDs) |
| **Tracing** | OpenTelemetry Collector, Jaeger |
| **Metrics** | Prometheus, InfluxDB 2.x |
| **Dashboards** | Grafana 10.x |
| **Telemetry Source** | NSO Observability Exporter package |

## 📜 License

Apache License 2.0

---

<div align="center">
<strong>Built for experimentation and learning</strong>
<br />
A containerized NSO lab with full observability — from intent to insight
</div>
