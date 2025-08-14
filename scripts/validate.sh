#!/bin/bash
set -euo pipefail

KBN="http://localhost:5601"   # ajuste se usar outro host/space (ex: http://localhost:5601/s/meu-space)
ES="http://localhost:9200"

PASS=0; FAIL=0
green(){ printf "\033[32m%s\033[0m\n" "$1"; }
red(){   printf "\033[31m%s\033[0m\n" "$1"; }
gray(){  printf "\033[90m%s\033[0m\n" "$1"; }

echo "🔎 Validando ambiente e respostas..."

# 1) Índice logs existe
if curl -s "$ES/logs" | grep -q '"number_of_shards"'; then
  green "✓ Índice 'logs' existe"
  PASS=$((PASS+1))
else
  red "✗ Índice 'logs' não encontrado"
  FAIL=$((FAIL+1))
fi

# 2) Data View 'logs' com time field
if curl -s "$KBN/api/saved_objects/_find?type=index-pattern&per_page=1000" -H "kbn-xsrf: true" \
  | grep -F '"title":"logs"' | grep -Fq '"timeFieldName":"@timestamp"'; then
  green "✓ Data View 'logs' com time field @timestamp"
  PASS=$((PASS+1))
else
  red "✗ Data View 'logs' ausente ou sem time field"
  FAIL=$((FAIL+1))
fi

# Função para checar Saved Objects por título (UTF-8 literal, sem URL-encode)
check_so () {
  local type="$1"
  local title="$2"
  if curl -s "$KBN/api/saved_objects/_find?type=$type&per_page=1000" -H "kbn-xsrf: true" \
    | grep -F "\"title\":\"$title\"" >/dev/null; then
    green "✓ $type: '$title' encontrado"
    PASS=$((PASS+1))
  else
    red "✗ $type: '$title' não encontrado"
    FAIL=$((FAIL+1))
  fi
}

check_so "visualization" "Treino - CPU por Serviço"
check_so "visualization" "Treino - Top 5 Hosts por Memória"
check_so "visualization" "Treino - Erros HTTP por Serviço"
check_so "dashboard"     "Treino - Dashboard Consolidado"

# 4) Job de ML
if curl -s "$ES/_ml/anomaly_detectors" | grep -q '"job_id":"treino_anomalia_memoria"'; then
  green "✓ Job ML 'treino_anomalia_memoria' existe"
  PASS=$((PASS+1))
else
  red "✗ Job ML 'treino_anomalia_memoria' não encontrado"
  FAIL=$((FAIL+1))
fi

echo
gray "Resultados: $PASS OK / $FAIL Falhas"
[ "$FAIL" -eq 0 ] && green "✅ Tudo certo!" || red "⚠️ Há itens pendentes acima."
