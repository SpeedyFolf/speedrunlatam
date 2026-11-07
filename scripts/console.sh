#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# `docker compose up` no reenvía stdin. Se levanta en segundo plano y se
# adjunta el contenedor para poder escribir en la consola de MTA.
docker compose up -d --wait 2>/dev/null || docker compose up -d

if docker compose attach server; then
    exit 0
fi

# Fallback para versiones de Compose sin subcomando attach.
exec docker attach "$(docker compose ps -q server)"
