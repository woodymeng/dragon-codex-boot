import Foundation

public enum FinishReason: String { case skipped, timeout, mediaTimeout, ended, failed }
public enum PlaybackCommand: Equatable { case none, hold, resume, finish(FinishReason) }

/// Pure state machine; elapsed time must be monotonic, independent of a paused player.
public struct PlaybackState {
    public private(set) var holding = false
    public private(set) var finished = false
    public private(set) var transitioning = false
    private var waitStarted: Double?
    private let config: Configuration
    public init(config: Configuration) { self.config = config }

    public mutating func tick(elapsed: Double, mediaTime: Double, mediaLoaded: Bool,
                              ready: Bool, ended: Bool = false, skip: Bool = false,
                              failed: Bool = false) -> PlaybackCommand {
        if finished { return .none }
        if skip { return finish(.skipped) }
        if failed { return finish(.failed) }
        if elapsed >= config.maxTotalSeconds { return finish(.timeout) }
        if !mediaLoaded {
            return elapsed >= config.mediaLoadTimeout ? finish(.mediaTimeout) : .none
        }
        if let since = waitStarted, elapsed - since >= config.maxWaitSeconds { return finish(.timeout) }
        // Enforce the hold before processing EOF (also covers a timer delayed by loading).
        if !ready && !transitioning && mediaTime >= config.holdAt {
            if !holding {
                holding = true; waitStarted = elapsed
                return .hold
            }
            return .none
        }
        if holding && ready {
            holding = false; waitStarted = nil
            return .resume
        }
        if ready && mediaTime >= config.transitionStart { transitioning = true }
        if ended { return finish(.ended) }
        return .none
    }

    private mutating func finish(_ reason: FinishReason) -> PlaybackCommand {
        finished = true; holding = false
        return .finish(reason)
    }
}
