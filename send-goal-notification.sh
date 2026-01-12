#!/bin/bash

echo "⚽ Sending Goal Notification Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Fetch credentials from AWS Secrets Manager
echo "📥 Fetching APNS credentials..."
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

echo "✅ Credentials loaded (Key: $KEY_ID)"
echo ""

# Save private key to temp file
TEMP_KEY="/tmp/apns_key_$$.p8"
echo "$PRIVATE_KEY" > "$TEMP_KEY"

# Generate JWT token
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

echo "✅ JWT token generated"
echo ""

# Prepare goal notification payload - mimicking the real system
NOTIFICATION_PAYLOAD=$(cat <<EOF
{
  "aps": {
    "alert": {
      "title": "⚽ GOAL!",
      "body": "Mohamed Salah scores! Egypt 2-1 Senegal (23')"
    },
    "sound": "goal.aiff",
    "badge": 1
  },
  "type": "goal",
  "fixture_id": "1505616",
  "scorer": "Mohamed Salah",
  "minute": "23"
}
EOF
)

# Send notification
APNS_URL="https://api.development.push.apple.com/3/device/$DEVICE_TOKEN"

echo "📤 Sending goal notification..."
echo "   ⚽ GOAL - Egypt | 23' Mohamed Salah"
echo "   📱 Device: ${DEVICE_TOKEN:0:20}..."
echo ""

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" --http2 \
  -X POST \
  -H "authorization: bearer $JWT_TOKEN" \
  -H "apns-topic: $TOPIC" \
  -H "apns-push-type: alert" \
  -H "apns-priority: 10" \
  -H "content-type: application/json" \
  -d "$NOTIFICATION_PAYLOAD" \
  "$APNS_URL")

# Extract status code
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -1)

# Clean up
rm -f "$TEMP_KEY"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Response Status: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ SUCCESS! Goal notification sent!"
  echo ""
  echo "📱 Your device should receive:"
  echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   ⚽ GOAL!"
  echo "   Mohamed Salah scores!"
  echo "   Egypt 2-1 Senegal (23')"
  echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "   With sound: goal.aiff 🔔"
  echo ""
elif [ "$HTTP_CODE" = "400" ]; then
  echo "❌ Bad Request (400)"
elif [ "$HTTP_CODE" = "403" ]; then
  echo "❌ Forbidden (403) - Authentication failed"
elif [ "$HTTP_CODE" = "410" ]; then
  echo "❌ Device Token Inactive (410)"
else
  echo "❌ Unexpected response: $HTTP_CODE"
fi
