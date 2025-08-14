#!/bin/bash
echo "♻  Resetando ambiente (containers e volumes)..."
docker compose down -v
docker compose up -d
echo "🔁 Recarregando dados..."
./scripts/load-data.sh
echo "✅ Ambiente resetado."
