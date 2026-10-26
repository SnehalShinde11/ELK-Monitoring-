# Project 5.2 — Centralized Logging with the ELK Stack

**Assignment:** Project 5.2 — Centralized Logging with the ELK Stack  
**Submitted by:** Snehal Shinde

## What this lab does

Runs Elasticsearch, Logstash, Kibana, and Filebeat with Docker Compose.

```text
logs/*.log -> Filebeat -> Logstash (Grok/date parsing)
           -> Elasticsearch: logs-app-default -> Kibana
```

## Files

- `docker-compose.yml` — runs the four services and persists Elasticsearch/Filebeat data.
- `filebeat.yml` — reads application log files and sends them to Logstash.
- `pipeline/logstash.conf` — parses the sample log format and writes valid events to Elasticsearch.
- `security/logstash_writer-role.json`, `scripts/setup-logstash-security.sh` — create the least-privilege Logstash writer account.
- `.env.example` — placeholder credentials and Kibana encryption keys.
- `logs/.gitkeep` — keeps the log directory in Git.

## Prerequisites

- Docker Engine and Docker Compose plugin
- Linux host/VM with 4 GB RAM or more recommended
- Internet access to pull Elastic Stack 8.19.0 images

Elasticsearch and Kibana bind to localhost only. Logstash port 5044 is available inside the Docker network and is not published on the host.

## 1. Clone and configure

```bash
git clone https://github.com/SnehalShinde11/ELK-Monitoring-.git
cd ELK-Monitoring-
cp .env.example .env
chmod 600 .env
```

Generate three unique passwords and three distinct encryption keys:

```bash
openssl rand -hex 24
openssl rand -hex 24
openssl rand -hex 24
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 32
```

Edit `.env` and replace every placeholder. Use the first three outputs for `ELASTIC_PASSWORD`, `KIBANA_PASSWORD`, and `LOGSTASH_PASSWORD`; use the last three for the three Kibana encryption-key variables. Keep these values safe and do not commit `.env`. If reusing an existing Elasticsearch volume, preserve the existing passwords and encryption keys.

Load the values in your current terminal (repeat in each new terminal):

```bash
set -a
source ./.env
set +a
```

## 2. Start Elasticsearch and initialize Kibana's service password

```bash
docker compose config --quiet
docker compose up -d elasticsearch

for attempt in $(seq 1 60); do
  if curl -fsS -u "elastic:${ELASTIC_PASSWORD}" \
    http://127.0.0.1:9200/_cluster/health >/dev/null; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "Elasticsearch did not become ready; check: docker compose logs elasticsearch" >&2
    exit 1
  fi
  sleep 5
done
```

Set the built-in `kibana_system` password to match `KIBANA_PASSWORD` before starting Kibana:

```bash
curl -fsS -u "elastic:${ELASTIC_PASSWORD}" \
  -X POST "http://127.0.0.1:9200/_security/user/kibana_system/_password" \
  -H 'Content-Type: application/json' \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}"
```

Run that password command on a new data volume, or when intentionally changing the service password. Do not reset it blindly on an existing lab.

## 3. Start the stack and configure Logstash access

```bash
docker compose up -d
bash scripts/setup-logstash-security.sh
docker compose ps
```

The script creates/updates `logstash_internal` and assigns the `logstash_writer` role. Logstash retries Elasticsearch output while it becomes available.

Validate the pipeline syntax:

```bash
docker compose exec -T logstash \
  /usr/share/logstash/bin/logstash \
  --path.settings /usr/share/logstash/config \
  --config.test_and_exit
```

Expected output includes `Configuration OK`.

## 4. Send a test log and verify ingestion

```bash
echo "$(date -u '+%Y-%m-%d %H:%M:%S') INFO  [payment-service] Payment processed order_id=9001" \
  >> logs/payment-service.log
sleep 10
```

Check that the data stream exists:

```bash
curl -fsS -u "elastic:${ELASTIC_PASSWORD}" \
  "http://127.0.0.1:9200/_data_stream/logs-app-default?pretty"
```

Search for the test event:

```bash
curl -fsS -u "elastic:${ELASTIC_PASSWORD}" \
  "http://127.0.0.1:9200/logs-app-default/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{"query":{"match_phrase":{"message":"Payment processed"}},"_source":["@timestamp","message","log.level","service.name","order_id","tags"]}'
```

A successfully parsed document should contain `@timestamp`, `log.level`, `service.name`, `message`, and integer `order_id`. Use a new log line for each test because Filebeat tracks which lines it has already read.

## 5. Explore logs in Kibana

1. Open `http://127.0.0.1:5601` on the Docker host. For a remote VM, use an SSH tunnel, for example: `ssh -L 5601:127.0.0.1:5601 USER@VM_ADDRESS`.
2. Sign in as `elastic` using `ELASTIC_PASSWORD`. The `kibana_system` account is for the Kibana service, not interactive login.
3. Create a data view with pattern `logs-app-*` and time field `@timestamp`.
4. Open **Discover**. In **Lens**, try a bar chart by `log.level` and a time chart by `@timestamp`.

## Troubleshooting

```bash
docker compose ps
docker compose logs --tail=100 elasticsearch kibana logstash filebeat
```

- **HTTP 401:** check that the password in `.env` matches the password already configured in the Elasticsearch volume.
- **Kibana cannot connect:** confirm the `kibana_system` password matches `KIBANA_PASSWORD`.
- **No documents:** confirm `logs/payment-service.log` exists, then inspect Filebeat and Logstash logs.
- **HTTP 403 from Logstash:** rerun `bash scripts/setup-logstash-security.sh` and check `security/logstash_writer-role.json`.
- **Missing `order_id` or `_grokparsefailure`:** check the sample line format and send a fresh event after any pipeline change.

## Assignment Details

**Assignment:** Project 5.2 — Centralized Logging with the ELK Stack  
**Submitted by:** Snehal Shinde
