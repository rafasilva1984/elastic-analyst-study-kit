#!/bin/bash
set -euo pipefail

INDEX_NAME="logs"
DATA_FILE="data/sample-logs.json"

echo "📥 Iniciando carga de dados..."

# Garante newline ao final do arquivo (Bulk API exige \n no último registro)
if [ -n "$(tail -c1 "$DATA_FILE" | wc -c)" ]; then
  printf "\n" >> "$DATA_FILE"
fi

# Cria índice com mapeamento adequado (geo_point, datas e numéricos)
echo "🧱 Criando índice \"$INDEX_NAME\" com mapeamento..."
curl -s -o /dev/null -w "%{http_code}" -XDELETE "http://localhost:9200/$INDEX_NAME" >/dev/null 2>&1 || true

CREATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -XPUT "http://localhost:9200/$INDEX_NAME" -H "Content-Type: application/json" -d '{
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "service.name": { "type": "keyword" },
      "host.name": { "type": "keyword" },
      "status_code": { "type": "integer" },
      "cpu_percent": { "type": "float" },
      "memory_percent": { "type": "float" },
      "geoip.location": { "type": "geo_point" },
      "message": { "type": "text" }
    }
  }
}')

if [ "$CREATE_CODE" != "200" ] && [ "$CREATE_CODE" != "201" ]; then
  echo "❌ Falha ao criar índice ($CREATE_CODE)"; exit 1
fi

# Envia bulk
echo "🚚 Enviando bulk para /$INDEX_NAME/_bulk ..."
HTTP_CODE=$(curl -s -o /tmp/bulk_response.json -w "%{http_code}" -H "Content-Type: application/x-ndjson" -XPOST "http://localhost:9200/$INDEX_NAME/_bulk?pretty" --data-binary "@$DATA_FILE")

# Verificação de sucesso HTTP
if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ Erro HTTP no bulk: código $HTTP_CODE"
  cat /tmp/bulk_response.json
  exit 1
fi

# Fallback sem jq: checa se aparece a string \"\"errors\": true\"
if grep -q '\"errors\": true' /tmp/bulk_response.json; then
  echo "⚠ Bulk retornou errors=true. Trecho da resposta:"
  head -n 60 /tmp/bulk_response.json
  echo "❌ Houve erros durante a indexação."
  exit 1
fi

echo "✅ Dados carregados com sucesso!"
