# Netsim Research Spike

**Date:** 2026-03-04
**Status:** Complete
**Context:** Critical-path research for Epic 3 (Netsim Integration). Blockers for compose.netsim.yaml, setup-netsim.sh, authgroups.xml, and the netsim container entrypoint.

---

## 1. ncs-netsim CLI Commands

The `ncs-netsim` tool simulates network devices using Tail-f ConfD. It accepts NED packages as input and creates device instances that NSO can manage.

### Full Command Reference

```
ncs-netsim [--dir <NetsimDir>]
    create-network <NcsPackage> <NumDevices> <Prefix>
    create-device <NcsPackage> <DeviceName>
    add-to-network <NcsPackage> <NumDevices> <Prefix>
    add-device <NcsPackage> <DeviceName>
    delete-network
    [-a | --async] start [devname]
    [-a | --async] stop [devname]
    [-a | --async] reset [devname]
    [-a | --async] restart [devname]
    list
    is-alive [devname]
    status [devname]
    whichdir
    ncs-xml-init [devname]
    ncs-xml-init-remote <RemoteNodeName> [devname]
    [--force-generic]
    packages
    netconf-console devname [XpathFilter]
    [-w | --window] [cli | cli-c | cli-i] devname
```

### Commands Relevant to Our Container Design

| Command | Purpose | Our Usage |
|---------|---------|-----------|
| `create-network <pkg> <n> <prefix>` | Creates N devices with prefix naming | Primary: creates `device0..N` from the NED |
| `create-device <pkg> <name>` | Creates a single named device | Alternative for explicit naming |
| `add-to-network <pkg> <n> <prefix>` | Adds more devices to existing network | Multi-NED scenarios |
| `start` | Starts all netsim devices | Container entrypoint must call this |
| `stop` | Stops all netsim devices | Container shutdown |
| `is-alive [devname]` | Checks if device(s) are running | Healthcheck command |
| `list` | Shows device names, ports, directories | Debugging |
| `ncs-xml-init` | Generates device onboarding XML | Critical for NSO device registration |
| `ncs-xml-init-remote <hostname>` | Same as above but replaces `127.0.0.1` with `<hostname>` | **Key for containers** — avoids manual sed |

### Port Assignment Scheme

Netsim assigns ports sequentially starting from base values. For the first device:

| Service | First Device | Second Device | Pattern |
|---------|-------------|---------------|---------|
| NETCONF SSH | 12022 | 12023 | 12022 + N |
| SNMP | 11022 | 11023 | 11022 + N |
| IPC | 5010 | 5011 | 5010 + N |
| CLI | 10022 | 10023 | 10022 + N |

Example `ncs-netsim list` output:
```
name=device0 netconf=12022 snmp=11022 ipc=5010 cli=10022 dir=./netsim/device/device0
name=device1 netconf=12023 snmp=11023 ipc=5011 cli=10023 dir=./netsim/device/device1
name=device2 netconf=12024 snmp=11024 ipc=5012 cli=10024 dir=./netsim/device/device2
```

### The `ncs-xml-init-remote` Discovery

**This is a major finding.** The `ncs-xml-init-remote <RemoteNodeName>` variant generates device XML with the specified hostname instead of `127.0.0.1`. This eliminates the `sed` replacement that Cisco's own example uses:

```bash
# Cisco's approach (from their compose example):
ncs-netsim --dir /netsim ncs-xml-init > /nso-run-prod/run/cdb/init2.xml
sed -i.orig -e "s|127.0.0.1|ex-netsim|" /nso-run-prod/run/cdb/init2.xml

# Cleaner approach using ncs-xml-init-remote:
ncs-netsim --dir /netsim ncs-xml-init-remote netsim-container > /output/devices.xml
```

Where `netsim-container` is the Docker Compose service name (resolvable via Docker DNS).

**Impact on our design:** Use `ncs-xml-init-remote` instead of `ncs-xml-init` + `sed`. Cleaner, less fragile, and purpose-built for this use case.

### Netsim Directory Structure

After `create-network`, the `--dir` path contains:

