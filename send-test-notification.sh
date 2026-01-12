#!/bin/bash

echo "🧪 APNS Test Notification Sender (HTTP/2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Fetch credentials from AWS Secrets Manager
echo "📥 Fetching APNS credentials from AWS Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id staging-afcon-apns \
  --region eu-north-1 \
  --query SecretString \
  --output text)

KEY_ID=$(echo "$SECRET_JSON" | jq -r '.key_id')
TEAM_ID=$(echo "$SECRET_JSON" | jq -r '.team_id')
TOPIC=$(echo "$SECRET_JSON" | jq -r '.topic')
PRIVATE_KEY=$(echo "$SECRET_JSON" | jq -r '.key')
DEVICE_TOKEN="7f89eea16ba1c3ef23736d96e8cb533b5b1f1deb49ed73feadf4a6dbc0dbe953"

echo "✅ Credentials loaded"
echo "   Key ID: $KEY_ID"
echo "   Team ID: $TEAM_ID"
echo "   Topic: $TOPIC"
echo "   Device: ${DEVICE_TOKEN:0:20}..."
echo ""

# Save private key to temp file
TEMP_KEY="/tmp/apns_key_$$.p8"
echo "$PRIVATE_KEY" > "$TEMP_KEY"

# Generate JWT token using Python
echo "🔐 Generating JWT token..."
JWT_TOKEN=$(python3 << EOF
import jwt
import time

with open("$TEMP_KEY", "r") as f:
    private_key = f.read()

headers = {"alg": "ES256", "kid": "$KEY_ID"}
payload = {"iss": "$TEAM_ID", "iat": int(time.time())}

token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
print(token)
EOF
)

if [ -z "$JWT_TOKEN" ]; then
  echo "❌ Failed to generate JWT token"
  rm -f "$TEMP_KEY"
  exit 1
fi

echo "✅ JWT token generated"
echo ""

# Prepare notification payload
NOTIFICATION_PAYLOAD=$(cat <<EOF
{
  "aps": {
    "alert": {
      "title": "🧪 Test Notification",
      "body": "APNS credentials updated successfully! Notifications are working. ⚽"
    },
    "sound": "default",
    "badge": 1
  },
  "test": true
}
EOF
)

# Send notification using curl with HTTP/2
APNS_URL="https://api.development.push.apple.com/3/device/$DEVICE_TOKEN"

echo "📤 Sending test notification to Apple APNS..."
echo "   Endpoint: $APNS_URL"
echo "   Topic: $TOPIC"
echo ""

HTTP_RESPONSE=$(curl -v --http2 \
  -X POST \
  -H "authorization: bearer $JWT_TOKEN" \
  -H "apns-topic: $TOPIC" \
  -H "apns-push-type: alert" \
  -H "apns-priority: 10" \
  -H "content-type: application/json" \
  -d "$NOTIFICATION_PAYLOAD" \
  "$APNS_URL" 2>&1)

HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep "< HTTP" | tail -1 | awk '{print $3}')

# Clean up temp key
rm -f "$TEMP_KEY"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Response Status: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ SUCCESS! Test notification sent successfully!"
  echo ""
  echo "📱 Check your iOS device for the notification:"
  echo "   Title: '🧪 Test Notification'"
  echo "   Body: 'APNS credentials updated successfully! Notifications are working. ⚽'"
  echo ""
  echo "🔔 If you don't see it, check:"
  echo "   1. Device is unlocked"
  echo "   2. App is installed (bundle ID: $TOPIC)"
  echo "   3. Notifications are enabled for the app"
  echo "   4. Device token is for development environment"
elif [ "$HTTP_CODE" = "400" ]; then
  echo "❌ Bad Request (400)"
  echo "   The notification payload is malformed"
  echo "$HTTP_RESPONSE" | grep -A 5 "{"
elif [ "$HTTP_CODE" = "403" ]; then
  echo "❌ Forbidden (403)"
  echo "   Authentication failed - invalid credentials"
  echo "$HTTP_RESPONSE" | grep -A 5 "{"
elif [ "$HTTP_CODE" = "410" ]; then
  echo "❌ Device Token Inactive (410)"
  echo "   The device token is no longer active"
  echo "   This can happen if the app was uninstalled"
else
  echo "❌ Unexpected response"
  echo ""
  echo "Full response:"
  echo "$HTTP_RESPONSE"
fi
