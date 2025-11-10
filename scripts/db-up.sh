#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not on PATH. Please install Docker Desktop."
  exit 1
fi

echo "Starting PostgreSQL with docker-compose..."
docker compose up -d postgres

echo "✔ PostgreSQL is starting. Connection info:"
echo "  HOST: ${POSTGRES_HOST:-127.0.0.1}"
echo "  PORT: ${POSTGRES_PORT:-5432}"
echo "  USER: ${POSTGRES_USER:-postgres}"
echo "  PASS: ${POSTGRES_PASSWORD:-postgres}"
echo "  DB:   ${POSTGRES_DB:-afcon}"

