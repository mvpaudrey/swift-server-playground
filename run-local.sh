#!/bin/bash

# Run AFCON server locally with Docker databases
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/afcon?sslmode=disable"
export REDIS_URL="redis://localhost:6379"
export ENVIRONMENT="development"
export LOG_LEVEL="debug"
export PORT="8080"
export GRPC_PORT="50051"

# Optional: Load additional environment variables from .env
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | xargs)
fi

echo "Starting AFCON server..."
echo "Database: $DATABASE_URL"
echo "Redis: $REDIS_URL"
echo "HTTP Port: $PORT"
echo "gRPC Port: $GRPC_PORT"
echo ""

swift run Run serve --hostname 0.0.0.0 --port $PORT
