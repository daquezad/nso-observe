# Research Findings & Architecture Revisions

**Date:** 2026-03-03
**Context:** Validation of brainstorming architecture against Cisco's actual implementation patterns

---

## Validated Decisions (No Changes Needed)

### 1. Build Container Workflow — CONFIRMED
- Build container stays running; packages compiled via `docker exec`
- Both build and prod mount `/nso/run/packages` (same path)
- Cisco uses bind mount from host OR named volume for sharing
- Build container has `network_mode: none` (no network needed)
- Compilation: `for f in ${NCS_RUN_DIR}/packages/*/src; do make -C "$f" all || exit 1; done`

### 2. Environment Variables for Interfaces — CONFIRMED
All five env vars are real and documented:
| Variable | Port | Purpose |
|----------|------|---------|
| `NCS_CLI_SSH` | 2024 | CLI over SSH |
| `NCS_WEBUI_TRANSPORT_TCP` | 8080 | JSON-RPC/RESTCONF over TCP |
| `NCS_WEBUI_TRANSPORT_SSL` | 8888 | JSON-RPC/RESTCONF over SSL |
| `NCS_NETCONF_TRANSPORT_SSH` | 2022 | NETCONF over SSH |
| `NCS_NETCONF_TRANSPORT_TCP` | 2023 | NETCONF over TCP |

All disabled by default. Set to `true` to enable.

### 3. ncs.conf Preference Order — CONFIRMED
1. `/etc/ncs/ncs.conf` (Dockerfile ENV)
2. `/nso/etc/ncs.conf` (mounted)
3. `/defaults/ncs.conf` (fallback)

### 4. Admin User via Env Vars — CONFIRMED
`ADMIN_USERNAME` (default `admin`), `ADMIN_PASSWORD`, `ADMIN_SSHKEY` work as documented.

### 5. EXTRA_ARGS — CONFIRMED
Checked before CMD instruction. Example: `EXTRA_ARGS=--with-package-reload`

### 6. Health Check — CONFIRMED
`ncs_cmd -c "wait-start 2"` with `start_period: 10s` (Cisco example). Default image start period is 60s.

### 7. Pre/Post Start Scripts — CONFIRMED
- `$NCS_CONFIG_DIR/pre-ncs-start.d/` — runs before `ncs` starts
- `$NCS_CONFIG_DIR/post-ncs-start.d/` — runs after `ncs` starts
- Supports Python and Bash scripts
- `$NCS_CONFIG_DIR` = `/etc/ncs` by default

### 8. SSH Host Key — CONFIRMED
Auto-generated at `/nso/etc/ssh/ssh_host_ed25519_key` if absent. Persists on volume.

### 9. HTTPS Certificate — CONFIRMED
Auto-generated self-signed cert (30-day, RSA 4096) at `/nso/ssl/cert/host.cert` and `host.key`. Persists on volume.

### 10. HA Raft TLS Certs — CONFIRMED
`gen_tls_certs.sh` uses ecdsa-with-sha384/P-384 (strong crypto). Output structure:
```
ssl/certs/ca.crt, ssl/certs/<node>.crt
ssl/private/ca.key, ssl/private/<node>.key
```
Use `-a` flag for IP addresses. Deploy per node: `ca.crt`, `<node>.crt`, `<node>.key`.

### 11. Observability Stack Components — CONFIRMED
OTel Collector + Jaeger + InfluxDB 2.x + Grafana + Prometheus. Pre-built Grafana dashboard JSON available from Cisco's pubhub.

---

## CRITICAL REVISIONS REQUIRED

### REVISION 1: Local Authentication Must Be Enabled

**Problem:** The default `ncs.conf` uses **Linux PAM only** with **local authentication disabled**. This means `ADMIN_PASSWORD` env var will NOT create a working admin user unless local auth is explicitly enabled.

**Cisco's own workaround (from netsim example):** They use `sed` to modify the default `ncs.conf`:
```bash
sed -i.bak -e "/<local-authentication>/{n;s|<enabled>false</enabled>|<enabled>true</enabled>|}" defaults/ncs.conf
```

