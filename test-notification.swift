#!/usr/bin/env swift

import Foundation

// Simple script to test device registration and Live Activity via gRPC
// This will use the AFCONClient package

let deviceToken = "7f89eea16ba1c3ef23736d96e8cb533b5b1f1deb49ed73feadf4a6dbc0dbe953"
let serverHost = "staging-grpc-nlb-823dd7fe6a5be8b9.elb.eu-north-1.amazonaws.com"
let serverPort = 50051
let fixtureId: Int32 = 1347272 // Sudan vs Burkina Faso

print("🏆 AFCON Notification Test")
print("Connecting to \(serverHost):\(serverPort)...")
print("Device Token: \(deviceToken)")
print("Fixture ID: \(fixtureId) (Sudan vs Burkina Faso)")
print("")

// We'll need to use the compiled client
// For now, let's just show what needs to be done
print("Next steps:")
print("1. Register device with RegisterDevice RPC")
print("2. Get device_uuid from response")
print("3. Call StartLiveActivity with device_uuid and fixture_id")
print("")
print("Run this from your iOS app instead, or use grpcurl to test")
