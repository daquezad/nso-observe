# NSO-docker

Containerized Cisco NSO development environment with composable topologies for single-node deployment, netsim device simulation, and full observability (OTel, Jaeger, InfluxDB, Prometheus, Grafana).

## Prerequisites

- **Docker Engine** 20.10+ or Docker Desktop
- **Docker Compose** v2 (the `docker compose` plugin, not standalone `docker-compose`)
- **Cisco NSO image tarballs** (`cisco-nso-build` and `cisco-nso-prod`) matching the version in `.env`
- **At least one NED** `.signed.bin` file (for netsim or device management)

## Quick Start

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

Or place the `.tar.gz` tarballs in the `images/` directory and `make build` will load them automatically.

### 3. Place NEDs and packages

Drop NED `.signed.bin` files into `neds/`:

```bash
cp ncs-6.6.1-cisco-ios-6.106.signed.bin neds/
```

For the observability stack, extract the Observability Exporter package into `packages/`:

```bash
tar -xzf ncs-6.6.1-observability-exporter-1.6.0.tar.gz -C packages/
```

### 4. Build

```bash
make build
```

This builds the custom production image, starts the build container, unpacks NEDs, and compiles all packages. You should see each NED unpacked, compiled, and copied to the shared volume.

### 5. Start NSO

**Single-node** (NSO only):

```bash
make up
```

**With netsim devices** (NSO + simulated network devices):

```bash
make up-netsim
```

**With observability** (NSO + OTel Collector + Jaeger + InfluxDB + Prometheus + Grafana):

```bash
make up-obs
```

### 6. Access the CLI

```bash
make cli
```

You should land in the NSO Cisco-style CLI. Verify with:

```
admin@ncs# show packages package oper-status
```

## Topologies

This project uses Docker Compose overlays to compose topologies additively.

### Single-Node (`make up`)

Starts only the NSO container. Use this for basic package development or NETCONF/RESTCONF testing against NSO's northbound interfaces.

```
compose.yaml  →  NSO
```

### Netsim (`make up-netsim`)

Adds a netsim container that creates simulated NETCONF devices. Devices are auto-created, auto-started, and auto-onboarded into NSO. Use this for service package testing.

```
compose.yaml + compose.netsim.yaml  →  NSO + Netsim (N devices)
```

After startup, verify devices:

```
admin@ncs# show devices list
```

### Observability (`make up-obs`)

Adds 5 observability containers. NSO's Observability Exporter sends traces and metrics automatically. Use this for performance analysis and transaction tracing.

```
compose.yaml + compose.observability.yaml  →  NSO + OTel + Jaeger + InfluxDB + Prometheus + Grafana
```

After startup, access the UIs:

| Service | URL |
|---------|-----|
| Jaeger (traces) | http://localhost:16686 |
| Grafana (dashboards) | http://localhost:3000 |
| Prometheus (metrics) | http://localhost:9090 |
| InfluxDB | http://localhost:8086 |
| NSO Web UI | http://localhost:8080 |

## Make Targets

| Target | Description |
|--------|-------------|
| `make build` | Build custom image, unpack NEDs, compile all packages |
| `make up` | Start NSO in single-node topology |
| `make up-netsim` | Start NSO with netsim simulated devices |
| `make up-obs` | Start NSO with full observability stack |
| `make down` | Stop and remove all containers (preserves volumes) |
| `make cli` | Open NSO CLI (Cisco-style) |
| `make logs` | Stream container logs |
| `make clean` | Stop all containers and destroy volumes (full reset) |

## Environment Variables

All configuration lives in a single `.env` file. Copy `.env.example` to `.env` before starting.

### NSO Version

| Variable | Default | Description |
|----------|---------|-------------|
| `NSO_VERSION` | `6.6.1` | Cisco NSO image tag. Change this single value for version upgrades. |

### NSO Credentials

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_USERNAME` | `admin` | Admin user created by NSO's `run-nso.sh` on startup |
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

## Project Structure

```
NSO-docker/
├── .env.example                    # Environment variable template
├── Makefile                        # Primary user interface
├── compose.yaml                    # Base: NSO + build service
├── compose.netsim.yaml             # Overlay: netsim devices
├── compose.observability.yaml      # Overlay: telemetry stack
├── images/
│   └── Dockerfile.prod             # Custom NSO production image
├── scripts/
│   ├── build-packages.sh           # NED unpacking & compilation
│   └── pre-ncs-start/
│       └── 01-enable-local-auth.sh # Enables local auth before NCS starts
├── init/
│   ├── users.xml                   # Operator user (CDB init)
│   ├── authgroups.xml              # Netsim device auth groups
│   └── observability-exporter-config.xml  # OE telemetry config
├── neds/                           # Drop NED .signed.bin files here
├── packages/                       # Drop custom/OE packages here
├── netsim/
│   ├── netsim-start.sh             # Netsim container entrypoint
│   └── post-ncs-start/
│       └── 01-load-netsim-devices.sh  # Auto-onboards devices into NSO
├── config/
│   ├── otelcol.yaml                # OTel Collector pipeline config
│   ├── prometheus/
│   │   └── prometheus.yml          # Prometheus scrape targets
│   └── influxdb/
│       └── influxdb_v1_setup.sh    # InfluxDB v1 auth init script
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasource.yaml     # InfluxDB + Prometheus datasources
│   │   └── dashboards/
│   │       └── dashboard-provider.yaml
│   └── dashboards/
│       └── nso-dashboard.json      # Pre-built NSO performance dashboard
└── tests/                          # Static validation test suite
    ├── test-build-packages.sh
    ├── test-init-xml.sh
    ├── test-makefile.sh
    ├── test-netsim-start.sh
    └── test-pre-ncs-start.sh
```

## Version Upgrade

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

## Troubleshooting

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

**Cause:** The Observability Exporter package isn't loaded, or the OE config references wrong endpoints.

**Fix:**
1. Verify the OE package was extracted into `packages/observability-exporter/` before `make build`
2. Verify in NSO CLI: `show packages package observability-exporter oper-status`
3. Verify OE config: `show progress export`
4. Check container logs: `make logs`

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
