#!/bin/bash
set -e

NETSIM_DEVICES_XML="${NETSIM_DEVICES_XML:-/netsim-output/netsim-devices.xml}"
NETSIM_AUTHGROUPS_XML="${NETSIM_AUTHGROUPS_XML:-/netsim-config/authgroups.xml}"
MAX_WAIT=60

waited=0
while [[ ! -f "${NETSIM_DEVICES_XML}" ]] && [[ ${waited} -lt ${MAX_WAIT} ]]; do
    echo "Waiting for netsim device XML at ${NETSIM_DEVICES_XML}... (${waited}s/${MAX_WAIT}s)"
    sleep 2
    waited=$((waited + 2))
done

if [[ ! -f "${NETSIM_DEVICES_XML}" ]]; then
    echo "No netsim device XML found at ${NETSIM_DEVICES_XML} after ${MAX_WAIT}s, skipping device onboarding"
    exit 0
fi

echo "Loading netsim authgroup configuration..."
if [[ -f "${NETSIM_AUTHGROUPS_XML}" ]]; then
    ncs_load -l -m "${NETSIM_AUTHGROUPS_XML}"
else
    echo "ERROR: Authgroup XML not found at ${NETSIM_AUTHGROUPS_XML}" >&2
    exit 1
fi

echo "Loading netsim device configuration..."
ncs_load -l -m "${NETSIM_DEVICES_XML}"

echo "Netsim device onboarding complete"
