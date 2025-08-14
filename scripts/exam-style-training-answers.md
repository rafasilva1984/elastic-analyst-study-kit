# Gabarito - Treino Cronometrado Elastic Certified Analyst

⚠ **Atenção**: Este gabarito mostra apenas o que é esperado como resultado final,
não necessariamente todos os passos de configuração.

---

## Tarefa 1 - Pesquisa Avançada
**KQL esperado:**
```
service.name : "payment-service" and status_code >= 500 and @timestamp >= now-24h
```
**Resultado esperado:**
- Lista de documentos filtrados apenas para `payment-service` com status >= 500 no período das últimas 24h.

---

## Tarefa 2 - Agregações
**Tipo de visualização:** Data Table
- **Buckets**:
  - Rows: `host.name` (Top 5, ordenado por métrica descendente)
- **Métrica**:
  - Average of `cpu_percent`
**Resultado esperado:**
- Tabela com 5 linhas (hosts) mostrando a média de CPU, ordenada do maior para o menor.

---

## Tarefa 3 - Gráfico de Linhas
**Tipo de visualização:** Line chart
- **Métrica:** Average of `memory_percent`
- **Bucket X:** Date Histogram (Intervalo: 1h)
- **Split series:** Terms → `service.name`
**Resultado esperado:**
- Múltiplas linhas (uma por serviço) mostrando variação da memória nos últimos 7 dias.

---

## Tarefa 4 - Mapa de Localização
**Tipo:** Coordinate Map / Maps
- **Campo de localização:** `geoip.location`
**Resultado esperado:**
- Pontos plotados no mapa representando eventos do índice `logs`.

---

## Tarefa 5 - Dashboard Consolidado
**Componentes esperados:**
1. Gráfico de linhas: uso médio de CPU (`cpu_percent`) por serviço (`service.name`)
2. Tabela: top 5 hosts por uso médio de memória (`memory_percent`)
3. Gráfico de barras: contagem de erros HTTP (status >= 400) por serviço
**Resultado esperado:**
- Painel limpo, com filtros aplicáveis e títulos claros.

---

## Tarefa 6 - Job de Machine Learning
**Configuração esperada:**
- Tipo: Single Metric
- Campo: `memory_percent`
- Bucket span: 15m
- Período: últimos 30 dias
**Resultado esperado:**
- Job ativo com gráfico de probabilidade e picos destacados.

---

## Tarefa 7 - Alerta
**Configuração esperada:**
- Condição: média de `cpu_percent` > 90
- Janela de tempo: 15 minutos
- Ação: Log ou e-mail (dependendo da configuração do ambiente)
**Resultado esperado:**
- Alerta configurado e pronto para disparar quando a condição for atendida.

---

## Tarefa 8 - Exportação de Dashboard
**Passos esperados:**
1. Acessar o dashboard criado na Tarefa 5
2. Menu → Share / Export → Export to NDJSON
3. Salvar arquivo `.ndjson`
**Resultado esperado:**
- Arquivo `.ndjson` contendo a definição do dashboard exportado.

---

✅ **Conclusão:** Se todas as tarefas acima foram concluídas no tempo estimado, você está muito próximo de estar pronto para o exame real.
