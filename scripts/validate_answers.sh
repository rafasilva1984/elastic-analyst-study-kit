#!/bin/bash
set -euo pipefail

# =========================
# Config
# =========================
KBN="${KBN:-http://localhost:5601}"        # Ex.: http://localhost:5601/s/default
ES="${ES:-http://localhost:9200}"

PASS=0; FAIL=0
ok () { printf "\033[32m✓ %s\033[0m\n" "$1"; PASS=$((PASS+1)); }
bad() { printf "\033[31m✗ %s\033[0m\n" "$1"; FAIL=$((FAIL+1)); }
dim() { printf "\033[90m↪ %s\033[0m\n" "$1"; }

CURL_KBN=(curl -sS --fail --connect-timeout 3 --max-time 12 -H kbn-xsrf:true)
CURL_ES=(curl -sS --fail --connect-timeout 3 --max-time 12)

# =========================
# Helpers
# =========================

# Normaliza texto (remove acentos pt-BR mais comuns e baixa para minúsculas)
normalize() {
  sed 'y/ÁÀÂÃÄáàâãäÉÊËÈéêëèÍÏÌÎíïìîÓÔÕÖÒóôõöòÚÜÙÛúüùûÇç/AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc/' \
  | tr '[:upper:]' '[:lower:]'
}

# GET Kibana /_find (lista objetos de um tipo)
kbn_find() { # $1 type
  "${CURL_KBN[@]}" -G \
    --data-urlencode "type=$1" \
    --data-urlencode "per_page=1000" \
    "$KBN/api/saved_objects/_find"
}

# Retorna linhas "id|||title" de um tipo
ids_and_titles() { # $1 type
  kbn_find "$1" | tr -d '\r' \
  | sed -n 's/.*"type":"'"$1"'","id":"\([^"]*\)".*"title":"\([^"]*\)".*/\1|||\2/p'
}

# Lista somente títulos de um tipo (para depuração)
titles_of() { # $1 type
  ids_and_titles "$1" | sed 's/^.*|||//'
}

# Encontra ID por título (case/acento-insensível)
find_id_by_title_soft() { # $1 type, $2 expected title
  local type="$1" want="$2"
  local want_n; want_n="$(printf '%s' "$want" | normalize)"
  local line id title title_n
  while IFS= read -r line; do
    id="${line%%|||*}"
    title="${line#*|||}"
    title_n="$(printf '%s' "$title" | normalize)"
    if [ "$title_n" = "$want_n" ]; then
      printf '%s\n' "$id"; return 0
    fi
  done < <(ids_and_titles "$type")
  return 1
}

# Exporta 1 saved object (NDJSON de 1 linha)
export_one() { # $1 type, $2 id
  "${CURL_KBN[@]}" "$KBN/api/saved_objects/_export" \
    -H "Content-Type: application/json" \
    -d "{\"objects\":[{\"type\":\"$1\",\"id\":\"$2\"}]}" || true
}

contains() { echo "$1" | grep -Fq "$2"; }

# =========================
# Sanidade
# =========================
if ! "${CURL_ES[@]}" "$ES/_cluster/health" >/dev/null; then bad "Elasticsearch indisponível em $ES"; exit 1; fi
if ! "${CURL_KBN[@]}" "$KBN/api/status"    >/dev/null; then bad "Kibana indisponível em $KBN"; exit 1; fi
ok "ES/Kibana respondendo"

# =========================
# Pré-requisitos
# =========================
if "${CURL_ES[@]}" "$ES/logs" | grep -q '"number_of_shards"'; then
  ok "Índice 'logs' existe"
else
  bad "Índice 'logs' não encontrado"
fi

# Data View 'logs' com @timestamp (usa saved object index-pattern)
if "${CURL_KBN[@]}" "$KBN/api/saved_objects/_find?type=index-pattern&per_page=1000" \
   | grep -F '"title":"logs"' | grep -Fq '"timeFieldName":"@timestamp"'; then
  ok "Data View 'logs' com @timestamp"
else
  bad "Data View 'logs' não encontrado ou sem @timestamp"
fi

echo "—"
echo "🧪 Tarefas (validação por NOME — case/acento INsensível)"

# =========================
# T1 — Saved Search "T1"
# =========================
T1_ID="$(find_id_by_title_soft search 'T1' || true)"
if [ -n "$T1_ID" ]; then
  T1_JSON="$(export_one search "$T1_ID")"
  # aceita KQL '>= 500' (escapes no NDJSON) OU DSL com "gte":500
  if [ -n "$T1_JSON" ] && contains "$T1_JSON" 'service.name' \
     && ( contains "$T1_JSON" '"gte":500' || echo "$T1_JSON" | grep -Eiq 'status_code[[:space:]]*\\?>=\\?[[:space:]]*500' ); then
    ok "T1: Saved Search 'T1' com service.name e status_code >= 500"
  else
    bad "T1: 'T1' encontrado, mas query não contém service.name + status_code >= 500"
  fi
