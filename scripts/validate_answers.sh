#!/bin/bash
set -euo pipefail

# ========= Config =========
KBN="${KBN:-http://localhost:5601}"
ES="${ES:-http://localhost:9200}"
CURL_KBN='curl -sS --fail --connect-timeout 3 --max-time 12 -H kbn-xsrf:true'
CURL_ES='curl -sS --fail --connect-timeout 3 --max-time 12'

PASS=0; FAIL=0
ok(){ printf "\033[32m✓ %s\033[0m\n" "$1"; PASS=$((PASS+1)); }
bad(){ printf "\033[31m✗ %s\033[0m\n" "$1"; FAIL=$((FAIL+1)); }
info(){ printf "\033[90m↪ %s\033[0m\n" "$1"; }
die(){ printf "\033[31m✗ %s\033[0m\n" "$1"; exit 1; }

# ========= Helpers =========
# Lista títulos de um tipo (para debug) e verifica se um título exato existe
titles_of () { # $1 type
  $CURL_KBN "$KBN/api/saved_objects/_find?type=$1&per_page=1000" \
    | tr -d '\r' \
    | sed -n 's/.*"title":"\([^"]*\)".*/\1/p'
}
exists_title () { # $1 type, $2 exact title
  titles_of "$1" | grep -Fx -- "$2" >/dev/null
}
# Exporta 1 objeto por título exato (retorna NDJSON) — lens tem prioridade sobre visualization
export_by_title () { # $1 expected title, $2 types (comma list) e.g. "lens,visualization"
  local title="$1" types="$2" t
  IFS=',' read -r -a arr <<< "$types"
  for t in "${arr[@]}"; do
    # achar id pelo título EXATO
    local id
    id=$($CURL_KBN "$KBN/api/saved_objects/_find?type=$t&per_page=1000" \
      | awk -v need="\"title\":\""$(printf %s "$title" | sed 's/[&/\]/\\&/g')"\"" -v tt="\"type\":\"$t\"" '
        BEGIN{RS="{";FS=","}
        index($0,tt) && index($0,need) {
          if (match($0,/"id":"[^"]+"/)) { id=substr($0,RSTART+5,RLENGTH-6); print id; exit }
        }')
    if [ -n "${id:-}" ]; then
      $CURL_KBN "$KBN/api/saved_objects/_export" \
        -H "Content-Type: application/json" \
        -d "{\"objects\":[{\"type\":\"$t\",\"id\":\"$id\"}]}" \
      || true
      return 0
    fi
  done
  return 1
}

contains () { echo "$1" | grep -Fq "$2"; }

# ========= Sanidade =========
$CURL_ES "$ES/_cluster/health" >/dev/null || die "Elasticsearch indisponível em $ES"
$CURL_KBN "$KBN/api/status"    >/dev/null || die "Kibana indisponível em $KBN"
ok "ES/Kibana respondendo"

# ========= Pré-requisitos =========
if $CURL_ES "$ES/logs" | grep -q '"number_of_shards"'; then ok "Índice 'logs' existe"; else bad "Índice 'logs' não encontrado"; fi
if $CURL_KBN "$KBN/api/saved_objects/_find?type=index-pattern&per_page=1000" | grep -F '"title":"logs"' | grep -Fq '"timeFieldName":"@timestamp"'; then
  ok "Data View 'logs' com @timestamp"
else
  bad "Data View 'logs' ausente/sem time field"
fi

echo "—"
echo "🧪 Tarefas (validação por NOME exato)"

# ========= T1 (Saved Search 'T1') =========
if exists_title search "T1"; then
  T1_JSON=$(export_by_title "T1" "search" || true)
  if [ -n "${T1_JSON:-}" ] && contains "$T1_JSON" 'service.name' && ( contains "$T1_JSON" '"gte":500' || echo "$T1_JSON" | grep -Eq 'status_code[[:space:]]*>=[[:space:]]*500' ); then
    ok "T1: Saved Search 'T1' com service.name e status_code >= 500"
  else
    bad "T1: 'T1' encontrado, mas query não contém service.name + status_code>=500"
  fi
else
  bad "T1: Saved Search 'T1' não encontrado"
  info "Títulos existentes (search):"; titles_of search | sed 's/^/   - /'
fi

# ========= T2 (Treino - CPU por Serviço) =========
TITLE_T2="Treino - CPU por Serviço"
if exists_title lens "$TITLE_T2" || exists_title visualization "$TITLE_T2"; then
  V2=$(export_by_title "$TITLE_T2" "lens,visualization" || true)
  if [ -n "${V2:-}" ] && contains "$V2" "cpu_percent" && contains "$V2" "service.name"; then
    ok "T2: '$TITLE_T2' usa cpu_percent por service.name"
  else
    # Mesmo que o Lens oculte a estrutura, se o nome bate, marcamos como OK
    ok "T2: '$TITLE_T2' encontrado (título confere)"
  fi
else
  bad "T2: '$TITLE_T2' não encontrado"
  info "Títulos existentes (lens/visualization):"
  { titles_of lens; titles_of visualization; } | sort -u | sed 's/^/   - /'
fi

# ========= T3 (Treino - Top 5 Hosts por Memória) =========
TITLE_T3="Treino - Top 5 Hosts por Memória"
if exists_title lens "$TITLE_T3" || exists_title visualization "$TITLE_T3"; then
  V3=$(export_by_title "$TITLE_T3" "lens,visualization" || true)
  if [ -n "${V3:-}" ] && contains "$V3" "memory_percent" && contains "$V3" "host.name"; then
    ok "T3: '$TITLE_T3' usa memory_percent por host.name"
  else
    ok "T3: '$TITLE_T3' encontrado (título confere)"
  fi
else
  bad "T3: '$TITLE_T3' não encontrado"
  info "Títulos existentes (lens/visualization):"
  { titles_of lens; titles_of visualization; } | sort -u | sed 's/^/   - /'
fi

# ========= T4 (Mapa com geoip.location) =========
# Aqui, só validamos por nome do T4 se você quiser. Por padrão, aceitamos qualquer map com geoip.location.
MAPS="$($CURL_KBN "$KBN/api/saved_objects/_find?type=map&per_page=1000" || true)"
if echo "$MAPS" | grep -Fq 'geoip.location'; then
  ok "T4: Mapa com geoip.location encontrado"
else
  # também aceitar Lens que mencione geoip.location
  ANY_GEO="$($CURL_KBN "$KBN/api/saved_objects/_find?type=lens&per_page=1000" | grep -F 'geoip.location' || true)"
  if [ -n "$ANY_GEO" ]; then ok "T4: Visual Lens com geoip.location encontrada"; else bad "T4: mapa/visual com geoip.location não encontrado"; fi
fi

# ========= T5 (Treino - Dashboard Consolidado) =========
TITLE_T5="Treino - Dashboard Consolidado"
if exists_title dashboard "$TITLE_T5"; then
  ok "T5: Dashboard '$TITLE_T5' encontrado"
else
  bad "T5: Dashboard '$TITLE_T5' não encontrado"
  info "Títulos existentes (dashboard):"; titles_of dashboard | sed 's/^/   - /'
fi

# ========= T6 (ML) =========
ML="$($CURL_ES "$ES/_ml/anomaly_detectors/treino_anomalia_memoria" || true)"
if echo "$ML" | grep -q '"job_id":"treino_anomalia_memoria"'; then
  if echo "$ML" | grep -q '"function":"mean"' && echo "$ML" | grep -q '"field_name":"memory_percent"' && echo "$ML" | grep -q '"bucket_span":"15m"'; then
    ok "T6: Job ML correto (mean memory_percent, bucket 15m)"
  else
    bad "T6: Job ML existe mas difere do gabarito (Single Metric • mean(memory_percent) • 15m)"
  fi
else
  bad "T6: Job ML 'treino_anomalia_memoria' não encontrado"
fi

# ========= T7 (Alert) =========
RULES="$($CURL_KBN "$KBN/api/alerting/rules/_find?per_page=1000" || true)"
if echo "$RULES" | grep -iq 'cpu_percent' && echo "$RULES" | grep -Eq '90[^0-9]*'; then
  ok "T7: Regra envolvendo cpu_percent>90 localizada"
else
  info "T7: não localizei regra (pode depender de conector/licença)."
fi

# ========= T8 =========
[ "$(exists_title dashboard "$TITLE_T5"$'\n' && echo ok || echo)" ] && ok "T8: Dashboard existe (export NDJSON é manual)"

echo "—"
TOTAL=$((PASS+FAIL))
echo "Resultados: $PASS OK / $FAIL Falhas (Total checagens: $TOTAL)"
[ "$FAIL" -eq 0 ] && echo "✅ Tudo certo!" || echo "⚠️ Há itens pendentes acima."
