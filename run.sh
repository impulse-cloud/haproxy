#!/bin/bash

if [ -n "${EASYDNS_USER}" ] && [ -n "${EASYDNS_TOKEN}" ] && [ -n "${EASYDNS_HOSTNAME}" ]; then
  echo "Setting EasyDNS Dynamic IP Address"
  wget -O - https://${EASYDNS_USER}:${EASYDNS_TOKEN}@api.cp.easydns.com/dyn/generic.php?hostname=${EASYDNS_HOSTNAME} > /dev/null
fi

if [ "${VIRTUAL_HOST}" = "**None**" ]; then
    unset VIRTUAL_HOST
fi

if [ "${SSL_CERT}" = "**None**" ]; then
    unset SSL_CERT
fi

if [ "${BACKEND_PORTS}" = "**None**" ]; then
    unset BACKEND_PORTS
fi

if [ -n "$SSL_CERT" ]; then
    echo "SSL certificate provided!"
    echo -e "${SSL_CERT}" > /servercert.pem
    export SSL="ssl crt /servercert.pem"
else
    echo "No SSL certificate provided"
fi

exec python /app/haproxy.py 
