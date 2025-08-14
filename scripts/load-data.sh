#!/bin/bash
set -euo pipefail

INDEX="logs"
DATA="data/sample-logs.json"

echo "📥 Iniciando carga no índice '$INDEX'..."
if [ -n "$(tail -c1 "$DATA" | wc -c)" ]; then printf "\n" >> "$DATA"; fi

curl -s -o /dev/null -XDELETE "http://localhost:9200/$INDEX" || true
CREATE=$(curl -s -o /dev/null -w "%{http_code}" -XPUT "http://localhost:9200/$INDEX" -H "Content-Type: application/json" -d '{
  "mappings": {
    "properties": {
      "@timestamp": {"type":"date"},
      "service.name": {"type":"keyword"},
      "host.name": {"type":"keyword"},
      "status_code": {"type":"integer"},
      "cpu_percent": {"type":"float"},
      "memory_percent": {"type":"float"},
      "geoip.location": {"type":"geo_point"},
      "message": {"type":"text"}
    }
  }
}')
if [ "$CREATE" != "200" ] && [ "$CREATE" != "201" ]; then echo "❌ Falha ao criar índice ($CREATE)"; exit 1; fi

HTTP=$(curl -s -o /tmp/bulk.json -w "%{http_code}" -H "Content-Type: application/x-ndjson" \
  -XPOST "http://localhost:9200/$INDEX/_bulk?pretty" --data-binary "@$DATA")
if [ "$HTTP" != "200" ]; then echo "❌ Bulk HTTP $HTTP"; head -n 60 /tmp/bulk.json; exit 1; fi

COUNT=$(curl -s "http://localhost:9200/$INDEX/_count" | tr -d '\r' | sed -n 's/.*"count":\([0-9]*\).*/\1/p')
echo "✅ Documentos no índice '$INDEX': ${COUNT:-desconhecido}"
