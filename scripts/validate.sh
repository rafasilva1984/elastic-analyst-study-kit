#!/bin/bash
set -euo pipefail

PASS=0
FAIL=0

green(){ printf "\033[32m%s\033[0m\n" "$1"; }
red(){ printf "\033[31m%s\033[0m\n" "$1"; }
gray(){ printf "\033[90m%s\033[0m\n" "$1"; }

echo "🔎 Validando ambiente e respostas..."

if curl -s "http://localhost:9200/logs" | grep -q '"number_of_shards"'; then
  green "✓ Índice 'logs' existe"
  PASS=$((PASS+1))
else
  red "✗ Índice 'logs' não encontrado"
  FAIL=$((FAIL+1))
fi

if curl -s "http://localhost:5601/api/saved_objects/_find?type=index-pattern&search=logs&search_fields=title" -H "kbn-xsrf: true" | grep -q '"timeFieldName":"@timestamp"'; then
  green "✓ Data View 'logs' com time field @timestamp"
  PASS=$((PASS+1))
else
  red "✗ Data View 'logs' ausente ou sem time field"
  FAIL=$((FAIL+1))
fi

check_saved_obj(){
  local type="$1"
  local title="$2"
  if curl -s "http://localhost:5601/api/saved_objects/_find?type=$type&search_fields=title&search=$title" -H "kbn-xsrf: true" | grep -q "\"title\":\"$title\""; then
    green "✓ $type: '$title' encontrado"
    PASS=$((PASS+1))
  else
    red "✗ $type: '$title' não encontrado"
    FAIL=$((FAIL+1))
  fi
}

check_saved_obj "visualization" "Treino - CPU por Serviço"
check_saved_obj "visualization" "Treino - Top 5 Hosts por Memória"
check_saved_obj "visualization" "Treino - Erros HTTP por Serviço"
check_saved_obj "dashboard" "Treino - Dashboard Consolidado"

if curl -s "http://localhost:9200/_ml/anomaly_detectors" | grep -q '"job_id":"treino_anomalia_memoria"'; then
  green "✓ Job ML 'treino_anomalia_memoria' existe"
  PASS=$((PASS+1))
else
  red "✗ Job ML 'treino_anomalia_memoria' não encontrado"
  FAIL=$((FAIL+1))
fi

echo
gray "Resultados: $PASS OK / $FAIL Falhas"
if [ "$FAIL" -eq 0 ]; then green "✅ Tudo certo!"; else red "⚠️ Há itens pendentes acima."; fi
