#!/bin/bash
set -euo pipefail
echo "📄 Criando Data View 'logs' (@timestamp)..."
curl -s -X POST "http://localhost:5601/api/saved_objects/index-pattern" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{"attributes":{"title":"logs","timeFieldName":"@timestamp"}}' >/dev/null || true
echo "🔄 Atualizando lista de campos..."
ID=$(curl -s "http://localhost:5601/api/saved_objects/_find?type=index-pattern&search=logs&search_fields=title" -H "kbn-xsrf: true" | sed -n 's/.*"id":"\([^"]*\)".*"title":"logs".*/\1/p')
if [ -n "$ID" ]; then
  curl -s -X POST "http://localhost:5601/api/index_patterns/index_pattern/$ID/fields/refresh" -H "kbn-xsrf: true" >/dev/null || true
  echo "✅ Data View atualizado (id=$ID)."
else
  echo "⚠️  Não consegui identificar o ID do Data View 'logs'. Verifique manualmente no Kibana."
fi