```
<netsim-dir>/
├── device/
│   ├── device0/    # ConfD instance files, logs
│   ├── device1/
│   └── device2/
├── .netsiminfo     # Metadata about the network
└── ...
```

Each device directory contains a full ConfD instance with its own configuration, logs, and state.

---

## 2. Device Onboarding XML Format

### What `ncs-xml-init` Generates

The command outputs XML that tells NSO about each simulated device: its name, address, port, authentication group, device type, and NED identity. The XML conforms to the `tailf-ncs` namespace.

Based on the Cisco documentation and device configuration patterns, the generated XML structure follows this schema:

```xml
<devices xmlns="http://tail-f.com/ns/ncs">
  <device>
    <name>device0</name>
    <address>127.0.0.1</address>
    <port>12022</port>
    <authgroup>default</authgroup>
    <device-type>
      <netconf>
        <ned-id xmlns:router-id="http://example.com/router">router-id:router</ned-id>
      </netconf>
    </device-type>
    <state>
      <admin-state>unlocked</admin-state>
    </state>
  </device>
  <device>
    <name>device1</name>
    <address>127.0.0.1</address>
    <port>12023</port>
    <authgroup>default</authgroup>
    <device-type>
      <netconf>
        <ned-id xmlns:router-id="http://example.com/router">router-id:router</ned-id>
      </netconf>
    </device-type>
    <state>
      <admin-state>unlocked</admin-state>
    </state>
  </device>
</devices>
```

Key observations:

- **`address`**: Always `127.0.0.1` with standard `ncs-xml-init`. Use `ncs-xml-init-remote <hostname>` to replace.
- **`port`**: The NETCONF SSH port assigned by netsim (12022, 12023, ...).
- **`authgroup`**: Set to `default` — NSO must have a matching authgroup configured.
- **`ned-id`**: Namespace-prefixed identifier matching the NED package used. The namespace and prefix come from the NED's YANG model.
- **`admin-state`**: Set to `unlocked` so NSO can immediately communicate with the device.
- **`device-type`**: Matches the simulated protocol. NETCONF for NETCONF NEDs, CLI for CLI NEDs. Generic NEDs simulate as NETCONF unless `--force-generic` is used.

### For CLI NEDs (cisco-ios, cisco-iosxr, cisco-nx)

CLI NED devices have a different `device-type` block:

```xml
<device-type>
  <cli>
    <ned-id xmlns:cisco-ios-cli="urn:...">cisco-ios-cli:cisco-ios-cli</ned-id>
  </cli>
</device-type>
```

**Important for our project:** The NED identifier must exactly match the installed NED package. Since we use signed `.bin` NEDs that get unpacked and compiled, the `ned-id` in the XML will reference whatever NED identity the package defines.

### Loading the XML into NSO

Two mechanisms:

1. **CDB init (first boot):** Place the XML file at `/nso/run/cdb/<filename>.xml`. NSO loads it on first start when CDB is empty.
2. **Runtime load:** `ncs_load -l -m devices.xml` merges the XML into running CDB.

For our container design, CDB init is preferred — the netsim container generates the XML and places it on a shared volume that NSO reads at startup.

### CDB Init Loading Order

When multiple XML files exist in `/nso/run/cdb/`, NSO loads them in alphabetical order. Cisco's example uses `init1.xml` (authgroups) and `init2.xml` (devices) to ensure authgroups exist before device references.

**Our naming convention:**
- `authgroups.xml` — static, provided by us (bind mount from `init/`)
- `netsim-devices.xml` — generated by netsim container (shared volume)

Alphabetical order puts `authgroups.xml` before `netsim-devices.xml`, which is correct.

---

## 3. Post-ncs-start Script Mechanism

### How It Works

The NSO production container runs `/run-nso.sh` as its entrypoint. This script executes scripts in two hook directories:

| Directory | Timing | Use Cases |
|-----------|--------|-----------|
| `$NCS_CONFIG_DIR/pre-ncs-start.d/` | Before `ncs` daemon starts | Modify ncs.conf, set up files, fix permissions |
| `$NCS_CONFIG_DIR/post-ncs-start.d/` | After `ncs` daemon starts | Load config into running NSO, start cron jobs |

