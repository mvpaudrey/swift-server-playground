#!/usr/bin/env python3

import json
import jwt
import time
import requests
import sys
import subprocess

print("🧪 APNS Test Notification Sender")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print()

# Get APNS credentials from AWS Secrets Manager
print("📥 Fetching APNS credentials from AWS Secrets Manager...")
result = subprocess.run(
    ["aws", "secretsmanager", "get-secret-value",
     "--secret-id", "staging-afcon-apns",
     "--region", "eu-north-1",
     "--query", "SecretString",
     "--output", "text"],
    capture_output=True,
    text=True
)

if result.returncode != 0:
    print(f"❌ Error fetching secret: {result.stderr}")
    sys.exit(1)

secret = json.loads(result.stdout)

KEY_ID = secret["key_id"]
TEAM_ID = secret["team_id"]
TOPIC = secret["topic"]
PRIVATE_KEY = secret["key"]
DEVICE_TOKEN = "7f89eea16ba1c3ef23736d96e8cb533b5b1f1deb49ed73feadf4a6dbc0dbe953"

print(f"✅ Credentials loaded")
print(f"   Key ID: {KEY_ID}")
print(f"   Team ID: {TEAM_ID}")
print(f"   Topic: {TOPIC}")
print(f"   Device: {DEVICE_TOKEN[:20]}...")
print()

# Generate JWT token
print("🔐 Generating JWT token...")
token_timestamp = int(time.time())

headers = {
    "alg": "ES256",
    "kid": KEY_ID
}

payload = {
    "iss": TEAM_ID,
    "iat": token_timestamp
}

try:
    token = jwt.encode(
        payload,
        PRIVATE_KEY,
        algorithm="ES256",
        headers=headers
    )
    print("✅ JWT token generated")
    print()
except Exception as e:
    print(f"❌ Error generating JWT: {e}")
    sys.exit(1)

# Prepare notification payload
notification_payload = {
    "aps": {
        "alert": {
            "title": "🧪 Test Notification",
            "body": "APNS credentials updated successfully! Notifications are working."
        },
        "sound": "default",
        "badge": 1
    },
    "test": True,
    "timestamp": token_timestamp
}

# Send to Apple APNS (development environment)
apns_url = f"https://api.development.push.apple.com/3/device/{DEVICE_TOKEN}"

headers = {
    "authorization": f"bearer {token}",
    "apns-topic": TOPIC,
    "apns-push-type": "alert",
    "apns-priority": "10"
}

print("📤 Sending test notification to Apple APNS...")
print(f"   Endpoint: {apns_url}")
print(f"   Topic: {TOPIC}")
print()

try:
    response = requests.post(
        apns_url,
        headers=headers,
        json=notification_payload,
        timeout=10
    )

    print(f"📊 Response Status: {response.status_code}")

    if response.status_code == 200:
        print("✅ SUCCESS! Test notification sent successfully!")
        print()
        print("📱 Check your iOS device for the notification:")
        print("   Title: '🧪 Test Notification'")
        print("   Body: 'APNS credentials updated successfully! Notifications are working.'")
        print()
    else:
        print(f"❌ Failed to send notification")
        print(f"   Status: {response.status_code}")
        print(f"   Reason: {response.reason}")
        if response.text:
            print(f"   Response: {response.text}")
        print()
        print("Common error codes:")
        print("   400 - Bad request (malformed notification)")
        print("   403 - Invalid credentials or certificate")
        print("   410 - Device token is no longer active")

except requests.exceptions.RequestException as e:
    print(f"❌ Network error: {e}")
    sys.exit(1)
