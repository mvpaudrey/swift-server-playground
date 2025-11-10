#!/bin/bash

# Start AFCON Middleware Server
echo "🚀 Starting AFCON Middleware Server..."
echo ""

# Check if Redis is running
echo "📡 Checking Redis..."
if ! redis-cli ping > /dev/null 2>&1; then
    echo "⚠️  Redis is not running. Starting Redis..."
    brew services start redis
    sleep 2
fi

echo "✅ Redis is running"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "⚠️  .env file not found. Copying from .env.example..."
    cp .env.example .env
fi

echo "✅ Environment configured"
echo ""

# Load environment variables from .env (export all)
set -a
source .env
set +a
if [ -n "$DATABASE_URL" ]; then
  echo "🐘 Using DATABASE_URL from environment"
else
  echo "⚠️  DATABASE_URL is not set. Postgres may not be configured."
fi

# Ensure PostgreSQL is running (try Docker first, then Homebrew)
POSTGRES_HOST=${POSTGRES_HOST:-127.0.0.1}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
POSTGRES_DB=${POSTGRES_DB:-afcon}

echo "🔎 Checking PostgreSQL availability at ${POSTGRES_HOST}:${POSTGRES_PORT}..."

check_pg() {
  # Try psql if available
  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'SELECT 1;' >/dev/null 2>&1 && return 0
  fi
  # Fallback to nc if available
  if command -v nc >/dev/null 2>&1; then
    nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" >/dev/null 2>&1 && return 0
  fi
  return 1
}

if ! check_pg; then
  echo "⚠️  PostgreSQL not reachable. Attempting to start via Docker Compose..."
  if command -v docker >/dev/null 2>&1; then
    if command -v docker compose >/dev/null 2>&1; then
      echo "▶️  docker compose up -d postgres"
      docker compose up -d postgres || true
      echo "⏳ Waiting for PostgreSQL to accept connections..."
      for i in {1..30}; do
        if check_pg; then
          echo "✅ PostgreSQL is up."
          break
        fi
        sleep 1
      done
    fi
  fi
fi

if ! check_pg; then
  echo "⚠️  Docker not available or Postgres still not reachable. Trying Homebrew setup (macOS)..."
  if [ -x "scripts/setup-postgres-macos.sh" ]; then
    ./scripts/setup-postgres-macos.sh || true
  fi
fi

if ! check_pg; then
  echo "❌ Could not reach PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}."
  echo "   Please start Postgres manually, or run ./scripts/db-up.sh (Docker Desktop)"
  echo "   or ./scripts/setup-postgres-macos.sh (Homebrew)."
  exit 1
fi

# Build and run the server
echo "🔨 Building server..."
swift build

if [ $? -eq 0 ]; then
    echo "✅ Build successful"
    echo ""
    echo "🚀 Starting servers..."
    echo "   - HTTP Server: http://localhost:8080"
    echo "   - gRPC Server: localhost:50051"
    echo ""
    swift run Run
else
    echo "❌ Build failed"
    exit 1
fi