`$NCS_CONFIG_DIR` defaults to `/etc/ncs`.

### Pre-ncs-start vs. Post-ncs-start

| Aspect | pre-ncs-start.d | post-ncs-start.d |
|--------|-----------------|-------------------|
| **NCS running?** | No | Yes |
| **CDB accessible?** | No | Yes |
| **ncs_cmd available?** | No | Yes |
| **ncs_load available?** | No | Yes |
| **Can modify ncs.conf?** | Yes (primary use case) | Yes but requires `ncs_cmd -c "reload"` |
| **Can load XML into CDB?** | No (use CDB init files instead) | Yes, via `ncs_load -l -m` |
| **Script types** | Bash, Python | Bash, Python |
| **Execution order** | Alphabetical by filename | Alphabetical by filename |
| **Cisco's own usage** | Enable local auth via sed | `10-cron-logrotate.sh` (log rotation cron) |

### Post-ncs-start for Netsim Device Loading

**Why we need post-ncs-start for netsim:** The netsim device XML could be loaded via CDB init (placing it in `/nso/run/cdb/`), but this only works on first boot. If the netsim container is recreated (new devices added/removed), the CDB init XML is ignored because CDB already has data.

**Alternative approaches:**

1. **CDB init only (first boot):** Simpler. Devices loaded once. To change, `make clean` + `make up-netsim`.
2. **Post-start script:** Runs `ncs_load -l -m` every startup. Always syncs devices. More complex but handles device count changes.
3. **Hybrid:** CDB init for authgroups (static), post-start script for device XML (dynamic).

**Recommendation:** Approach 1 (CDB init only) for v1. This matches the CDB init behavior we already use for `users.xml`. Device changes require `make clean`, which is acceptable for dev/lab.

### Script Format Requirements

Scripts must be executable and have appropriate shebangs:

```bash
#!/bin/bash
# Scripts in post-ncs-start.d/ run after NCS is fully started.
# NCS CLI, ncs_cmd, and ncs_load are all available.
```

