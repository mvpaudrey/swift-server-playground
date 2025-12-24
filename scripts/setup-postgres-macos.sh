#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Setting up local PostgreSQL (macOS/Homebrew)..."

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install from https://brew.sh/ and re-run."
  exit 1
fi

if ! brew list postgresql@16 >/dev/null 2>&1; then
  echo "Installing postgresql@16 via Homebrew..."
  brew install postgresql@16
fi

echo "Starting postgresql@16..."
brew services start postgresql@16
sleep 2

export POSTGRES_HOST=${POSTGRES_HOST:-127.0.0.1}
export POSTGRES_PORT=${POSTGRES_PORT:-5432}
export POSTGRES_USER=${POSTGRES_USER:-postgres}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
export POSTGRES_DB=${POSTGRES_DB:-afcon}

echo "Ensuring database and user exist..."
createuser -s ${POSTGRES_USER} || true
createdb ${POSTGRES_DB} || true

echo "Setting password for ${POSTGRES_USER}..."
psql -h ${POSTGRES_HOST} -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';" || true

echo "✅ Postgres ready at ${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
echo "   user: ${POSTGRES_USER} password: ${POSTGRES_PASSWORD}"

