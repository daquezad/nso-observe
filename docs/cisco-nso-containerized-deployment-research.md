# Cisco NSO Containerized Deployment: Research Notes

**Sources:**
1. [NSO Docs - Containerized NSO](https://nso-docs.cisco.com/guides/administration/installation-and-deployment/containerized-nso)
2. [nso-examples/netsim-sshkey](https://github.com/NSO-developer/nso-examples/tree/6.6/getting-started/netsim-sshkey)
3. [sshkey-deployment-example](https://github.com/NSO-developer/sshkey-deployment-example) (container-based variant)

---

## 1. Overview: Build vs Production Images

| Image | Purpose | Base |
|-------|---------|------|
| **Build Image** (`cisco-nso-build:VERSION`) | Compile NSO packages (NEDs, services) | Red Hat UBI + Ant, JDK, net-tools, pip, etc. |
| **Production Image** (`cisco-nso-prod:VERSION`) | Run NSO, load compiled packages | System Install equivalent |

Build Image adds dev tools for building packages. Production Image is runtime-only.

---

## 2. Build Container: Package Compilation Workflow

### Commands run inside the Build container

**From NSO docs (canonical example):**

```bash
# 1. Copy packages from NSO examples (or host) into NCS_RUN_DIR
docker exec -it build-nso-pkgs sh -c 'cp -r ${NCS_DIR}/examples.ncs/getting-started/netsim-sshkey/packages ${NCS_RUN_DIR}'

# 2. Compile all packages (per-package Makefile in src/)
docker exec -it build-nso-pkgs sh -c 'for f in ${NCS_RUN_DIR}/packages/*/src; do make -C "$f" all || exit 1; done'
```

**From sshkey-deployment-example (compose.yaml):**

The `BUILD-NSO-PKGS` service uses a single `command` that copies and compiles:

```yaml
command: -c 'cp -r /${NSOAPP_NAME}/package-store/* /nso/run/packages/
&& make -C /nso/run/packages/distkey/src all
&& make -C /nso/run/packages/ne/src all'
```

So the build workflow is:
1. **Copy** source packages into `/nso/run/packages/`
2. **Compile** each package: `make -C <package>/src all`

---

## 3. How Packages Are Shared: Build ↔ Prod

### Mechanism: **Shared volume** or **Bind mount**

Both Build and Production containers mount the **same** packages directory.

**NSO docs (bind mount example):**

```yaml
# Production container
volumes:
  - type: bind
    source: /path/to/packages/NSO-1
    target: /nso/run/packages

# Build container - SAME bind mount
volumes:
  - type: bind
    source: /path/to/packages/NSO-1
    target: /nso/run/packages
```

**sshkey-deployment-example (named volume):**

```yaml
volumes:
  packages:

# Production (NODE-NSO)
volumes:
  - type: volume
    source: packages
    target: /nso/run/packages/

# Build (BUILD-NSO-PKGS)
volumes:
  - type: volume
    source: packages
    target: /nso/run/packages/
```

### Mount path (both containers)

| Container | Mount target |
|-----------|--------------|
| Build | `/nso/run/packages` |
| Prod  | `/nso/run/packages` |

`NCS_RUN_DIR` defaults to `/nso/run`; the packages load path is `$NCS_RUN_DIR/packages` (from `ncs.conf`).

---

## 4. Docker Compose Structure (Cisco Docs Example)

Full example from NSO docs (`docker-compose.yaml`):

```yaml
version: '1.0'
volumes:
  NSO-1-rvol:

networks:
  NSO-1-net:

services:
  NSO-1:
    image: cisco-nso-prod:6.4
    container_name: nso1
    profiles:
      - prod
    environment:
      - EXTRA_ARGS=--with-package-reload
      - ADMIN_USERNAME=admin
      - ADMIN_PASSWORD=admin
    networks:
      - NSO-1-net
    ports:
      - "2024:2024"
      - "8888:8888"
    volumes:
      - type: bind
        source: /path/to/packages/NSO-1
        target: /nso/run/packages
      - type: bind
        source: /path/to/log/NSO-1
        target: /log
      - type: volume
        source: NSO-1-rvol
        target: /nso
    healthcheck:
      test: ncs_cmd -c "wait-start 2"
      interval: 5s
      retries: 5
      start_period: 10s
      timeout: 10s

  BUILD-NSO-PKGS:
    image: cisco-nso-build:6.4
    container_name: build-nso-pkgs
    network_mode: none
    profiles:
      - build
    volumes:
      - type: bind
        source: /path/to/packages/NSO-1
        target: /nso/run/packages

  EXAMPLE:
    image: cisco-nso-prod:6.4
    container_name: ex-netsim
    profiles:
      - example
    networks:
      - NSO-1-net
    healthcheck:
      test: test -f /nso-run-prod/etc/ncs.conf && ncs-netsim --dir /netsim is-alive ex0
      interval: 5s
      retries: 5
      start_period: 10s
      timeout: 10s
      entrypoint: bash
    command: -c 'rm -rf /netsim && mkdir /netsim && ncs-netsim --dir /netsim create-network /network-element 1 ex ...'
    volumes:
      - type: bind
        source: /path/to/packages/NSO-1/ne
        target: /network-element
      - type: volume
        source: NSO-1-rvol
        target: /nso-run-prod
```

### Profiles

| Profile   | Services                    |
|-----------|-----------------------------|
| `prod`    | NSO-1 (Production NSO)      |
| `build`   | BUILD-NSO-PKGS (compilation)|
| `example` | EXAMPLE (netsim device)     |

---

## 5. Build Container Lifecycle: Stay Running vs Exit

### Cisco docs workflow (stays running)

```bash
# Start build container (keeps running in background)
docker compose --profile build up -d

# Run compilation via docker exec
docker exec -it build-nso-pkgs sh -c 'for f in ${NCS_RUN_DIR}/packages/*/src; do make -C "$f" all || exit 1; done'
```

The build container is started with `up -d` and **stays running**. Compilation is done via `docker exec`.

### sshkey-deployment-example (exits after compile)

```bash
docker compose --profile build up
```

Here the Build service uses a `command` that runs `cp` + `make` and then **exits** when done (no long-running process). `docker compose up` runs it once and the container stops after compilation completes.

---

## 6. Canonical `demo.sh` Script (NSO docs)

```bash
#!/bin/bash
set -eu

printf "${GREEN}##### Reset the container setup\n${NC}";
docker compose --profile build down
docker compose --profile example down -v
docker compose --profile prod down -v
rm -rf ./packages/NSO-1/* ./log/NSO-1/*

printf "${GREEN}##### Start the build container used for building the NSO NED and service packages\n${NC}"
docker compose --profile build up -d

printf "${GREEN}##### Get the packages\n${NC}"
printf "${PURPLE}##### NOTE: Normally you populate the package directory from the host. Here, we use packages from an NSO example\n${NC}"
docker exec -it build-nso-pkgs sh -c 'cp -r ${NCS_DIR}/examples.ncs/getting-started/netsim-sshkey/packages ${NCS_RUN_DIR}'

printf "${GREEN}##### Build the packages\n${NC}"
docker exec -it build-nso-pkgs sh -c 'for f in ${NCS_RUN_DIR}/packages/*/src; do make -C "$f" all || exit 1; done'

printf "${GREEN}##### Start the simulated device container and setup the example\n${NC}"
docker compose --profile example up --wait

printf "${GREEN}##### Start the NSO prod container\n${NC}"
docker compose --profile prod up --wait

printf "${GREEN}##### Showcase the netsim-sshkey example from NSO on the prod container\n${NC}"
# ... showcase.sh ...
```

---

## 7. Key Paths Summary

| Path                     | Purpose                                  |
|--------------------------|------------------------------------------|
| `/nso/run/packages`      | Package load path (build & prod)         |
| `/nso/run`               | NSO runtime dir (CDB, state, backups)    |
| `/nso/etc`               | ncs.conf, SSH keys, SSL certs            |
| `/log`                   | Log output                               |
| `$NCS_RUN_DIR`           | Default `/nso/run`                       |
| `$NCS_DIR`               | NSO install root (e.g. `/opt/ncs/current`) |

---

## 8. Build Container Details

- **image**: `cisco-nso-build:VERSION`
- **network_mode**: `none` (Cisco docs) – no network access during build
- **profiles**: `build` (started separately from prod)
- **No Dockerfile** for Build – use Cisco’s pre-built image as-is.

---

## 9. Netsim (EXAMPLE) Container

- Reuses `cisco-nso-prod` image.
- Custom entrypoint/command to:
  1. Create netsim network: `ncs-netsim --dir /netsim create-network /network-element 1 ex`
  2. Start netsims: `ncs-netsim --dir /netsim start`
  3. Generate `init1.xml`, `init2.xml`, `ncs.conf` into shared volume.
  4. Keep running: `tail -f /dev/null`
- Mounts:
  - `/path/to/packages/NSO-1/ne` → `/network-element`
  - `NSO-1-rvol` → `/nso-run-prod` (share CDB/config with NSO Prod)
