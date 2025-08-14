#!/bin/bash

set -e

KBN="http://localhost:5601"
ES="http://localhost:9200"
CURL_KBN="curl -s -H kbn-xsrf:true"

ok()   { echo "✓ $1"; }
bad()  { echo "✗ $1"; }
info() { echo "↪ $1"; }

# -------- Funções utilitárias --------
urlencode() { python - <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.stdin.read().strip()))
PY
}

titles_of () { # $1 type
  $CURL_KBN "$KBN/api/saved_objects/_find?type=$1&per_page=1000" \
    | sed -n 's/.*"title":"\([^"]*\)".*/\1/p'
}

find_id_by_title () { # $1 type, $2 exact title
  local type="$1" title="$2"
  local q; q=$(printf '%s' "\"$title\"" | urlencode)
  $CURL_KBN "$KBN/api/saved_objects/_find?type=$type&per_page=1000&search_fields=title&search=$q" \
    | sed -n 's/.*"type":"'"$type"'","id":"\([^"]*\)".*/\1/p' | head -n1
}

export_by_title () { # $1 exact title, $2 types coma "lens,visualization"
  local title="$1" types="$2" t id
  IFS=',' read -r -a arr <<< "$types"
  for t in "${arr[@]}"; do
    id=$(find_id_by_title "$t" "$title")
    if [ -n "$id" ]; then
      $CURL_KBN "$KBN/api/saved_objects/_export" \
        -H "Content-Type: application/json" \
        -d "{\"objects\":[{\"type\":\"$t\",\"id\":\"$id\"}]}" \
      || true
      return 0
    fi
  done
  return 1
}

exists_title () { # $1 type, $2 exact title
  [ -n "$(find_id_by_title "$1" "$2")" ]
}

# -------- Validação --------
echo "✓ ES/Kibana respondendo"
curl -s "$ES" > /dev/null
curl -s "$KBN" > /dev/null

# Pré-requisitos
if curl -s "$ES/logs" | grep -q '"acknowledged":true\|{"logs"'; then
  ok "Índice 'logs' existe"
else
  bad "Índice 'logs' não encontrado"
fi

if $CURL_KBN "$KBN/api/data_views/data_view" | grep -q '"name":"logs"'; then
  ok "Data View 'logs' com @timestamp"
else
  bad "Data View 'logs' não encontrado ou sem @timestamp"
fi

echo "—"
echo "🧪 Tarefas (validação por NOME exato)"

# ========= T1 =========
if exists_title search "T1"; then
  T1_JSON=$(export_by_title "T1" "search" || true)
  if [ -n "${T1_JSON:-}" ] && echo "$T1_JSON" | grep -Fq 'service.name' \
     && ( echo "$T1_JSON" | grep -Fq '"gte":500' || echo "$T1_JSON" | grep -Eq 'status_code[[:space:]]*\\?>=\\?[[:space:]]*500' ); then
    ok "T1: Saved Search 'T1' com service.name e status_code >= 500"
  else
    bad "T1: 'T1' encontrado, mas query não contém service.name + status_code>=500"
  fi
else
  bad "T1: Saved Search 'T1' não encontrado"
  info "Títulos existentes (search):"; titles_of search | sed 's/^/   - /'
fi

# ========= T2 =========
if exists_title lens "Treino - CPU por Serviço" || exists_title visualization "Treino - CPU por Serviço"; then
  ok "T2: 'Treino - CPU por Serviço' encontrado"
else
  bad "T2: 'Treino - CPU por Serviço' não encontrado"
  info "Títulos existentes (lens/visualization):"; titles_of lens | sed 's/^/   - /'; titles_of visualization | sed 's/^/   - /'
fi

# ========= T3 =========
if exists_title lens "Treino - Top 5 Hosts por Memória" || exists_title visualization "Treino - Top 5 Hosts por Memória"; then
  ok "T3: 'Treino - Top 5 Hosts por Memória' encontrado (título confere)"
else
  bad "T3: 'Treino - Top 5 Hosts por Memória' não encontrado"
fi

# ========= T4 =========
if $CURL_KBN "$KBN/api/saved_objects/_find?type=map&per_page=1000" | grep -q 'geoip.location'; then
  ok "T4: Mapa com geoip.location encontrado"
else
  bad "T4: mapa/visual com geoip.location não encontrado"
fi

# ========= T5 =========
if exists_title dashboard "Treino - Dashboard Consolidado"; then
  ok "T5: Dashboard 'Treino - Dashboard Consolidado' encontrado"
else
  bad "T5: Dashboard 'Treino - Dashboard Consolidado' não encontrado"
fi

# ========= T6 =========
if curl -s "$ES/_ml/anomaly_detectors" | grep -q 'memory_percent'; then
  if curl -s "$ES/_ml/anomaly_detectors" | grep -q '"function":"mean".*"field_name":"memory_percent".*"bucket_span":"15m"'; then
    ok "T6: Job ML confere com gabarito"
  else
    bad "T6: Job ML existe mas difere do gabarito (Single Metric • mean(memory_percent) • 15m)"
  fi
else
  bad "T6: Job ML não encontrado"
fi

# ========= T7 =========
if curl -s "$ES/.alerts*" | grep -q 'rule'; then
  ok "T7: Regra de alerta localizada"
else
  info "T7: não localizei regra (pode depender de conector/licença)."
fi

# ========= T8 =========
if exists_title dashboard "Treino - Dashboard Consolidado"; then
  ok "T8: Dashboard existe (export NDJSON é manual)"
else
  bad "T8: Dashboard não encontrado"
fi
