# Elastic Certified Analyst - Study Kit

Este kit simula um ambiente prático para treinar para a certificação **Elastic Certified Analyst**.

## 📂 Conteúdo
- `docker-compose.yml` → Sobe Elasticsearch + Kibana (7.15.2)
- `data/sample-logs.json` → Dataset realista com 10.000 documentos
- `scripts/load-data.sh` → Script para ingestão de dados
- `scripts/reset-env.sh` → Reset do ambiente com recarga dos dados
- `scripts/tasks.md` → Lista de tarefas estilo exame
- `scripts/exam-style-training.md` → Treino cronometrado de 2 horas
- `scripts/exam-style-training-answers.md` → Gabarito do treino
- `docs/quick-start.md` → Guia rápido para iniciar
- `docs/kql-cheatsheet.md` → Guia rápido de queries KQL
- `docs/ml-jobs-guide.md` → Guia rápido de Machine Learning
- `docs/exam-checklist.md` → Checklist rápido para o dia do exame

## 🚀 Como usar
1. **Subir ambiente**:
```bash
docker compose up -d
```

2. **Carregar dados**:
```bash
./scripts/load-data.sh
```

3. **Acessar Kibana**:
http://localhost:5601

4. **Executar tarefas**:
Siga `scripts/tasks.md` e pratique.

## 🏁 Treino Cronometrado
Veja `scripts/exam-style-training.md` para um treino de 2 horas simulando o exame real.

## 📄 Gabarito do Treino
Compare no arquivo `scripts/exam-style-training-answers.md`.

## 🗒 Checklist Rápido
Veja `docs/exam-checklist.md` para ter dicas rápidas de execução no dia do exame.

---
💡 **Dica:** Treine navegando na documentação da Elastic para ganhar tempo no exame.
