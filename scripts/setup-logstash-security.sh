#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Copy .env.example to .env and set real values." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source ./.env
set +a

: "${ELASTIC_PASSWORD:?ELASTIC_PASSWORD must be set in .env}"
: "${LOGSTASH_PASSWORD:?LOGSTASH_PASSWORD must be set in .env}"

ES_URL="${ES_URL:-http://127.0.0.1:9200}"
ADMIN_AUTH="elastic:${ELASTIC_PASSWORD}"

echo "Waiting for Elasticsearch at ${ES_URL} ..."
for attempt in $(seq 1 30); do
  if curl -fsS -u "$ADMIN_AUTH" "${ES_URL}/_cluster/health" >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    echo "ERROR: Elasticsearch did not become available." >&2
    exit 1
  fi
  sleep 2
done

echo "Applying logstash_writer role ..."
curl -fsS -u "$ADMIN_AUTH" \
  -X PUT "${ES_URL}/_security/role/logstash_writer" \
  -H 'Content-Type: application/json' \
  --data-binary @security/logstash_writer-role.json >/dev/null

user_payload="$(mktemp)"
chmod 600 "$user_payload"
trap 'rm -f "$user_payload"' EXIT

python3 - "$user_payload" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({
        "password": os.environ["LOGSTASH_PASSWORD"],
        "roles": ["logstash_writer"],
        "enabled": True
    }, f)
PY

echo "Creating/updating logstash_internal user and assigning role ..."
curl -fsS -u "$ADMIN_AUTH" \
  -X PUT "${ES_URL}/_security/user/logstash_internal" \
  -H 'Content-Type: application/json' \
  --data-binary @"$user_payload" >/dev/null

echo "Verifying role assignment ..."
curl -fsS -u "$ADMIN_AUTH" \
  "${ES_URL}/_security/user/logstash_internal" \
  | python3 -c 'import json,sys; u=json.load(sys.stdin)["logstash_internal"]; print("User:", u["username"]); print("Roles:", ", ".join(u["roles"]))'

echo "Done. Password values were not printed."
