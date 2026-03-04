# Cisco NSO Production Image – Internal Behavior

**Source:** [Containerized NSO Documentation](https://nso-docs.cisco.com/guides/administration/installation-and-deployment/containerized-nso)

Structured notes on `run-nso.sh`, default `ncs.conf`, environment variables, scripts, and related behavior.

---

## 1. ncs.conf preference order

The `run-nso.sh` script checks at startup to choose which `ncs.conf` to use. Order:

| Priority | Location | Notes |
|----------|----------|-------|
| **1st** | `/etc/ncs/` | Via Dockerfile `ENV NCS_CONFIG_DIR /etc/ncs/` (if ncs.conf present) |
| **2nd** | `/nso/etc/` | Mounted configuration directory in the run layout |
| **Fallback** | `/defaults/` | Default `ncs.conf` bundled in the NSO image when no file at either above path |

**Note:** If `ncs.conf` is edited after startup, reload with MAAPI `reload_config()` or: `ncs_cmd -c "reload"`.

**Warning:** Overriding `NCS_CONFIG_DIR`, `NCS_LOG_DIR`, `NCS_RUN_DIR`, etc. is not supported and should be avoided. Mount config under `/nso/etc` instead.

---

## 2. Default ncs.conf environment variables (interfaces)

The default `ncs.conf` in `/defaults` uses environment variables to enable northbound interfaces. **All interfaces are disabled by default.** Set to `true` to enable.

| Variable | Effect | Port |
|----------|--------|------|
| `NCS_NETCONF_TRANSPORT_TCP` | NETCONF over TCP | 2023 |
| `NCS_NETCONF_TRANSPORT_SSH` | NETCONF over SSH | 2022 |
| `NCS_WEBUI_TRANSPORT_SSL` | JSON-RPC and RESTCONF over SSL/TLS | 8888 |
| `NCS_WEBUI_TRANSPORT_TCP` | JSON-RPC and RESTCONF over TCP | 8080 |
| `NCS_CLI_SSH` | CLI over SSH | 2024 |

These are the documented variables. No ports are exposed externally unless enabled in `ncs.conf`.

---

## 3. Admin user creation (ADMIN_USERNAME, ADMIN_PASSWORD, ADMIN_SSHKEY)

Three environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `ADMIN_USERNAME` | Username for the admin user | `admin` |
| `ADMIN_PASSWORD` | Password for the admin user | (none) |
| `ADMIN_SSHKEY` | Private SSH key for the admin user | (none) |

**Behavior:**

- Only `ADMIN_PASSWORD` or `ADMIN_SSHKEY` must be set; `ADMIN_USERNAME` has a default.
- Example: `docker run -e ADMIN_PASSWORD=admin cisco-nso-prod:6.4`
- Intended for CI/testing; usually not used in production where CDB already has users.

### Local authentication caveat

The default `ncs.conf` uses only Linux PAM, with **local authentication disabled**.

For `ADMIN_USERNAME`, `ADMIN_PASSWORD`, and `ADMIN_SSHKEY` to work, one of:

1. Enable local authentication in NSO: `/ncs-conf/aaa/local-authentication` → `enabled`
2. Or create a local Linux admin user that NSO authenticates via Linux PAM

### CDB persistence caveat

With a **persistent volume for CDB** and repeated restarts with different `ADMIN_USERNAME`/`ADMIN_PASSWORD`:

- The script generates `add_admin_user.xml` and puts it in the CDB directory.
- If an existing CDB config file is already there, NSO does **not** load XML at startup.
- You must load the generated `add_admin_user.xml` manually in that case.

---

## 4. Pre- and post-start scripts

| Directory | Purpose |
|-----------|---------|
| `$NCS_CONFIG_DIR/pre-ncs-start.d/` | Scripts run **before** `ncs` starts |
| `$NCS_CONFIG_DIR/post-ncs-start.d/` | Scripts run **after** `ncs` starts |

**Details:**

- Scripts can be **Python** and/or **Bash**.
- `run-nso.sh` invokes them automatically.
- `$NCS_CONFIG_DIR` is typically `/etc/ncs` or `/nso/etc`.

**Example:** `/etc/ncs/post-ncs-start.d/10-cron-logrotate.sh` – handles logrotate via cron (`CRON_ENABLE` and `LOGROTATE_ENABLE` in `/etc/logrotate.conf`).

---

## 5. take-ownership.sh

| Property | Detail |
|----------|--------|
| Role | Takes ownership of directories NSO needs |
| When | One of the first steps in startup |
| Override | Yes – you can override the script to take ownership of extra dirs (e.g. mounted volumes, bind mounts) |

**Migration note:** If migrating from older container images where NSO ran as root, ensure the `nso` user owns or can access required files (app dirs, SSH host keys, device SSH keys, etc.).

---

## 6. Health check

| Property | Value |
|----------|-------|
| Mechanism | `ncs_cmd` to get NCS state |
| Observed | Only the result status – whether `ncs_cmd` can talk to the `ncs` process (IPC) |
| Default `--health-start-period` | **60 seconds** |
| Behavior | NSO is marked **unhealthy** if it takes more than 60 seconds to start |

**Recommendations:**

- If startup takes longer: increase `--health-start-period` (e.g. `600`).
- To turn off: `--no-healthcheck`.

**Example Compose overrides:**

```yaml
healthcheck:
  test: ncs_cmd -c "wait-start 2"
  interval: 5s
  retries: 5
  start_period: 10s   # Override if needed (e.g. 600s)
  timeout: 10s
```

---

## 7. EXTRA_ARGS (startup arguments)

| Property | Detail |
|----------|--------|
| Purpose | Pass extra arguments to the NSO start command |
| Check order | `EXTRA_ARGS` is checked **before** the `CMD` instruction |
| ENTRYPOINT | `/run-nso.sh` (doc sometimes says `/nso-run.sh` – assume `run-nso.sh`) |

**Example with EXTRA_ARGS:**

```bash
docker run -e EXTRA_ARGS='--with-package-reload --ignore-initial-validation' -itd cisco-nso-prod:6.4
```

**Example with CMD:**

```bash
docker run -itd cisco-nso-prod:6.4 --with-package-reload --ignore-initial-validation
```

---

## 8. SSH host key generation

| Property | Detail |
|----------|--------|
| Expected key | `ssh_host_ed25519_key` in `/nso/etc/ssh` |
| If present | Used as-is; unchanged across restarts or upgrades (with persistent volume) |
| If absent | Script generates private and public key automatically |

**HA note:** In HA setups, the same host key is usually shared by all nodes (via shared persistent volume) so clients do not need to re-fetch it after failover.

---

## 9. HTTPS TLS self-signed certificate

| Property | Detail |
|----------|--------|
| Expected paths | `/nso/ssl/cert/host.cert`, `/nso/ssl/cert/host.key` |
| If present | Used as-is (typical when `/nso` is on a persistent volume) |
| If absent | Self-signed cert generated; valid **30 days** |
| Intended use | Development and staging; **not** for production |

**Generation command (same logic as the script):**

```bash
openssl req -new -newkey rsa:4096 -x509 -sha256 -days 30 -nodes \
  -out /nso/ssl/cert/host.cert -keyout /nso/ssl/cert/host.key \
  -subj "/C=SE/ST=NA/L=/O=NSO/OU=WebUI/CN=Mr. Self-Signed"
```

**Recommendation:** Replace with a proper CA-signed certificate for production (and preferably for test/staging).

---

## 10. Backup and restore (certs excluded)

When running NSO in a container:

- `ncs-backup` does **not** include SSH and SSL certificates.
- Outside containers, the default path `/etc/ncs` stores SSH and SSL certs (`/etc/ncs/ssh`, `/etc/ncs/ssl`).

---

## 11. Script name discrepancy

The docs use both:

- `/run-nso.sh` (main references)
- `/nso-run.sh` (in the “Startup Arguments” section)

Assume the actual script is `run-nso.sh` unless your image shows otherwise.

---

## Quick reference: environment variables summary

| Variable | Purpose |
|----------|---------|
| `NCS_CLI_SSH` | Enable CLI over SSH (port 2024) |
| `NCS_WEBUI_TRANSPORT_TCP` | Enable JSON-RPC/RESTCONF over TCP (port 8080) |
| `NCS_WEBUI_TRANSPORT_SSL` | Enable JSON-RPC/RESTCONF over SSL (port 8888) |
| `NCS_NETCONF_TRANSPORT_SSH` | Enable NETCONF over SSH (port 2022) |
| `NCS_NETCONF_TRANSPORT_TCP` | Enable NETCONF over TCP (port 2023) |
| `ADMIN_USERNAME` | Admin username (default: `admin`) |
| `ADMIN_PASSWORD` | Admin password |
| `ADMIN_SSHKEY` | Admin private SSH key |
| `EXTRA_ARGS` | Extra args for NSO start (checked before CMD) |

---

## Gotchas / caveats

1. Local auth disabled by default – `ADMIN_*` only work if local auth is enabled or a Linux PAM user is set up.
2. CDB persistence – different `ADMIN_*` on each restart with existing CDB may require manual loading of `add_admin_user.xml`.
3. Health start period 60s – long startups may be marked unhealthy; increase `--health-start-period`.
4. No override of `NCS_CONFIG_DIR`, `NCS_RUN_DIR`, etc.; mount config under `/nso/etc`.
5. Self-signed TLS cert valid 30 days – replace for production and preferably for staging.
6. NSO runs as non-root user `nso`; ensure ownership/permissions for SSH keys, app dirs, etc.
