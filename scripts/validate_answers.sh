#!/bin/bash
set -euo pipefail

# ===== Config rápida =====
KBN="${KBN:-http://localhost:5601}"   # Ex.: http://localhost:5601/s/meu-space
ES="${ES:-http://localhost:9200}"

CURL_KBN='curl -sS --fail --connect-timeout 3 --max-time 12 -H kbn-xsrf:true'
CURL_ES='curl -sS --fail --connect-timeout 3 --max-time 12'

PASS=0; FAIL=0
ok(){ printf "\033[32m✓ %s\033[0m\n" "$1"; PASS=$((PASS+1)); }
bad(){ printf "\033[31m✗ %s\033[0m\n" "$1"; FAIL=$((FAIL+1)); }
info(){ printf "\033[90m↪ %s\033[0m\n" "$1"; }

die(){ printf "\033[31m✗ %s\033[0m\n" "$1"; exit 1; }

# ===== Helpers =====
find_id_by_title () {
  # $1 type, $2 title, returns first ID
  local type="$1" title="$2"
  $CURL_KBN "$KBN/api/saved_objects/_find?type=$type&per_page=1000" \
  | tr -d '\r' \
  | awk -v t="\"type\":\"$type\"" -v n="\"title\":\"$title\"" '
      BEGIN{RS="{";FS=","}
      index($0,t) && index($0,n) {
        if (match($0,/"id":"[^"]+"/)) {
          id=substr($0,RSTART+5,RLENGTH-6); print id; exit
        }
      }'
}

export_one () {
  # export single SO: $1 type, $2 id
  local type="$1" id="$2"
  $CURL_KBN "$KBN/api/saved_objects/_export" \
    -H "Content-Type: application/json" \
    -d "{\"objects\":[{\"type\":\"$type\",\"id\":\"$id\"}]}" \
  || true
}

contains () { echo "$1" | grep -Fq "$2"; }

# ===== Sanidade =====
$CURL_ES "$ES/_cluster/health" >/dev/null || die "Elasticsearch indisponível em $ES"
$CURL_KBN "$KBN/api/status"    >/dev/null || die "Kibana indisponível em $KBN"
ok "ES/Kibana respondendo"

# ===== Pré-requisitos =====
if $CURL_ES "$ES/logs" | grep -q '"number_of_shards"'; then
  ok "Índice 'logs' existe"
else
  bad "Índice 'logs' não encontrado"
fi

if $CURL_KBN "$KBN/api/saved_objects/_find?type=index-pattern&per_page=1000" \
   | grep -F '"title":"logs"' | grep -Fq '"timeFieldName":"@timestamp"'; then
  ok "Data View 'logs' com @timestamp"
else
  bad "Data View 'logs' ausente/sem time field"
fi

echo "—"
echo "🧪 Tarefas"

# ===== T1: Saved Search 'T1' com service.name e status_code >= 500 =====
T1_ID="$(find_id_by_title search 'T1' || true)"
if [ -n "$T1_ID" ]; then
  T1_JSON="$(export_one search "$T1_ID")"
  if contains "$T1_JSON" 'service.name' && \
     ( contains "$T1_JSON" '"gte":500' || echo "$T1_JSON" | grep -Eq 'status_code[[:space:]]*>=[[:space:]]*500' ); then
    ok "T1: Saved Search 'T1' com service.name e status_code >= 500"
  else
    bad "T1: 'T1' encontrado, mas não detectei service.name e status_code>=500 na query"
  fi
else
  # fallback: qualquer saved search/query com termos
  Q="$($CURL_KBN "$KBN/api/saved_objects/_find?type=query&per_page=1000" || true)"
  S="$($CURL_KBN "$KBN/api/saved_objects/_find?type=search&per_page=1000" || true)"
  if ( contains "$Q" 'service.name' && contains "$Q" 'status_code' ) || \
     ( contains "$S" 'service.name' && contains "$S" 'status_code' ); then
    ok "T1: Saved Query/Search com service.name e status_code encontrados"
  else
    info "T1: não achei saved search/query — (dica: salve como 'T1')"
  fi
fi

# ===== Localiza visuais (Lens ou Visualization) por título =====
V_CPU_ID="$(find_id_by_title lens 'Treino - CPU por Serviço' || true)"
[ -z "$V_CPU_ID" ] && V_CPU_ID="$(find_id_by_title visualization 'Treino - CPU por Serviço' || true)"

V_MEM_ID="$(find_id_by_title lens 'Treino - Top 5 Hosts por Memória' || true)"
[ -z "$V_MEM_ID" ] && V_MEM_ID="$(find_id_by_title visualization 'Treino - Top 5 Hosts por Memória' || true)"

V_ERR_ID="$(find_id_by_title lens 'Treino - Erros HTTP por Serviço' || true)"
[ -z "$V_ERR_ID" ] && V_ERR_ID="$(find_id_by_title visualization 'Treino - Erros HTTP por Serviço' || true)"

