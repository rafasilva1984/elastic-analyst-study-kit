#!/bin/bash
set -euo pipefail

# Ajuste se usar outro Space ou portas:
KBN="${KBN:-http://localhost:5601}"
ES="${ES:-http://localhost:9200}"

CURL_KBN='curl -sS --fail --connect-timeout 3 --max-time 12 -H kbn-xsrf:true'
CURL_ES='curl -sS --fail --connect-timeout 3 --max-time 12'

TMP_DIR="$(mktemp -d)"
EXPORT_JSON="$TMP_DIR/saved_objects.ndjson"

PASS=0; FAIL=0
ok(){ printf "\033[32m✓ %s\033[0m\n" "$1"; PASS=$((PASS+1)); }
bad(){ printf "\033[31m✗ %s\033[0m\n" "$1"; FAIL=$((FAIL+1)); }
info(){ printf "\033[90m↪ %s\033[0m\n" "$1"; }

echo "🔎 Validando ambiente..."
$CURL_ES "$ES/_cluster/health" >/dev/null || { echo "ES indisponível em $ES"; exit 1; }
$CURL_KBN "$KBN/api/status"    >/dev/null || { echo "Kibana indisponível em $KBN"; exit 1; }
ok "ES/Kibana respondendo"

echo "📤 Exportando Saved Objects (sem tipos não-exportáveis)..."
# IMPORTANTE: não incluir 'alert'/'rule' (não exportáveis)
$CURL_KBN "$KBN/api/saved_objects/_export" \
  -H "Content-Type: application/json" \
  -d '{"type":["index-pattern","search","visualization","lens","map","dashboard","query","url","tag"],"excludeExportDetails":true,"includeReferencesDeep":true}' \
  > "$EXPORT_JSON"

# Helpers
find_block_by_title() { awk -v t="\"title\":\"$1\"" 'index($0,t){print $0}' "$EXPORT_JSON"; }
contains_field()      { echo "$1" | grep -Fq "$2"; }

echo "—"
echo "✅ Pré-requisitos"
if $CURL_ES "$ES/logs" | grep -q '"number_of_shards"'; then ok "Índice 'logs' existe"; else bad "Índice 'logs' não encontrado"; fi
if $CURL_KBN "$KBN/api/saved_objects/_find?type=index-pattern&per_page=1000" \
    | grep -F '"title":"logs"' | grep -Fq '"timeFieldName":"@timestamp"'; then
  ok "Data View 'logs' com @timestamp"
else
  bad "Data View 'logs' ausente/sem time field"
fi

echo "—"
echo "🧪 Tarefas"

# T1 – Saved Search (best-effort)
SEARCHS="$($CURL_KBN "$KBN/api/saved_objects/_find?type=search&per_page=1000" | sed 's/\\u002F/\//g')"
if echo "$SEARCHS" | grep -qi '"payment-service"\|"api-gateway"\|"auth-service"\|"order-service"' \
   && echo "$SEARCHS" | grep -q 'status_code'; then
  ok "T1: Saved search com filtro de service.name e status_code encontrado (best-effort)"
else
  info "T1: não encontrei saved search com filtros esperados (se não salvou a busca, ignore)"
fi

# T2 – Visual 'Treino - CPU por Serviço'
V2="$(find_block_by_title 'Treino - CPU por Serviço')"
if [ -n "$V2" ] && contains_field "$V2" "cpu_percent" && contains_field "$V2" "service.name"; then
  ok "T2: Visual 'Treino - CPU por Serviço' usa cpu_percent por service.name"
else
  bad "T2: Visual 'Treino - CPU por Serviço' ausente/sem cpu_percent/service.name"
fi

# T3 – Visual 'Treino - Top 5 Hosts por Memória'
V3="$(find_block_by_title 'Treino - Top 5 Hosts por Memória')"
if [ -n "$V3" ] && contains_field "$V3" "memory_percent" && contains_field "$V3" "host.name"; then
  ok "T3: Visual 'Top 5 Hosts por Memória' usa memory_percent por host.name"
else
  bad "T3: Visual 'Top 5 Hosts por Memória' ausente/sem memory_percent/host.name"
fi

# T4 – Mapa (geoip.location)
MAP_LINE="$(awk 'index($0,"geoip.location"){print $0}' "$EXPORT_JSON" | head -n1)"
if [ -n "$MAP_LINE" ]; then ok "T4: Visual com geoip.location encontrado (mapa)"; else bad "T4: Mapa com geoip.location não encontrado"; fi

# T5 – Dashboard referencia as 3 visuais
DASH="$(find_block_by_title 'Treino - Dashboard Consolidado')"
if [ -n "$DASH" ] && echo "$DASH" | grep -Fq 'Treino - CPU por Serviço' \
   && echo "$DASH" | grep -Fq 'Treino - Top 5 Hosts por Memória' \
   && echo "$DASH" | grep -Fq 'Treino - Erros HTTP por Serviço'; then
  ok "T5: Dashboard referencia as 3 visuais esperadas"
else
  bad "T5: Dashboard não referencia todas as visuais (confira títulos exatos)"
fi

# T6 – Job ML
ML="$($CURL_ES "$ES/_ml/anomaly_detectors/treino_anomalia_memoria" || true)"
if echo "$ML" | grep -q '"job_id":"treino_anomalia_memoria"'; then
  if echo "$ML" | grep -q '"function":"mean"' && echo "$ML" | grep -q '"field_name":"memory_percent"' && echo "$ML" | grep -q '"bucket_span":"15m"'; then
    ok "T6: Job ML correto (mean memory_percent, bucket 15m)"
  else
    bad "T6: Job ML existe mas com configuração diferente do gabarito"
  fi
else
  bad "T6: Job ML 'treino_anomalia_memoria' não encontrado"
fi

# T7 – Regra de alerta (sem export)
RULES="$($CURL_KBN "$KBN/api/alerting/rules/_find?per_page=1000" || true)"
if echo "$RULES" | grep -iq 'cpu_percent' && echo "$RULES" | grep -Eq '90[^0-9]*'; then
  ok "T7: Regra de alerta envolvendo cpu_percent>90 localizada (best-effort)"
else
  info "T7: não localizei regra de alerta (pode variar por conector/licença)."
fi

# T8 – Export NDJSON (manual)
if [ -n "$DASH" ]; then ok "T8: Dashboard existe (export NDJSON é manual, considerado OK)"; fi

echo "—"
TOTAL=$((PASS+FAIL)); echo "Resultados: $PASS OK / $FAIL Falhas (Total checagens: $TOTAL)"
[ "$FAIL" -eq 0 ] && echo "✅ Tudo certo!" || echo "⚠️ Há itens pendentes acima."

rm -rf "$TMP_DIR"
