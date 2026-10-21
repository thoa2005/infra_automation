#!/usr/bin/env bash
set -u

url='http://127.0.0.1/'
status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 5 "$url") || status='000'

if [[ "$status" == '200' ]]; then
    logger -t infra-health "nginx OK: HTTP $status"
    exit 0
fi

logger -p user.err -t infra-health "nginx loi: HTTP $status tai $url"
exit 1
