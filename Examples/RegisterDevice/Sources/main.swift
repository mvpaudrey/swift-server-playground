import AFCONClient
import Foundation

@main
struct RegisterDeviceExample {
    static let serverHost = "staging-grpc-nlb-823dd7fe6a5be8b9.elb.eu-north-1.amazonaws.com"
    static let serverPort = 50051

    static let deviceToken = "7f89eea16ba1c3ef23736d96e8cb533b5b1f1deb49ed73feadf4a6dbc0dbe953"
    static let fixtureId: Int32 = 1347272 // Sudan vs Burkina Faso at 16:00 UTC

    static func main() async throws {
        print("🏆 AFCON Device Registration & Live Activity Test")
        print("Connecting to \(serverHost):\(serverPort)...")
        print("")

        guard #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) else {
            print("❌ This example requires macOS 15.0+ (or equivalent OS versions).")
            return
        }

        let service = try AFCONService(host: serverHost, port: serverPort)
        print("✅ Connected to gRPC server\n")

        // Step 1: Register Device
        print("📱 Step 1: Registering device...")
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        let registerResponse = try await service.registerDevice(
            userId: "test-user-\(UUID().uuidString)",
            deviceToken: deviceToken,
            platform: "ios",
            deviceId: deviceId,
            appVersion: "1.0.0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            language: "en",
            timezone: TimeZone.current.identifier
        )

        if registerResponse.success {
            print("✅ Device registered successfully!")
            print("   Device UUID: \(registerResponse.deviceUuid)")
            print("   Message: \(registerResponse.message)")
            print("")

            // Step 2: Start Live Activity
            print("🔴 Step 2: Starting Live Activity for Sudan vs Burkina Faso...")
            let activityId = "activity-\(UUID().uuidString)"

            let liveActivityResponse = try await service.startLiveActivity(
                deviceUuid: registerResponse.deviceUuid,
                fixtureId: fixtureId,
                activityId: activityId,
                pushToken: deviceToken, // In real app, this would be ActivityKit push token
                updateFrequency: "all_events"
            )

            if liveActivityResponse.success {
                print("✅ Live Activity started successfully!")
                print("   Activity UUID: \(liveActivityResponse.activityUuid)")
                print("   Message: \(liveActivityResponse.message)")
                print("")
                print("🎉 All set! You should receive notifications when the match starts or has updates.")
            } else {
                print("❌ Failed to start Live Activity: \(liveActivityResponse.message)")
            }
        } else {
            print("❌ Failed to register device: \(registerResponse.message)")
        }
    }
}

// Dummy UIDevice for macOS compilation
#if os(macOS)
struct UIDevice {
    static let current = UIDevice()
    var identifierForVendor: UUID? { UUID() }
}
#endif
