import Foundation

public struct Rectangle: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum Geometry {
    public static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    public static func interpolate(_ frames: [ScreenFrame], at time: Double) -> ScreenFrame {
        precondition(!frames.isEmpty)
        if time <= frames[0].time { return frames[0] }
        for index in 1..<frames.count where time <= frames[index].time {
            let a = frames[index - 1], b = frames[index]
            let t = ease((time - a.time) / (b.time - a.time))
            func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
            return ScreenFrame(time: time, x: mix(a.x, b.x), y: mix(a.y, b.y),
                               width: mix(a.width, b.width), height: mix(a.height, b.height))
        }
        return frames[frames.count - 1]
    }

    public static func aspectFit(sourceWidth: Double, sourceHeight: Double, in rect: Rectangle) -> Rectangle {
        guard sourceWidth > 0, sourceHeight > 0, rect.width > 0, rect.height > 0 else {
            return Rectangle(x: rect.x, y: rect.y, width: 0, height: 0)
        }
        let scale = min(rect.width / sourceWidth, rect.height / sourceHeight)
        let width = sourceWidth * scale, height = sourceHeight * scale
        return Rectangle(x: rect.x + (rect.width - width) / 2,
                         y: rect.y + (rect.height - height) / 2, width: width, height: height)
    }

    // Video coordinates start at top left; AppKit coordinates start at bottom left.
    public static func destination(_ frame: ScreenFrame, videoRect: Rectangle) -> Rectangle {
        Rectangle(x: videoRect.x + frame.x * videoRect.width,
                  y: videoRect.y + (1 - frame.y - frame.height) * videoRect.height,
                  width: frame.width * videoRect.width, height: frame.height * videoRect.height)
    }

    // AX/CG global coordinates originate at the primary display's top left.
    // Do not flip relative to the current display: that breaks secondary displays.
    public static func accessibilityRect(appKit rect: Rectangle, primaryDisplayHeight: Double) -> Rectangle {
        Rectangle(x: rect.x, y: primaryDisplayHeight - rect.y - rect.height,
                  width: rect.width, height: rect.height)
    }
}
