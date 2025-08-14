#!/bin/bash
set -euo pipefail

KBN="${KBN:-http://localhost:5601}"
ES="${ES:-http://localhost:9200}"
CURL="curl -sS --fail --connect-timeout 3 --max-time 10 -H kbn-xsrf:true"

PASS=0; FAIL=0
green(){ printf "\033[32m%s\033[0m\n" "$1"; }
red(){   printf "\033[31m%s\033[0m\n" "$1"; }
gray(){  printf "\033[90m%s\033[0m\n" "$1"; }
die(){ red "✗ $1"; exit 1; }

echo "🔎 Validando ambiente e respostas..."

# Sanidade
$CURL "$ES/_cluster/health?pretty"  >/dev/null || die "Elasticsearch indisponível em $ES"
$CURL "$KBN/api/status"             >/dev/null || die "Kibana indisponível em $KBN"

# 1) Índice logs
if $CURL "$ES/logs" | grep -q '"number_of_shards"'; then
  green "✓ Índice 'logs' existe"; PASS=$((PASS+1))
else
  red "✗ Índice 'logs' não encontrado"; FAIL=$((FAIL+1))
fi

# 2) Data View
if $CURL "$KBN/api/saved_objects/_find?type=index-pattern&per_page=1000" \
   | grep -F '"title":"logs"' | grep -Fq '"timeFieldName":"@timestamp"'; then
  green "✓ Data View 'logs' com time field @timestamp"; PASS=$((PASS+1))
else
  red "✗ Data View 'logs' ausente ou sem time field"; FAIL=$((FAIL+1))
fi

# 3) Visuais (aceitar Lens OU Visualization)
check_vis () {
  local title="$1"
  # procura em lens
  if $CURL "$KBN/api/saved_objects/_find?type=lens&per_page=1000" \
     | grep -F "\"title\":\"$title\"" >/dev/null; then
    green "✓ lens: '$title' encontrado"; PASS=$((PASS+1)); return
  fi
  # procura em visualization (aggs clássicas)
  if $CURL "$KBN/api/saved_objects/_find?type=visualization&per_page=1000" \
     | grep -F "\"title\":\"$title\"" >/dev/null; then
    green "✓ visualization: '$title' encontrado"; PASS=$((PASS+1)); return
  fi
  red "✗ visual: '$title' não encontrado (lens/visualization)"; FAIL=$((FAIL+1))
}

check_vis "Treino - CPU por Serviço"
check_vis "Treino - Top 5 Hosts por Memória"
check_vis "Treino - Erros HTTP por Serviço"

# 4) Dashboard
if $CURL "$KBN/api/saved_objects/_find?type=dashboard&per_page=1000" \
   | grep -F "\"title\":\"Treino - Dashboard Consolidado\"" >/dev/null; then
  green "✓ dashboard: 'Treino - Dashboard Consolidado' encontrado"; PASS=$((PASS+1))
else
  red "✗ dashboard: 'Treino - Dashboard Consolidado' não encontrado"; FAIL=$((FAIL+1))
fi

# 5) Job de ML
if $CURL "$ES/_ml/anomaly_detectors" | grep -q '"job_id":"treino_anomalia_memoria"'; then
  green "✓ Job ML 'treino_anomalia_memoria' existe"; PASS=$((PASS+1))
else
  red "✗ Job ML 'treino_anomalia_memoria' não encontrado"; FAIL=$((FAIL+1))
fi

echo
gray "Resultados: $PASS OK / $FAIL Falhas"
[ "$FAIL" -eq 0 ] && green "✅ Tudo certo!" || red "⚠️ Há itens pendentes acima."
