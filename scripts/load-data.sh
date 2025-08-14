#!/bin/bash
set -e
echo "📥 Iniciando carga de dados..."
curl -H "Content-Type: application/x-ndjson" -XPOST "localhost:9200/logs/_bulk?pretty" --data-binary "@data/sample-logs.json"
echo "✅ Dados carregados com sucesso!"
