# Elastic Certified Analyst Study Kit — 8.8 (fiel ao exame)

**Objetivo**: simular o ambiente do exame (Elastic 8.8) e validar rapidamente se você criou os itens pedidos.

## Como usar
```bash
docker compose up -d
./scripts/load-data.sh
./scripts/create-data-view.sh
# Abra http://localhost:5601 e ajuste o Time picker para JUL/2025
# Crie as visuais, dashboard e job ML com os nomes indicados abaixo
./scripts/validate.sh
```

## Itens esperados pelo validador
- Visualização: **Treino - CPU por Serviço** (média de `cpu_percent` por `service.name`)
- Visualização: **Treino - Top 5 Hosts por Memória** (tabela top 5 `host.name` por média de `memory_percent`)
- Visualização: **Treino - Erros HTTP por Serviço** (contagem com `status_code >= 400` por `service.name`)
- Dashboard: **Treino - Dashboard Consolidado**
- Job ML (job_id): **treino_anomalia_memoria** (Single metric em `memory_percent`, bucket `15m`)

> O validador checa EXISTÊNCIA/NOME e a presença do Job ML, não a configuração detalhada.

Veja `docs/quick-start.md`, `docs/ml-guide.md` e `docs/kql-cheatsheet.md`.