**Impact on our design:** Our "no custom ncs.conf" principle needs adjustment.

**Solution:** Add a `pre-ncs-start.d` script that enables local authentication in whichever `ncs.conf` is active:
```bash
#!/bin/bash
# Enable local authentication so ADMIN_PASSWORD env var works
NCS_CONF="/etc/ncs/ncs.conf"
[ -f "$NCS_CONF" ] || NCS_CONF="/nso/etc/ncs.conf"
[ -f "$NCS_CONF" ] || NCS_CONF="/defaults/ncs.conf"
if [ -f "$NCS_CONF" ]; then
    sed -i.bak '/<local-authentication>/{n;s|<enabled>false</enabled>|<enabled>true</enabled>|}' "$NCS_CONF"
fi
```

**Alternative:** Mount a minimal custom `ncs.conf` that extends the default but enables local auth. This is more explicit but creates a version-upgrade dependency.

**Recommendation:** Use the `pre-ncs-start.d` sed approach — it's what Cisco themselves do in their example, and it works regardless of NSO version.

---

### REVISION 2: HA Raft Node Addresses Need a Dot

**Problem:** HA Raft node addresses **cannot be simple short names**. They must contain at least one dot (e.g., `nso1.cluster` not `nso-1`). Docker compose service names like `nso-1` or `nso1` won't work.

**From docs:** "Limitations of the underlying platform place a constraint on the format of ADDRESS, which can't be a simple short name (without a dot), even if the system is able to resolve such a name."

**Impact on our design:** Our proposed node names `nso-1.nso-cluster` need validation. Docker compose resolves by service name, but we need the dotted format.

**Solution:** Use Docker compose `hostname` and network aliases:
```yaml
services:
  nso-1:
    hostname: nso1.cluster
    networks:
      nso-cluster-net:
        aliases:
          - nso1.cluster
```

This gives each node a dotted FQDN resolvable by other containers on the same network.

For TLS certs, generate with: `./generate-tls-certs.sh nso1.cluster nso2.cluster nso3.cluster`

---

### REVISION 3: CDB Init XML Only Works on First Boot

**Problem:** With persistent CDB volumes, if a CDB configuration file already exists, NSO does **not** load XML files at startup. The `init/users.xml` for the operator user will only take effect on first boot (empty CDB).

**Impact:** If you `make clean` and start fresh, users are created. If you restart without cleaning volumes, no new XML is loaded.

**Mitigation:** This is acceptable for dev/lab. Document it clearly:
- First `make up` → users created from init XML
- Subsequent `make up` → users persist in CDB volume
- `make clean` → destroys volumes, next `make up` re-creates users

---

### REVISION 4: Netsim Pattern Is More Complex Than Expected

**Problem:** Cisco's netsim example does much more than run netsim devices. It also:
1. Generates authgroup init XML (`init1.xml`)
2. Generates device init XML (`init2.xml` via `ncs-netsim ncs-xml-init`)
3. Replaces `127.0.0.1` with the netsim container hostname in device configs
4. Modifies `ncs.conf` to enable local auth, SSH, SSL, C-style CLI
5. Shares everything via the SAME volume that NSO mounts

**Impact on our design:** The netsim container in Cisco's example is tightly coupled to NSO setup. We need to decide: replicate this coupling, or separate concerns.

**Solution:** Split into two responsibilities:
- **Netsim container:** Only creates and runs netsim devices. Generates device init XML to a shared volume.
- **Pre-start script on NSO:** Handles ncs.conf modifications (local auth, SSH, SSL). This is already covered by REVISION 1.
- **Init directory:** Static authgroup XML provided by us (not generated by netsim).

This is cleaner than Cisco's example but achieves the same result.

---

### REVISION 5: Observability Exporter Needs pip Dependencies in NSO Container

**Problem:** The Observability Exporter NSO package requires Python dependencies (`parsedatetime`, `opentelemetry-exporter-otlp`, `influxdb`) to be installed in the NSO container.

**Impact on our design:** The thin 4-line Dockerfile needs to also install pip packages when observability is used.

