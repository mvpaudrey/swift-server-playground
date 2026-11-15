import Foundation
import Logging

/// A `LogHandler` that prints one line per event, prefixed with a wall-clock time:
///
///     [08:34:12.482] INFO  🚀 Starting AFCON Middleware
///     [08:34:27.913] INFO  🎬 DEMO goal — England 1-0 Tanzania @ 12'
///
/// Used instead of Vapor's colourised console logger so the server log reads clearly
/// when it's projected during the talk.
public struct TimestampLogHandler: LogHandler {
    public var logLevel: Logger.Level
    public var metadata: Logger.Metadata = [:]
    private let label: String

    public init(label: String, logLevel: Logger.Level) {
        self.label = label
        self.logLevel = logLevel
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata explicitMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let time = Self.timeFormatter.string(from: Date())
        // Drop noisy per-request metadata so the projected log stays readable.
        let noisyKeys: Set<String> = ["request-id", "request-method", "request-path", "connection-id"]
        let merged = metadata
            .merging(explicitMetadata ?? [:]) { $1 }
            .filter { !noisyKeys.contains($0.key) }
        let meta = merged.isEmpty
            ? ""
            : " " + merged.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let padded = level.name.padding(toLength: 5, withPad: " ", startingAt: 0)
        print("[\(time)] \(padded) \(message)\(meta)")
    }
}

private extension Logger.Level {
    var name: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRIT"
        }
    }
}
