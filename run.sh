#!/bin/bash

if [ -n "${EASYDNS_USER}" ] && [ -n "${EASYDNS_TOKEN}" ] && [ -n "${EASYDNS_HOSTNAME}" ]; then
  echo "Setting EasyDNS Dynamic IP Address"
  wget -O - https://${EASYDNS_USER}:${EASYDNS_TOKEN}@api.cp.easydns.com/dyn/generic.php?hostname=${EASYDNS_HOSTNAME} > /dev/null
fi

if [ "${SSL_CERT}" = "**None**" ]; then
    unset SSL_CERT
fi

if [ "${DEFAULT_SSL_CERT}" = "**None**" ]; then
    unset DEFAULT_SSL_CERT
fi

exec python /haproxy/main.py
