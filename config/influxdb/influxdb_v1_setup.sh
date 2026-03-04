#!/bin/bash
set -e

nso_bucket_id=$(influx bucket find --name "${DOCKER_INFLUXDB_INIT_BUCKET}" --hide-headers | awk '{print $1}')

influx v1 auth create \
  --username "${V1_AUTH_USERNAME}" \
  --password "${V1_AUTH_PASSWORD}" \
  --write-bucket "${nso_bucket_id}" \
  --org "${DOCKER_INFLUXDB_INIT_ORG}"
