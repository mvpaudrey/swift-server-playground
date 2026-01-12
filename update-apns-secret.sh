#!/bin/bash

# Update APNS credentials in AWS Secrets Manager

echo "🔐 APNS Credentials Updater"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script will update the staging-afcon-apns secret"
echo ""

# Check if .p8 file path is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <path-to-apns-key.p8> <key-id> <team-id> <bundle-id>"
  echo ""
  echo "Example:"
  echo "  $0 ~/Downloads/AuthKey_ABC123.p8 ABC123 XYZ456 com.cheulah.AFCON2025"
  echo ""
  echo "Or manually provide the key:"
  echo "  Key ID (found in Apple Developer): "
  read -r KEY_ID
  echo "  Team ID (found in Apple Developer): "
  read -r TEAM_ID
  echo "  App Bundle ID (e.g., com.cheulah.AFCON2025): "
  read -r TOPIC
  echo "  Path to .p8 file: "
  read -r KEY_FILE
else
  KEY_FILE="$1"
  KEY_ID="$2"
  TEAM_ID="$3"
  TOPIC="$4"
fi

# Validate inputs
if [ ! -f "$KEY_FILE" ]; then
  echo "❌ Error: Key file not found: $KEY_FILE"
  exit 1
fi

if [ -z "$KEY_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$TOPIC" ]; then
  echo "❌ Error: Key ID, Team ID, and Bundle ID are required"
  exit 1
fi

# Read the key file
KEY_CONTENT=$(cat "$KEY_FILE")

# Validate key format
if ! echo "$KEY_CONTENT" | grep -q "BEGIN PRIVATE KEY"; then
  echo "❌ Error: Invalid key format. File should contain '-----BEGIN PRIVATE KEY-----'"
  exit 1
fi

echo ""
echo "📋 Configuration to upload:"
echo "  Key ID:    $KEY_ID"
echo "  Team ID:   $TEAM_ID"
echo "  Topic:     $TOPIC"
echo "  Key File:  $KEY_FILE"
echo ""

# Create JSON payload
SECRET_JSON=$(jq -n \
  --arg key_id "$KEY_ID" \
  --arg team_id "$TEAM_ID" \
  --arg topic "$TOPIC" \
  --arg key "$KEY_CONTENT" \
  '{
    key_id: $key_id,
    team_id: $team_id,
    topic: $topic,
    key: $key
  }')

echo "Updating AWS secret: staging-afcon-apns..."
aws secretsmanager update-secret \
  --secret-id staging-afcon-apns \
  --secret-string "$SECRET_JSON" \
  --region eu-north-1

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Secret updated successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Restart ECS service to pick up new credentials"
  echo "  2. Test notifications"
  echo ""
  echo "Run this to restart:"
  echo "  aws ecs update-service --cluster staging-afcon-cluster --service afcon-service --force-new-deployment --region eu-north-1"
else
  echo "❌ Failed to update secret"
  exit 1
fi