The `run-nso.sh` entrypoint runs them in alphabetical order, so use numeric prefixes:
- `01-load-netsim-devices.sh`
- `10-cron-logrotate.sh` (Cisco's built-in)

---

## 4. Authgroup XML Pattern

### What Authgroups Do

Authgroups store the credentials NSO uses to authenticate to managed devices. Every device references an authgroup by name. When NSO connects to a device, it looks up the authgroup to determine what username/password (or SSH key) to send.

### Authgroup Structure

Authgroups support two mapping strategies:

1. **`default-map`**: A fallback for any local NSO user not explicitly mapped.
2. **`umap`**: Per-user mapping from local NSO user to remote device credentials.

### Netsim Default Credentials

All netsim devices use `admin`/`admin` for authentication. This is hardcoded in the ConfD instances that netsim creates. The generated `ncs-xml-init` output references `authgroup: default`, so NSO must have an authgroup named `default` with credentials that match.

### Cisco's Authgroup XML (From Their Docker Compose Example)

Cisco's own netsim container example generates this XML inline:

```xml
<devices xmlns="http://tail-f.com/ns/ncs">
  <authgroups>
    <group>
      <name>default</name>
      <umap>
        <local-user>admin</local-user>
        <remote-name>admin</remote-name>
        <remote-password>admin</remote-password>
      </umap>
    </group>
  </authgroups>
</devices>
```

This maps the local NSO user `admin` to remote credentials `admin`/`admin` on netsim devices.

### Recommended Authgroup XML for Our Project

For our project, we should use `default-map` instead of `umap` since we want any NSO user (admin or operator) to be able to manage netsim devices:

```xml
<devices xmlns="http://tail-f.com/ns/ncs">
  <authgroups>
    <group>
      <name>default</name>
      <default-map>
        <remote-name>admin</remote-name>
        <remote-password>admin</remote-password>
      </default-map>
    </group>
  </authgroups>
</devices>
```

**`default-map` vs `umap`:**
- `default-map`: Any local user maps to these remote credentials. Simpler for dev/lab.
- `umap`: Only explicitly listed local users get mapped. Better for production.

For netsim in a dev/lab context, `default-map` is the pragmatic choice.

### File Location

This XML goes in `init/authgroups.xml`, bind-mounted to `/nso/run/cdb/authgroups.xml`. It loads on first boot via CDB init.

**Critical:** The authgroup XML must use the root element `<devices xmlns="http://tail-f.com/ns/ncs">` — it's part of the devices configuration tree, not a standalone element.

### Password Handling

Passwords in CDB init XML are provided as plaintext. NSO encrypts them (AES) upon loading into CDB. After CDB init, the running config shows encrypted values:

```
devices authgroups group default
  default-map remote-name admin
  default-map remote-password $4$wIo7Yd068FRwhYYI0d4IDw==
```

This is expected and secure — the plaintext only exists in the init XML file, which is on a bind mount from the host (not stored in CDB).

---

## 5. Netsim Container Entrypoint Design

### Cisco's Approach (From Official Docker Compose Example)

Cisco's netsim example uses the **production image** (`cisco-nso-prod`) with a custom entrypoint. The container runs a long inline bash command:

```yaml
EXAMPLE:
  image: cisco-nso-prod:6.4
  container_name: ex-netsim
  entrypoint: bash
  command: -c '
    rm -rf /netsim
    && mkdir /netsim
    && ncs-netsim --dir /netsim create-network /network-element 1 ex
    && PYTHONPATH=/opt/ncs/current/src/ncs/pyapi ncs-netsim --dir /netsim start
    && mkdir -p /nso-run-prod/run/cdb
    && echo "<devices xmlns=...>
        <authgroups>...</authgroups>
        </devices>" > /nso-run-prod/run/cdb/init1.xml
    && ncs-netsim --dir /netsim ncs-xml-init > /nso-run-prod/run/cdb/init2.xml
    && sed -i.orig -e "s|127.0.0.1|ex-netsim|" /nso-run-prod/run/cdb/init2.xml
    && mkdir -p /nso-run-prod/etc
    && sed ... defaults/ncs.conf > /nso-run-prod/etc/ncs.conf
    && tail -f /dev/null'
```

Key observations:
1. Uses `cisco-nso-prod` image (has `ncs-netsim` binary)
2. Overrides `entrypoint: bash` to bypass `run-nso.sh`
3. Creates netsim network, starts devices, generates init XMLs
4. Writes authgroup + device XML to a **shared volume** with the NSO container
5. Also modifies `ncs.conf` for the NSO container (tight coupling)
6. Ends with `tail -f /dev/null` to keep the container running
7. Requires `PYTHONPATH` to be set for netsim start

### Design Considerations for Our Implementation

#### Image Choice

The netsim container must use an image that has the `ncs-netsim` binary and the NED packages. Options:

| Option | Pros | Cons |
|--------|------|------|
| **`cisco-nso-prod`** (Cisco's choice) | Has ncs-netsim, battle-tested | Heavy image (~1GB), not the image's intended purpose |
| **`cisco-nso-build`** | Has ncs-netsim + build tools | Even heavier, overkill |
| **Custom netsim image** | Minimal, purpose-built | Extra build step, maintenance burden |

**Recommendation:** Use `cisco-nso-prod` (same as Cisco's example). The image is already pulled for the NSO service. No extra build needed.

#### Entrypoint Design: Script vs Inline Command

Cisco's inline command is hard to read and maintain. We should use a dedicated script:

```yaml
netsim:
  image: cisco-nso-prod:${NSO_VERSION}
  entrypoint: bash
  command: /setup-netsim.sh
  volumes:
    - type: bind
      source: ./scripts/setup-netsim.sh
      target: /setup-netsim.sh
    - type: bind
      source: ./neds
      target: /neds
    - type: volume
      source: netsim-vol
      target: /netsim-output
```

#### The PYTHONPATH Requirement

Cisco's example sets `PYTHONPATH=/opt/ncs/current/src/ncs/pyapi` before `ncs-netsim start`. This is because netsim uses Python internally. In the production image, this path may not be in the default PYTHONPATH.

**Verification needed:** Test whether `ncs-netsim start` works without the explicit PYTHONPATH in our NSO version. If not, set it as an environment variable in compose.

#### Separation of Concerns (Our Design vs Cisco's)

Cisco's netsim container does too much — it generates authgroup XML, modifies ncs.conf, and writes to the NSO container's volume. We split responsibilities:

| Responsibility | Cisco's Example | Our Design |
|----------------|-----------------|------------|
| Create netsim devices | Netsim container | Netsim container |
| Start netsim devices | Netsim container | Netsim container |
| Generate device XML | Netsim container | Netsim container |
| Generate authgroup XML | Netsim container (inline echo) | **Static file** (`init/authgroups.xml`) |
| Modify ncs.conf | Netsim container | **Pre-start script** (Story 2.2, already done) |
| Replace 127.0.0.1 | Netsim container (sed) | **`ncs-xml-init-remote`** (no sed needed) |

#### Volume Strategy for XML Sharing

The netsim container needs to output device XML to a location that NSO can read. Options:

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| **Shared named volume** | Netsim writes to volume, NSO reads | Clean separation | Must coordinate paths |
| **Bind mount directory** | Both containers bind-mount a host directory | Simple, inspectable | Platform-dependent paths |

**Recommendation:** Use a named volume (`netsim-vol`) mounted to a specific output path in the netsim container, and mount the same volume into the NSO container's CDB init path.

However, there's a subtlety: NSO's CDB init directory is `/nso/run/cdb/`, which is inside the `nso-cdb` named volume. We can't easily mount a second volume inside an existing volume mount.

**Alternative:** The netsim container writes to a staging volume, and a post-ncs-start script copies the XML into CDB. Or use `ncs_load -l -m` at runtime.

**Simplest approach:** Bind-mount a shared host directory (e.g., `./netsim-init/`) that:
- Netsim container writes device XML into
- NSO container bind-mounts as part of CDB init

#### Healthcheck

Cisco's example uses:
```yaml
healthcheck:
  test: test -f /nso-run-prod/etc/ncs.conf && ncs-netsim --dir /netsim is-alive ex0
```

Our healthcheck should verify netsim devices are running:
```yaml
healthcheck:
  test: ncs-netsim --dir /netsim is-alive
  interval: 5s
  retries: 5
  start_period: 15s
  timeout: 10s
```

Using `is-alive` without a device name checks all devices.

#### Container Lifecycle

The netsim container must:
1. Create the netsim network (one-time setup)
2. Start the devices
3. Generate device XML for NSO
4. Stay running (devices must remain alive for NSO to connect)

The `tail -f /dev/null` pattern at the end keeps the container alive after setup. An alternative is to run netsim in the foreground if it supports it, but `ncs-netsim start` backgrounds the ConfD processes, so `tail -f /dev/null` is the standard pattern.

#### NED Package Access

The netsim container needs access to the compiled NED packages to create devices. Options:

1. **Mount compiled packages volume:** Same `nso-packages` volume the build container outputs to.
2. **Mount raw NED directory:** If the NED is already compiled/extracted.

Since our build pipeline compiles NEDs into the `nso-packages` volume at `/nso/run/packages`, the netsim container should mount this same volume to access the compiled NEDs.

**The netsim `create-network` command needs the path to the NED package directory**, not individual files. The command is:
```bash
ncs-netsim create-network /nso/run/packages/<ned-package-name> $NETSIM_DEVICE_COUNT device
```

This means the setup script needs to discover which NED package to use. For v1, we can make this configurable via an environment variable (e.g., `NETSIM_NED_PACKAGE`).

---

## 6. Revised Netsim Architecture

Based on this research, here is the recommended netsim container design:

### setup-netsim.sh Script Outline

```bash
#!/bin/bash
set -e

NETSIM_DIR="/netsim"
NETSIM_OUTPUT="/netsim-output"
NED_PKG="${NETSIM_NED_PACKAGE:-/nso/run/packages/router}"
DEVICE_COUNT="${NETSIM_DEVICE_COUNT:-3}"
DEVICE_PREFIX="${NETSIM_DEVICE_PREFIX:-device}"
CONTAINER_HOSTNAME="${NETSIM_HOSTNAME:-netsim}"

# Set PYTHONPATH for netsim (may be required)
export PYTHONPATH="${PYTHONPATH:-/opt/ncs/current/src/ncs/pyapi}"

# Create netsim network (idempotent check)
if [ ! -d "$NETSIM_DIR/device" ]; then
    ncs-netsim --dir "$NETSIM_DIR" create-network "$NED_PKG" "$DEVICE_COUNT" "$DEVICE_PREFIX"
fi

# Start netsim devices
ncs-netsim --dir "$NETSIM_DIR" start

# Generate device onboarding XML with container hostname
ncs-netsim --dir "$NETSIM_DIR" ncs-xml-init-remote "$CONTAINER_HOSTNAME" \
    > "$NETSIM_OUTPUT/netsim-devices.xml"

# Keep container running
tail -f /dev/null
```

### compose.netsim.yaml Overlay Structure

```yaml
services:
  netsim:
    image: cisco-nso-prod:${NSO_VERSION}
    profiles:
      - netsim
    entrypoint: bash
    command: /setup-netsim.sh
    environment:
      NETSIM_DEVICE_COUNT: ${NETSIM_DEVICE_COUNT}
      NETSIM_HOSTNAME: netsim
    volumes:
      - type: bind
        source: ./scripts/setup-netsim.sh
        target: /setup-netsim.sh
      - type: volume
        source: nso-packages
        target: /nso/run/packages
        read_only: true
      - type: bind
        source: ./netsim-init
        target: /netsim-output
    healthcheck:
      test: ncs-netsim --dir /netsim is-alive
      interval: 5s
      retries: 5
      start_period: 15s
      timeout: 10s
    networks:
      - nso-net

  nso:
    depends_on:
      netsim:
        condition: service_healthy
    volumes:
      - type: bind
        source: ./netsim-init/netsim-devices.xml
        target: /nso/run/cdb/netsim-devices.xml
      - type: bind
        source: ./init/authgroups.xml
        target: /nso/run/cdb/authgroups.xml
```

### Open Questions for Implementation

1. **NED package discovery:** How to automatically find the right NED package path inside the container? The setup script needs to know the NED directory name. Options: env var, glob pattern, or convention-based (`/nso/run/packages/*-cli-*` or similar).

2. **PYTHONPATH verification:** Does `ncs-netsim start` work in the prod image without explicit PYTHONPATH? Must test.

3. **Netsim directory persistence:** Should `/netsim` be on a named volume? If yes, `create-network` is idempotent (skip if exists). If no, netsim is recreated every `docker compose up`. For dev/lab, ephemeral is fine.

4. **Bind mount for netsim-init:** The `./netsim-init/` directory must exist on the host before `docker compose up`. The netsim container writes `netsim-devices.xml` into it, and the NSO container reads it. This directory should be in `.gitignore` (generated content). **Alternative:** Use a named volume instead.

5. **Race condition:** NSO must not start before netsim has written the device XML. The `depends_on: condition: service_healthy` on NSO waiting for netsim should handle this — netsim's healthcheck passes only after devices are started, and the XML is written before the healthcheck could pass.

---

## Sources

- [Cisco NSO Network Simulator (ncs-netsim) Documentation — NSO 6.3](https://nso-docs.cisco.com/guides/nso-6.3/operation-and-usage/operations/network-simulator-netsim)
- [Cisco NSO Containerized Deployment — NSO 6.4](https://nso-docs.cisco.com/guides/nso-6.4/administration/installation-and-deployment/containerized-nso)
- [Cisco NSO NEDs and Adding Devices — NSO 6.1](https://nso-docs.cisco.com/guides/nso-6.1/operation-and-usage/operations/neds-and-adding-devices)
- [Cisco NSO Docker Compose Example (netsim-sshkey) — nso-docs.cisco.com](https://nso-docs.cisco.com/guides/nso-6.4/administration/installation-and-deployment/containerized-nso#sec.example-docker-compose)
- [NSO-developer/nso-docker — GitHub](https://github.com/NSO-developer/nso-docker)
- [NSO-developer/nso-examples (netsim-sshkey) — GitHub](https://github.com/NSO-developer/nso-examples/tree/6.4/getting-started/netsim-sshkey)
