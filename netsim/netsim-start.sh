#!/bin/bash
set -euo pipefail

NETSIM_DIR="/netsim"
OUTPUT_DIR="/netsim-output"
DEVICE_COUNT="${NETSIM_DEVICE_COUNT:-3}"
DEVICE_PREFIX="${NETSIM_DEVICE_PREFIX:-device}"
CONTAINER_HOSTNAME="${NETSIM_HOSTNAME:-netsim}"
PACKAGES_DIR="/nso/run/packages"

export PYTHONPATH="${PYTHONPATH:-/opt/ncs/current/src/ncs/pyapi}"

discover_ned_package() {
    local pkg
    for pkg in "${PACKAGES_DIR}"/*/; do
        if [[ -d "${pkg}src/yang" ]] || [[ -f "${pkg}package-meta-data.xml" ]]; then
            echo "${pkg%/}"
            return 0
        fi
    done
    echo "ERROR: No NED package found in ${PACKAGES_DIR}" >&2
    exit 1
}

NED_PACKAGE="$(discover_ned_package)"
echo "Using NED package: ${NED_PACKAGE}"

if [[ ! -d "${NETSIM_DIR}/device" ]]; then
    echo "Creating ${DEVICE_COUNT} netsim devices with prefix '${DEVICE_PREFIX}'..."
    ncs-netsim --dir "${NETSIM_DIR}" create-network "${NED_PACKAGE}" "${DEVICE_COUNT}" "${DEVICE_PREFIX}"
else
    echo "Netsim devices already exist in ${NETSIM_DIR}, skipping creation"
fi

echo "Starting netsim devices..."
ncs-netsim --dir "${NETSIM_DIR}" start

mkdir -p "${OUTPUT_DIR}"
echo "Generating device XML with hostname '${CONTAINER_HOSTNAME}'..."
ncs-netsim --dir "${NETSIM_DIR}" ncs-xml-init \
    | sed "s/127.0.0.1/${CONTAINER_HOSTNAME}/g" \
    > "${OUTPUT_DIR}/netsim-devices.xml"
echo "Device XML written to ${OUTPUT_DIR}/netsim-devices.xml"

echo "Netsim devices running — keeping container alive"
tail -f /dev/null