**Solution options:**
1. **Expand Dockerfile** to always install OE deps (adds ~30s to build, harmless if OE not enabled)
2. **Separate Dockerfile** for observability variant (`Dockerfile.prod-obs`)
3. **Post-start script** that pip installs if OE package is detected

**Recommendation:** Option 1 — install the deps in the Dockerfile. They're lightweight and don't hurt if the OE package isn't loaded. Keep it simple:
```dockerfile
ARG NSO_VERSION
FROM cisco-nso-prod:${NSO_VERSION}
USER root
RUN dnf install -y --nodocs net-tools procps vim-minimal && dnf clean all
RUN pip install --no-cache-dir parsedatetime opentelemetry-exporter-otlp influxdb
USER nso
```

---

### REVISION 6: Observability Compose Must Be Built From Scratch

**Problem:** Cisco's OE `compose.yaml` is NOT publicly available — it's only in the CCO package download. We can't reference it directly.

**Impact:** We need to build our own `compose.observability.yaml` from the documented architecture (OTel Collector, Jaeger, InfluxDB 2.x, Grafana, Prometheus).

**Available resources from Cisco:**
- Grafana data source JSON: downloadable from pubhub
- Grafana dashboard JSON: downloadable from pubhub
- NSO configuration XML: documented
- OTel Collector config for Splunk: documented (we adapt for Jaeger/Prometheus)

**Solution:** Create `compose.observability.yaml` with standard images and our own configs. The documented ports and architecture give us enough to build it.

---

### REVISION 7: HA Raft Requires Custom ncs.conf

**Problem:** HA Raft configuration (enabled, cluster-name, listen, ssl, seed-nodes) must be in `ncs.conf`. These cannot be set via environment variables — they're not part of the default ncs.conf env var mechanism.

**Impact:** For HA mode, we MUST mount a custom `ncs.conf`. The "no custom ncs.conf" principle only holds for single-node mode.

**Solution:** Create `config/ncs-ha.conf.xml` template with HA Raft settings. The compose.ha.yaml overlay mounts this into `/nso/etc/ncs.conf` (preference order #2). Use environment variable substitution or sed for per-node values (node-address, cert paths).

Each HA node needs slightly different ncs.conf (different node-address, cert files). Options:
1. **Three separate ncs.conf files** (simple but repetitive)
2. **Template + per-node env var substitution via pre-start script** (cleaner)
3. **Single ncs.conf with env vars expanded by run-nso.sh** (if supported)

**Recommendation:** Option 2 — single template, `pre-ncs-start.d` script does `envsubst` to generate per-node ncs.conf.

---

## Revised Architecture Summary

| Area | Original Decision | Revision | Reason |
|------|-------------------|----------|--------|
| ncs.conf (single-node) | Default + env vars only | Default + env vars + **pre-start sed for local auth** | Local auth disabled by default |
| ncs.conf (HA) | Default + env vars only | **Custom ncs.conf template** with envsubst | HA Raft config can't use env vars |
| HA node names | `nso-1.nso-cluster` | `nso1.cluster` via Docker hostname/alias | Must contain dot, no hyphen issues |
| Dockerfile | 4 lines (debug tools) | **6 lines** (debug tools + pip deps for OE) | OE Python dependencies needed |
| Netsim container | Replicates Cisco's full pattern | **Simplified:** netsim only + device init XML | Separate concerns from ncs.conf modification |
| CDB init XML | Expected to work on every boot | **First boot only** — documented | CDB persistence behavior |
| Observability compose | Adapt from Cisco's | **Build from scratch** using documented architecture | Cisco's compose not publicly available |

---

## Files to Research Further (During Implementation)

1. Download Grafana dashboard JSON from `https://pubhub.devnetcloud.com/media/nso/docs/addons/observability-exporter/dashboard-nso-local.json`
2. Download Grafana data source JSON from `https://pubhub.devnetcloud.com/media/nso/docs/addons/observability-exporter/influxdb-data-source.json`
3. Review `gen_tls_certs.sh` script from NSO examples for exact adaptation
