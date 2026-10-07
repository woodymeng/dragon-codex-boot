import Foundation

public struct ScreenFrame: Codable, Equatable {
    public let time: Double
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(time: Double, x: Double, y: Double, width: Double, height: Double) {
        self.time = time; self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct Configuration: Codable {
    public var video = "media/startup.mp4"
    public var bundleIdentifier = "com.openai.codex"
    public var applicationPath = "/Applications/Codex.app"
    public var holdAt = 11.3
    public var transitionStart = 12.7
    public var transitionEnd = 13.65
    public var maxWaitSeconds = 60.0
    public var maxTotalSeconds = 90.0
    public var mediaLoadTimeout = 12.0
    public var captureStartTimeout = 3.0
    public var stableWindowSeconds = 0.6
    public var volume = 1.0
    // AppKit points; fit to the selected screen's visibleFrame, preserving 16:9.
    public var playerWidth = 1280.0
    public var playerHeight = 720.0
    public var matchClientToPlayer = true
    public var screenFrames = [
        ScreenFrame(time: 12.65, x: 0.123, y: 0.094, width: 0.736, height: 0.725),
        ScreenFrame(time: 13, x: 0.074, y: 0.061, width: 0.845, height: 0.825),
        ScreenFrame(time: 13.5, x: 0, y: 0, width: 1, height: 1),
        ScreenFrame(time: 13.65, x: 0, y: 0, width: 1, height: 1)
    ]

    public init() {}

    public static func load(from url: URL) throws -> Configuration {
        let result = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }

    public func validate() throws {
        let numbers = [holdAt, transitionStart, transitionEnd, maxWaitSeconds, maxTotalSeconds,
                       mediaLoadTimeout, captureStartTimeout, stableWindowSeconds, volume,
                       playerWidth, playerHeight]
        guard numbers.allSatisfy({ $0.isFinite }), holdAt > 0,
              transitionStart > holdAt, transitionEnd > transitionStart,
              maxWaitSeconds > 0, maxTotalSeconds > transitionEnd,
              mediaLoadTimeout > 0, captureStartTimeout > 0, stableWindowSeconds >= 0,
              (0...1).contains(volume), playerWidth >= 320, playerHeight >= 180 else {
            throw ValidationError.invalid("Invalid timing, volume, or window dimensions")
        }
        guard !bundleIdentifier.isEmpty, applicationPath.hasPrefix("/"),
              applicationPath.hasSuffix(".app"), !video.isEmpty else {
            throw ValidationError.invalid("Specify a bundle identifier, absolute .app path, and video")
        }
        guard screenFrames.count >= 2,
              screenFrames.first!.time <= transitionStart,
              screenFrames.last!.time >= transitionEnd else {
            throw ValidationError.invalid("Screen frames must cover the entire transition")
        }
        var previous = -Double.infinity
        for frame in screenFrames {
            guard [frame.time, frame.x, frame.y, frame.width, frame.height].allSatisfy({ $0.isFinite }),
                  frame.time >= 0, frame.time > previous, frame.x >= 0, frame.y >= 0,
                  frame.width > 0, frame.height > 0,
                  frame.x + frame.width <= 1.000001, frame.y + frame.height <= 1.000001 else {
                throw ValidationError.invalid("Frames must be ordered, finite, and inside the video")
            }
            previous = frame.time
        }
    }

    public func validateMedia(duration: Double, hasVideo: Bool) throws {
        guard hasVideo, duration.isFinite, duration >= transitionEnd, duration < maxTotalSeconds else {
            throw ValidationError.invalid("Video must contain a video track and cover the transition within the total deadline")
        }
    }
}

public enum ValidationError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self { case .invalid(let message): return message }
    }
}