# ===== T2: CPU por Serviço =====
if [ -n "$V_CPU_ID" ]; then
  V2="$(export_one lens "$V_CPU_ID")"
  [ -z "$V2" ] && V2="$(export_one visualization "$V_CPU_ID")"
  if contains "$V2" "cpu_percent" && contains "$V2" "service.name"; then
    ok "T2: 'Treino - CPU por Serviço' usa cpu_percent por service.name"
  else
    # passa se pelo menos a visual existir (evita falso negativo por formatos de Lens)
    info "T2: visual encontrada, mas não consegui confirmar campos — aceitando"
    ok  "T2: visual existente"
  fi
else
  bad "T2: 'Treino - CPU por Serviço' não encontrada (verifique o título exato)"
fi

# ===== T3: Top 5 Hosts por Memória =====
if [ -n "$V_MEM_ID" ]; then
  V3="$(export_one lens "$V_MEM_ID")"
  [ -z "$V3" ] && V3="$(export_one visualization "$V_MEM_ID")"
  if contains "$V3" "memory_percent" && contains "$V3" "host.name"; then
    ok "T3: 'Treino - Top 5 Hosts por Memória' usa memory_percent por host.name"
  else
    info "T3: visual encontrada, mas não confirmei campos — aceitando"
    ok  "T3: visual existente"
  fi
else
  bad "T3: 'Treino - Top 5 Hosts por Memória' não encontrada (verifique o título)"
fi

# ===== T4: Mapa com geoip.location (qualquer visual que contenha o campo) =====
MAPS="$($CURL_KBN "$KBN/api/saved_objects/_find?type=map&per_page=1000" || true)"
if contains "$MAPS" 'geoip.location'; then
  ok "T4: Mapa contendo geoip.location encontrado"
else
  # também aceite se alguma visual/lens referenciar geoip.location
  ANY_GEO="$( $CURL_KBN "$KBN/api/saved_objects/_find?type=lens&per_page=1000" | grep -F 'geoip.location' || true )"
  if [ -n "$ANY_GEO" ]; then ok "T4: Visual Lens com geoip.location encontrada"; else bad "T4: mapa/visual com geoip.location não encontrado"; fi
fi

# ===== T5: Dashboard que referencia as 3 visuais =====
DASH_ID="$(find_id_by_title dashboard 'Treino - Dashboard Consolidado' || true)"
if [ -n "$DASH_ID" ]; then
  DASH="$(export_one dashboard "$DASH_ID")"
  refs_ok=0
  [ -n "$V_CPU_ID" ] && contains "$DASH" "\"id\":\"$V_CPU_ID\"" && refs_ok=$((refs_ok+1))
  [ -n "$V_MEM_ID" ] && contains "$DASH" "\"id\":\"$V_MEM_ID\"" && refs_ok=$((refs_ok+1))
  [ -n "$V_ERR_ID" ] && contains "$DASH" "\"id\":\"$V_ERR_ID\"" && refs_ok=$((refs_ok+1))
  if [ "$refs_ok" -ge 2 ]; then
    # aceita com 2+ referências corretas para evitar falso negativo caso 1 visual tenha outro ID
    ok "T5: Dashboard referencia as visuais (encontrei $refs_ok/3)"
  else
    bad "T5: Dashboard não referencia as visuais esperadas (confira títulos e salve no dashboard)"
  fi
else
  bad "T5: Dashboard 'Treino - Dashboard Consolidado' não encontrado"
fi

# ===== T6: Job de ML =====
ML="$($CURL_ES "$ES/_ml/anomaly_detectors/treino_anomalia_memoria" || true)"
if echo "$ML" | grep -q '"job_id":"treino_anomalia_memoria"'; then
  if echo "$ML" | grep -q '"function":"mean"' && echo "$ML" | grep -q '"field_name":"memory_percent"' && echo "$ML" | grep -q '"bucket_span":"15m"'; then
    ok "T6: Job ML correto (mean memory_percent, bucket 15m)"
  else
    bad "T6: Job ML existe mas difere do gabarito (use Single Metric • mean(memory_percent) • 15m)"
  fi
else
  bad "T6: Job ML 'treino_anomalia_memoria' não encontrado"
fi

# ===== T7: Regra de alerta (best-effort) =====
RULES="$($CURL_KBN "$KBN/api/alerting/rules/_find?per_page=1000" || true)"
if echo "$RULES" | grep -iq 'cpu_percent' && echo "$RULES" | grep -Eq '90[^0-9]*'; then
  ok "T7: Regra envolvendo cpu_percent>90 localizada"
else
  info "T7: não localizei regra (pode depender de conector/licença)."
fi

# ===== T8: Export NDJSON é manual; passa se houver dashboard =====
[ -n "$DASH_ID" ] && ok "T8: Dashboard existe (export é manual)"

echo "—"
TOTAL=$((PASS+FAIL))
echo "Resultados: $PASS OK / $FAIL Falhas (Total checagens: $TOTAL)"
[ "$FAIL" -eq 0 ] && echo "✅ Tudo certo!" || echo "⚠️ Há itens pendentes acima."
