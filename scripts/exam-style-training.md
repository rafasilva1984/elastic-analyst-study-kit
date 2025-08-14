# Treino Cronometrado - Elastic Certified Analyst (2 horas)

⏱ **Tempo total:** 2 horas
💡 **Dica:** Tente seguir ~10-12 minutos por tarefa

---

## Tarefa 1 - Pesquisa Avançada (Discover)
Encontre todos os logs do serviço `payment-service` com `status_code` >= 500 ocorridos nas últimas 24 horas.

---

## Tarefa 2 - Agregações (Discover → Visualize)
Crie uma tabela que mostre a média de `cpu_percent` por `host.name`.
- Ordene do maior para o menor
- Exiba apenas os 5 principais hosts

---

## Tarefa 3 - Gráfico de Linhas
Mostre a variação de `memory_percent` ao longo do tempo, agregada por serviço (`service.name`).
- Intervalo: 1h
- Período: Últimos 7 dias

---

## Tarefa 4 - Mapa de Localização
Usando o campo `geoip.location`, crie um mapa que mostre todos os eventos geolocalizados.

---

## Tarefa 5 - Dashboard Consolidado
Monte um painel com:
- Gráfico de linhas: uso de CPU por serviço
- Tabela: top 5 hosts por uso de memória
- Gráfico de barras: contagem de erros HTTP (status >= 400) por serviço

---

## Tarefa 6 - Job de Machine Learning
Crie um **Single Metric Job** para detectar anomalias no campo `memory_percent`:
- Índice: `logs`
- Intervalo de bucket: 15m
- Período: últimos 30 dias

---

## Tarefa 7 - Alerta
Crie um alerta que dispare quando o `cpu_percent` médio de um host exceder 90% em 15 minutos.

---

## Tarefa 8 - Exportação de Dashboard
Exporte o dashboard criado na Tarefa 5 para um arquivo `.ndjson`.

---

## Finalização
- Salve todas as visualizações com nomes claros (ex.: `Treino - CPU por Serviço`)
- Salve o job ML com nome `Treino - Anomalia Memória`
- Revise se todos os filtros estão corretos
