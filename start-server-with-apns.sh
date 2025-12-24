#!/bin/bash

# AFCON Server Startup Script with APNs Configuration
# This script starts the server with Live Activities enabled

echo "🚀 Starting AFCON Server with APNs enabled..."
echo ""

# APNs Configuration
export APNS_KEY_ID="K6V97L2X47"
export APNS_TEAM_ID="486Q5MQF2F"
export APNS_KEY_PATH="$HOME/.apns-keys/AuthKey_K6V97L2X47.p8"
export APNS_TOPIC="com.cheulah.AFCON2025"
export APNS_ENVIRONMENT="sandbox"

# Optional: Pause AFCON live match polling during development
# export PAUSE_AFCON_LIVE_MATCHES="true"

# League Configuration
export INIT_LEAGUES="6:2025:AFCON2025"

# Database Configuration (using defaults from configure.swift)
# export DATABASE_HOST="localhost"
# export DATABASE_PORT="5432"
# export DATABASE_NAME="afcon_db"
# export DATABASE_USERNAME="postgres"
# export DATABASE_PASSWORD=""

echo "📋 Configuration:"
echo "   APNs Key ID: $APNS_KEY_ID"
echo "   APNs Team ID: $APNS_TEAM_ID"
echo "   APNs Environment: $APNS_ENVIRONMENT"
echo "   App Bundle ID: $APNS_TOPIC"
echo "   Key Path: $APNS_KEY_PATH"
echo ""
echo "🔍 Verifying APNs key file..."

if [ ! -f "$APNS_KEY_PATH" ]; then
    echo "❌ ERROR: APNs key file not found at $APNS_KEY_PATH"
    exit 1
fi

echo "✅ APNs key file found"
echo ""
echo "🎯 Starting server..."
echo "   HTTP: http://0.0.0.0:8080"
echo "   gRPC: 0.0.0.0:50051"
echo ""

# Start the server
.build/debug/Run serve --hostname 0.0.0.0 --port 8080
