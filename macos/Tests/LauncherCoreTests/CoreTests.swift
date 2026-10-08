#if DRAGON_CLT_TESTS
import Foundation
#else
import XCTest
#endif
@testable import LauncherCore

final class ConfigurationTests: XCTestCase {
    func testBundledConfigurationMatchesMediaTimeline() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let config = try Configuration.load(from: root.appendingPathComponent("Resources/launcher.example.json"))
        XCTAssertEqual(config.holdAt, 11.3)
        XCTAssertEqual(config.transitionEnd, 13.65)
        XCTAssertEqual(config.bundleIdentifier, "com.openai.codex")
        try config.validateMedia(duration: 14.101, hasVideo: true)
    }

    func testInvalidTimingRejected() {
        var config = Configuration()
        config.transitionStart = config.holdAt
        XCTAssertThrowsError(try config.validate())
        config = Configuration(); config.maxWaitSeconds = 0
        XCTAssertThrowsError(try config.validate())
        config = Configuration(); config.maxTotalSeconds = 10
        XCTAssertThrowsError(try config.validate())
    }

    func testNonfiniteNumbersRejected() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            var config = Configuration(); config.volume = value
            XCTAssertThrowsError(try config.validate())
            config = Configuration(); config.holdAt = value
            XCTAssertThrowsError(try config.validate())
        }
    }

    func testInvalidWindowAndVolumeRejected() {
        var config = Configuration(); config.playerWidth = 100
        XCTAssertThrowsError(try config.validate())
        config = Configuration(); config.volume = 1.01
        XCTAssertThrowsError(try config.validate())
    }

    func testFramesMustBeOrderedAndWithinVideo() {
        var config = Configuration()
        config.screenFrames.swapAt(0, 1)
        XCTAssertThrowsError(try config.validate())
        config = Configuration()
        config.screenFrames[1] = ScreenFrame(time: 13, x: 0.9, y: 0, width: 0.5, height: 1)
        XCTAssertThrowsError(try config.validate())
        config = Configuration()
        config.screenFrames[1] = ScreenFrame(time: 13, x: 0, y: 0, width: 0, height: 1)
        XCTAssertThrowsError(try config.validate())
    }

    func testFramesMustCoverTransition() {
        var config = Configuration(); config.screenFrames.removeLast(2)
        XCTAssertThrowsError(try config.validate())
        config = Configuration(); config.screenFrames.removeFirst(2)
        XCTAssertThrowsError(try config.validate())
    }

    func testMalformedConfigurationAndMissingFieldsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(Configuration.self, from: Data("{bad".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8)))
    }

    func testWrongApplicationPathRejected() {
        var config = Configuration(); config.applicationPath = "Codex"
        XCTAssertThrowsError(try config.validate())
        config = Configuration(); config.bundleIdentifier = ""
        XCTAssertThrowsError(try config.validate())
    }

    func testMediaMustCoverTimelineAndContainVideo() {
        let config = Configuration()
        for duration in [0.0, 13.0, 100.0, .infinity, .nan] {
            XCTAssertThrowsError(try config.validateMedia(duration: duration, hasVideo: true))
        }
        XCTAssertThrowsError(try config.validateMedia(duration: 14.1, hasVideo: false))
    }
}

final class GeometryTests: XCTestCase {
    func testLetterboxedTransitionEndsAtNativeWindowBounds() {
        let window = Rectangle(x: 0, y: 0, width: 1512, height: 900)
        let video = Geometry.aspectFit(sourceWidth: 1920, sourceHeight: 1080, in: window)
        let frame = Configuration().screenFrames[0]
        XCTAssertEqual(Geometry.transitionDestination(frame, videoRect: video, windowRect: window, progress: 0),
                       Geometry.destination(frame, videoRect: video))
        XCTAssertEqual(Geometry.transitionDestination(frame, videoRect: video, windowRect: window, progress: 1), window)
        for step in 0...100 {
            let rect = Geometry.transitionDestination(frame, videoRect: video, windowRect: window, progress: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(rect.x, 0)
            XCTAssertGreaterThanOrEqual(rect.y, 0)
            XCTAssertLessThanOrEqual(rect.x + rect.width, window.width + 0.000001)
            XCTAssertLessThanOrEqual(rect.y + rect.height, window.height + 0.000001)
        }
    }

    func testEaseEndpointsAndMidpoint() {
        XCTAssertEqual(Geometry.ease(-1), 0)
        XCTAssertEqual(Geometry.ease(0.5), 0.5)
        XCTAssertEqual(Geometry.ease(2), 1)
    }

    func testKeyframesClampAndInterpolate() {
        let frames = [ScreenFrame(time: 1, x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                      ScreenFrame(time: 3, x: 0, y: 0, width: 1, height: 1)]
        XCTAssertEqual(Geometry.interpolate(frames, at: -1), frames[0])
        XCTAssertEqual(Geometry.interpolate(frames, at: 4), frames[1])
        let midpoint = Geometry.interpolate(frames, at: 2)
        XCTAssertEqual(midpoint.x, 0.1, accuracy: 0.000001)
        XCTAssertEqual(midpoint.height, 0.8, accuracy: 0.000001)
    }

    func testEveryTransitionSampleRemainsInsideVideo() {
        let frames = Configuration().screenFrames
        for step in 0...200 {
            let sample = Geometry.interpolate(frames, at: 12.7 + Double(step) / 200)
            XCTAssertGreaterThanOrEqual(sample.x, 0)
            XCTAssertGreaterThanOrEqual(sample.y, 0)
            XCTAssertLessThanOrEqual(sample.x + sample.width, 1.000001)
            XCTAssertLessThanOrEqual(sample.y + sample.height, 1.000001)
        }
    }

    func testTopLeftCoordinatesConvertToAppKit() {
        let frame = ScreenFrame(time: 1, x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        let rect = Geometry.destination(frame, videoRect: Rectangle(x: 10, y: 20, width: 1000, height: 500))
        XCTAssertEqual(rect.x, 110, accuracy: 0.000001)
        XCTAssertEqual(rect.y, 220, accuracy: 0.000001)
        XCTAssertEqual(rect.width, 500)
        XCTAssertEqual(rect.height, 200)
    }

    func testLetterboxingAndSmallScreenFit() {
        let box = Geometry.aspectFit(sourceWidth: 1920, sourceHeight: 1080,
                                     in: Rectangle(x: 0, y: 0, width: 800, height: 800))
        XCTAssertEqual(box.width, 800)
        XCTAssertEqual(box.height, 450)
        XCTAssertEqual(box.y, 175)
    }

    func testAccessibilityCoordinatesAcrossMultipleDisplays() {
        let left = Rectangle(x: -1280, y: 100, width: 1280, height: 720)
        let converted = Geometry.accessibilityRect(appKit: left, primaryDisplayHeight: 1080)
        XCTAssertEqual(converted, Rectangle(x: -1280, y: 260, width: 1280, height: 720))
        let above = Rectangle(x: 0, y: 1200, width: 1280, height: 720)
        XCTAssertEqual(Geometry.accessibilityRect(appKit: above, primaryDisplayHeight: 1080).y, -840)
    }
}

final class PlaybackTests: XCTestCase {
    func testColdLaunchHoldsAndResumesThenFinishesAtEOF() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 5, mediaTime: 5, mediaLoaded: true, ready: false), .none)
        XCTAssertEqual(state.tick(elapsed: 12, mediaTime: 11.31, mediaLoaded: true, ready: false), .hold)
        XCTAssertTrue(state.holding)
        XCTAssertEqual(state.tick(elapsed: 15, mediaTime: 11.3, mediaLoaded: true, ready: true), .resume)
        XCTAssertEqual(state.tick(elapsed: 17, mediaTime: 13, mediaLoaded: true, ready: true), .none)
        XCTAssertTrue(state.transitioning)
        XCTAssertEqual(state.tick(elapsed: 18, mediaTime: 13.7, mediaLoaded: true, ready: true), .none)
        XCTAssertEqual(state.tick(elapsed: 19, mediaTime: 14.1, mediaLoaded: true, ready: true, ended: true), .finish(.ended))
    }

