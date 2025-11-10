#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not on PATH."
  exit 1
fi

echo "Stopping PostgreSQL..."
docker compose rm -sf postgres
echo "✔ PostgreSQL container removed."