else
  bad "T1: Saved Search 'T1' não encontrado"
  dim "Títulos (search):"; titles_of search | sed 's/^/   - /'
fi

# =========================
# T2 — Visual "Treino - CPU por Serviço"
# =========================
TITLE_T2="Treino - CPU por Serviço"
V_CPU_ID="${V_CPU_ID:-$(find_id_by_title_soft lens "$TITLE_T2" || true)}"
[ -z "$V_CPU_ID" ] && V_CPU_ID="$(find_id_by_title_soft visualization "$TITLE_T2" || true)"
if [ -n "$V_CPU_ID" ]; then
  ok "T2: '$TITLE_T2' encontrado"
else
  bad "T2: '$TITLE_T2' não encontrado"
  dim "Títulos (lens/visualization):"
  { titles_of lens; titles_of visualization; } | sort -u | sed 's/^/   - /'
fi

# =========================
# T3 — Visual "Treino - Top 5 Hosts por Memória"
# =========================
TITLE_T3="Treino - Top 5 Hosts por Memória"
V_MEM_ID="${V_MEM_ID:-$(find_id_by_title_soft lens "$TITLE_T3" || true)}"
[ -z "$V_MEM_ID" ] && V_MEM_ID="$(find_id_by_title_soft visualization "$TITLE_T3" || true)"
if [ -n "$V_MEM_ID" ]; then
  ok "T3: '$TITLE_T3' encontrado"
else
  bad "T3: '$TITLE_T3' não encontrado"
fi

# =========================
# T4 — Map com geoip.location (ou Lens contendo o campo)
# =========================
MAPS_JSON="$("${CURL_KBN[@]}" -G --data-urlencode "type=map" --data-urlencode "per_page=1000" "$KBN/api/saved_objects/_find" || true)"
if echo "$MAPS_JSON" | grep -Fq 'geoip.location'; then
  ok "T4: Mapa com geoip.location encontrado"
else
  LENS_JSON="$("${CURL_KBN[@]}" -G --data-urlencode "type=lens" --data-urlencode "per_page=1000" "$KBN/api/saved_objects/_find" || true)"
  if echo "$LENS_JSON" | grep -Fq 'geoip.location'; then
    ok "T4: Visual Lens com geoip.location encontrada"
  else
    bad "T4: mapa/visual com geoip.location não encontrado"
  fi
fi

# =========================
# T5 — Dashboard "Treino - Dashboard Consolidado"
# =========================
TITLE_T5="Treino - Dashboard Consolidado"
DASH_ID="${DASH_ID:-$(find_id_by_title_soft dashboard "$TITLE_T5" || true)}"
if [ -n "$DASH_ID" ]; then
  ok "T5: Dashboard '$TITLE_T5' encontrado"
else
  bad "T5: Dashboard '$TITLE_T5' não encontrado"
  dim "Títulos (dashboard):"; titles_of dashboard | sed 's/^/   - /'
fi

# =========================
# T6 — ML job treino_anomalia_memoria (mean memory_percent, bucket 15m)
# =========================
ML_JSON="$("${CURL_ES[@]}" "$ES/_ml/anomaly_detectors/treino_anomalia_memoria" || true)"
if echo "$ML_JSON" | grep -q '"job_id":"treino_anomalia_memoria"'; then
  if echo "$ML_JSON" | grep -q '"function":"mean"' \
     && echo "$ML_JSON" | grep -q '"field_name":"memory_percent"' \
     && echo "$ML_JSON" | grep -q '"bucket_span":"15m"'; then
    ok "T6: Job ML confere com gabarito (mean memory_percent, 15m)"
  else
    bad "T6: Job ML existe mas difere do gabarito (Single Metric • mean(memory_percent) • 15m)"
  fi
else
  bad "T6: Job ML 'treino_anomalia_memoria' não encontrado"
fi

# =========================
# T7 — Regra de alerta (best-effort)
# =========================
RULES_JSON="$("${CURL_KBN[@]}" "$KBN/api/alerting/rules/_find?per_page=1000" || true)"
if echo "$RULES_JSON" | grep -iq 'cpu_percent' && echo "$RULES_JSON" | grep -Eq '90[^0-9]*'; then
  ok "T7: Regra envolvendo cpu_percent > 90 localizada"
else
  dim "T7: não localizei regra (pode depender de conector/licença)"
fi

# =========================
# T8 — Dashboard existe (export NDJSON é manual)
# =========================
[ -n "${DASH_ID:-}" ] && ok "T8: Dashboard existe (export NDJSON é manual)"

echo "—"
echo "Resultados: $PASS OK / $FAIL Falhas"
[ "$FAIL" -eq 0 ] && echo "✅ Tudo certo!" || echo "⚠️ Há itens pendentes acima."