    func testWarmLaunchDoesNotPause() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 12, mediaTime: 11.31, mediaLoaded: true, ready: true), .none)
        XCTAssertFalse(state.holding)
    }

    func testCapturePreparationCanGateReadiness() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 12, mediaTime: 11.31, mediaLoaded: true, ready: false), .hold)
        XCTAssertEqual(state.tick(elapsed: 13, mediaTime: 11.3, mediaLoaded: true, ready: false), .none)
        XCTAssertEqual(state.tick(elapsed: 14, mediaTime: 11.3, mediaLoaded: true, ready: true), .resume)
    }

    func testHoldTimeoutUsesWallClock() {
        var state = PlaybackState(config: Configuration())
        _ = state.tick(elapsed: 12, mediaTime: 11.3, mediaLoaded: true, ready: false)
        XCTAssertEqual(state.tick(elapsed: 71.9, mediaTime: 11.3, mediaLoaded: true, ready: false), .none)
        XCTAssertEqual(state.tick(elapsed: 72, mediaTime: 11.3, mediaLoaded: true, ready: false), .finish(.timeout))
    }

    func testTotalDeadlineAppliesEvenToLoadedButStalledPlayer() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 90, mediaTime: 1, mediaLoaded: true, ready: true), .finish(.timeout))
    }

    func testLoadingTimeout() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 11, mediaTime: 0, mediaLoaded: false, ready: false), .none)
        XCTAssertEqual(state.tick(elapsed: 12, mediaTime: 0, mediaLoaded: false, ready: false), .finish(.mediaTimeout))
    }

    func testSkipDuringLoadOrHoldIsImmediateAndIdempotent() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 0, mediaTime: 0, mediaLoaded: false, ready: false, skip: true), .finish(.skipped))
        XCTAssertEqual(state.tick(elapsed: 1, mediaTime: 0, mediaLoaded: false, ready: false, skip: true), .none)
        var holding = PlaybackState(config: Configuration())
        _ = holding.tick(elapsed: 12, mediaTime: 11.3, mediaLoaded: true, ready: false)
        XCTAssertEqual(holding.tick(elapsed: 13, mediaTime: 11.3, mediaLoaded: true, ready: false, skip: true), .finish(.skipped))
    }

    func testCaptureLossDuringTransitionDoesNotReenterHold() {
        var state = PlaybackState(config: Configuration())
        _ = state.tick(elapsed: 13, mediaTime: 13, mediaLoaded: true, ready: true)
        XCTAssertEqual(state.tick(elapsed: 13.5, mediaTime: 13.5, mediaLoaded: true, ready: false), .none)
        XCTAssertFalse(state.holding)
        XCTAssertEqual(state.tick(elapsed: 14.1, mediaTime: 14.1, mediaLoaded: true, ready: false, ended: true), .finish(.ended))
    }

    func testDelayedTimerAtEOFStillHoldsIfClientMissing() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 15, mediaTime: 14.1, mediaLoaded: true, ready: false, ended: true), .hold)
    }

    func testMediaFailureAlwaysTerminates() {
        var state = PlaybackState(config: Configuration())
        XCTAssertEqual(state.tick(elapsed: 1, mediaTime: 0, mediaLoaded: false, ready: false, failed: true), .finish(.failed))
    }
}
