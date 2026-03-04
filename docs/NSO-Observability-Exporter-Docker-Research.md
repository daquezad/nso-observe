# Cisco NSO Observability Exporter — Docker Multi-Container Setup Research

Research notes from [nso-docs.cisco.com/resources](https://nso-docs.cisco.com/resources) and related documentation.

---

## 1. Containers Created by compose.yaml

The documentation states that `compose.yaml` is provided in the OE package's `setup/` folder and creates the following containers (inferred from setup.sh flags and output URLs):

| Container      | Purpose                                           | Confirmed By                         |
|----------------|---------------------------------------------------|--------------------------------------|
| **OTel Collector** | Receives OTLP traces/metrics from NSO, forwards to backends | setup.sh `--otelcol-grpc`, `--otelcol-http` |
| **Jaeger**     | Trace visualization                               | Output URL: `http://127.0.0.1:12346` |
| **InfluxDB**   | Time-series metrics storage                       | setup.sh `--influxdb`                |
| **Grafana**    | Dashboards (InfluxDB + Jaeger)                    | Output URL: `http://127.0.0.1:12349` |
| **Prometheus** | Metrics backend (OTel Collector can export here)  | Output URL: `http://127.0.0.1:12348` |

**Note:** The actual `compose.yaml` content is **not** published publicly; it is included in the NSO Observability Exporter package downloaded from CCO (Cisco Connection Online). The documentation describes a "diagram" of container interconnectivity but does not show the compose file itself.

---

## 2. setup.sh Script — Flags and Behavior

### Location

```
$ sh ncs-6.2-observability-exporter-1.2.0.signed.bin
$ tar -xzf ncs-6.2-observability-exporter-1.2.0.tar.gz
$ cd observability-exporter/setup
$ chmod u+x setup.sh
```

### Flags (from documentation examples)

| Flag | Purpose | Example Value |
|------|---------|---------------|
| `--otelcol-grpc` | OTel Collector gRPC port | `12344` |
| `--otelcol-http` | OTel Collector HTTP port | `12345` |
| `--jaeger` | Jaeger UI port | `12346` |
| `--influxdb` | InfluxDB port | `12347` |
| `--influxdb-user` | InfluxDB username | `admin` |
| `--influxdb-password` | InfluxDB password | `admin123` |
| `--influxdb-token` | InfluxDB 2.x API token (for v1 auth) | `my-token` |
| `--prometheus` | Prometheus port | `12348` |
| `--grafana` | Grafana port | `12349` |
| `--otelcol-cert-path` | TLS certificate path (HTTPS/gRPC Secure) | `/path/to/certificate.crt` |
| `--otelcol-key-path` | TLS private key path | `/path/to/privatekey.key` |
| `--down` | Bring down containers only | — |
| `--remove-volumes` | Bring down containers and remove volumes | Used with `--down` |
| `--help` | Print help and default values | — |

### Defaults (when run without arguments)

- Uses default ports defined in the script
- Uses default InfluxDB username and password

### Example invocations

```bash
# Default values
./setup.sh

# Custom ports and InfluxDB config
./setup.sh --otelcol-grpc 12344 --otelcol-http 12345 --jaeger 12346 \
  --influxdb 12347 --influxdb-user admin --influxdb-password admin123 \
  --influxdb-token my-token --prometheus 12348 --grafana 12349

# Secure (TLS) variant
./setup.sh --otelcol-cert-path /path/to/certificate.crt \
  --otelcol-key-path /path/to/privatekey.key

# Teardown
./setup.sh --down
./setup.sh --down --remove-volumes
```

### Output

The script prints:
1. **NSO configuration XML** to configure the Observability Exporter
2. **URLs** to visit Jaeger, Grafana, and Prometheus

---

## 3. Default Ports by Service

| Service        | Default Port | Host URL Example       |
|----------------|-------------|-------------------------|
| OTel Collector gRPC | 12344  | —                       |
| OTel Collector HTTP | 12345  | NSO sends OTLP here     |
| Jaeger         | 12346       | http://127.0.0.1:12346  |
| InfluxDB       | 12347       | localhost:12347         |
| Prometheus     | 12348       | http://127.0.0.1:12348  |
| Grafana        | 12349       | http://127.0.0.1:12349  |
| InfluxDB (standard) | 8086   | http://localhost:8086   |
| Jaeger (standalone) | 16686   | http://localhost:16686  |

---

## 4. OTel Collector Configuration (otelcol.yaml)

The documentation does **not** include the default `otelcol.yaml` from the OE package. It shows custom configs for:

- **Splunk Observability Cloud** (sapm + signalfx exporters)
- **Splunk Enterprise** (splunk_hec exporters)

Typical responsibilities for the OE stack:
- **Receivers:** OTLP (traces, metrics) from NSO
- **Exporters:** Jaeger, Prometheus, InfluxDB (or Splunk)

For Splunk Enterprise, the doc shows this pattern:

```yaml
exporters:
  splunk_hec/traces:
    token: "<YOUR_HEC_TOKEN_FOR_TRACES>"
    endpoint: "http://<your_splunk_server_ip>:8088/services/collector"
    index: "nso_traces"
    tls:
      insecure_skip_verify: true
  splunk_hec/metrics:
    token: "<YOUR_HEC_TOKEN_FOR_TRACES>"
    endpoint: "http://<your_splunk_server_ip>:8088/services/collector"
    index: "nso_metrics"
    tls:
      insecure_skip_verify: true

service:
  pipelines:
    traces:
      exporters: [splunk_hec/traces]
    metrics:
      exporters: [splunk_hec/metrics]
```

For the Docker stack, a reasonable minimal structure would be receivers for OTLP traces and metrics, and exporters for Jaeger, Prometheus, and InfluxDB. The exact file is in the OE package.

---

## 5. NSO Configuration XML

### Standard HTTP (from setup.sh output)

```xml
<config xmlns="http://tail-f.com/ns/config/1.0">
  <progress xmlns="http://tail-f.com/ns/progress">
    <export xmlns="http://tail-f.com/ns/observability-exporter">
      <enabled>true</enabled>
      <influxdb>
        <host>localhost</host>
        <port>12347</port>
        <username>admin</username>
        <password>admin123</password>
      </influxdb>
      <otlp>
        <port>12345</port>
        <transport>http</transport>
        <metrics>
          <port>12345</port>
        </metrics>
      </otlp>
    </export>
  </progress>
</config>
```

### C-Style (CLI equivalent)

```nso
progress export enabled
progress export influxdb host localhost
progress export influxdb port 12347
progress export influxdb username admin
progress export influxdb password admin123
progress export otlp host localhost
progress export otlp port 12345
progress export otlp transport http
```

### J-Style

```nso
progress {
    export {
        enabled;
        influxdb {
            host     localhost;
            port     12347;
            username admin;
            password admin123;
        }
        otlp {
            host      localhost;
            port      12345;
            transport http;
        }
    }
}
```

### HTTPS/TLS variant

For OTLP over HTTPS, configure `server-certificate-path` (root CA PEM) for both traces and metrics:

```xml
<config xmlns="http://tail-f.com/ns/config/1.0">
  <progress xmlns="http://tail-f.com/ns/progress">
    <export xmlns="http://tail-f.com/ns/observability-exporter">
      <otlp>
        <endpoint><endpoint></endpoint>
        <server-certificate-path>/path/to/rootCA.pem</server-certificate-path>
        <service_name>nso</service_name>
        <transport>https</transport>
        <metrics>
          <endpoint><endpoint></endpoint>
          <server-certificate-path>/path/to/rootCA.pem</server-certificate-path>
        </metrics>
      </otlp>
    </export>
  </progress>
</config>
```

**Note:** There is a typo in the doc: `server-certificate-pathh`; the correct element is `server-certificate-path`.

---

## 6. InfluxDB v1 API Access for InfluxDB 2.x

The Observability Exporter uses the **InfluxDB v1 API**. With InfluxDB 2.x you must create v1-compatible credentials.

### Steps

1. Create org and bucket (e.g. `my-org`, `nso`):

   ```bash
   influx bucket list --org my-org
   ```

   Note the bucket ID (e.g. `5d744e55fb178310`).

2. Create v1 auth:

   ```bash
   influx v1 auth create --org my-org \
     --username nso \
     --password nso123nso \
     --write-bucket BUCKET_ID
   ```

3. Configure NSO with the same username/password. The `database` name in NSO should match the bucket name (`nso`).

### Auth options (InfluxDB 2.x docs)

- **Token:** `Authorization: Token INFLUX_API_TOKEN`
- **Username/password:** Query string `u=`/`p=` or Basic auth  
- v1 username/password is **separate** from the InfluxDB 2.x UI login

Source: [InfluxDB v2 API Guide - InfluxDB 1.x compatibility](https://docs.influxdata.com/influxdb/v2/api-guide/influxdb-1x/)

---

## 7. Grafana Configuration

### Data source JSON

Download: [influxdb-data-source.json](https://pubhub.devnetcloud.com/media/nso/docs/addons/observability-exporter/influxdb-data-source.json)

```json
{
  "id": 2,
  "orgId": 1,
  "name": "InfluxDB",
  "type": "influxdb",
  "typeLogoUrl": "public/app/plugins/datasource/influxdb/img/influxdb_logo.svg",
  "access": "proxy",
  "url": "http://influxdb:8086",
  "basicAuth": false,
  "isDefault": false,
  "jsonData": {
    "version": "Flux",
    "defaultBucket": "nso",
    "organization": "my-org",
    "httpMode": "POST"
  },
  "secureJsonData": {
    "token": "my-token"
  },
  "readOnly": false
}
```

- Replace `"my-token"` with the InfluxDB API token.
- For Docker, `url` should point to the InfluxDB service (e.g. `http://influxdb:8086`).

### Importing the data source

```bash
curl -i "http://admin:admin@127.0.0.1:3000/api/datasources" \
  -m 5 -X POST --noproxy '*' \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data @influxdb-data-source.json
```

### Pre-built dashboard JSON

- Download: [dashboard-nso-local.json](https://pubhub.devnetcloud.com/media/nso/docs/addons/observability-exporter/dashboard-nso-local.json)
- gnetId: 14353
- Panels: Transaction throughput, longest transactions, locks, queue length, service durations, device locks, etc.

### Dashboard inputs

- `DS_INFLUXDB`: InfluxDB datasource (e.g. `"InfluxDB"`)
- `INPUT_JAEGER_BASE_URL`: Jaeger UI base URL (e.g. `http://127.0.0.1:12346/`)

### Import command (requires jq)

```bash
curl -i "http://admin:admin@127.0.0.1:3000/api/dashboards/import" \
  -m 5 -X POST -H "Accept: application/json" --noproxy '*' \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data-binary "$(jq '{"dashboard": . , "overwrite": true, "inputs":[
    {"name":"DS_INFLUXDB","type":"datasource", "pluginId":"influxdb","value":"InfluxDB"},
    {"name":"INPUT_JAEGER_BASE_URL","type":"constant","value":"http://127.0.0.1:12346/"}
  ]}' dashboard-nso-local.json)"
```

### Optional: set as default dashboard

```bash
curl -i 'http://admin:admin@127.0.0.1:3000/api/org/preferences' \
  -m 5 -X PUT --noproxy '*' \
  -H 'X-Grafana-Org-Id: 1' \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data-binary "{\"homeDashboardId\":$(curl -m 5 --noproxy '*' 'http://admin:admin@127.0.0.1:3000/api/dashboards/uid/nso' 2>/dev/null | jq .dashboard.id)}"
```

---

## 8. NSO Packages Required

- **Package name:** `observability-exporter`
- **Installation:** Copy package into NSO `packages/` directory and reload
- **Verification:** `show packages package observability-exporter` in NSO CLI

---

## 9. Python Dependencies

From `src/requirements.txt` in the package folder:

```
parsedatetime
opentelemetry-exporter-otlp
influxdb
```

Install:

```bash
pip install -r src/requirements.txt
```

Run from the package root (e.g. `observability-exporter/`).

---

## 10. Secure (TLS) Variant

### setup.sh TLS flags

```bash
./setup.sh --otelcol-cert-path /path/to/certificate.crt \
  --otelcol-key-path /path/to/privatekey.key
```

- OTel Collector uses these for HTTPS and gRPC Secure.

### Creating self-signed certificates

```bash
# Root CA
openssl genrsa -out rootCA.key 2048
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.pem

# Server cert
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr
openssl x509 -req -in server.csr -CA rootCA.pem -CAkey rootCA.key \
  -CAcreateserial -out server.crt -days 365 -sha256
```

- Use `server.crt` and `server.key` for the OTel Collector.
- Add `rootCA.pem` to NSO's trust store via `server-certificate-path` in the config.

### NSO config for HTTPS OTLP

- Set `transport` to `https`.
- Set `server-certificate-path` to `/path/to/rootCA.pem` for traces and metrics.
- Set `endpoint` for each (traces and metrics).

---

## Summary of Unpublished Artifacts

The following are shipped in the OE package from CCO and are **not** in public repos:

- `observability-exporter/setup/compose.yaml` — full service definitions
- `observability-exporter/setup/setup.sh` — complete script and defaults
- `observability-exporter/setup/otelcol.yaml` — default OTel Collector config
- Any other config files referenced by setup

To obtain them: download the Observability Exporter package from CCO, extract it, and inspect the `setup/` directory.

---

## References

- [NSO Observability Exporter - nso-docs.cisco.com](https://nso-docs.cisco.com/resources)
- [InfluxDB 1.x compatibility API](https://docs.influxdata.com/influxdb/v2/api-guide/influxdb-1x/)
- [Grafana InfluxDB data source JSON](https://pubhub.devnetcloud.com/media/nso/docs/addons/observability-exporter/influxdb-data-source.json)
- [NSO Dashboard JSON](https://pubhub.devnetcloud.com/media/nso/docs/addons/observability-exporter/dashboard-nso-local.json)
