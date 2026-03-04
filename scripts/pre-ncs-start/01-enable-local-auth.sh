#!/bin/bash
set -e

NCS_CONF="/etc/ncs/ncs.conf"
[[ -f "${NCS_CONF}" ]] || NCS_CONF="/nso/etc/ncs.conf"
[[ -f "${NCS_CONF}" ]] || NCS_CONF="/defaults/ncs.conf"

if [[ -f "${NCS_CONF}" ]]; then
    sed -i.bak '/<local-authentication>/{
n
s|<enabled>false</enabled>|<enabled>true</enabled>|
}' "${NCS_CONF}"
    rm -f "${NCS_CONF}.bak"
else
    echo "ERROR: ncs.conf not found in any expected location" >&2
    exit 1
fi
