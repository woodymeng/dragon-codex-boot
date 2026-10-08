#if os(macOS)
import AppKit
import AVFoundation
import LauncherCore

final class LauncherView: NSView {
    let videoLayer = AVPlayerLayer()
    let capturedLayer = CALayer()
    let status = NSTextField(labelWithString: "")
    let skipButton = NSButton(title: "跳过 · Esc", target: nil, action: nil)
    var onSkip: (() -> Void)?
    var aspectRatio = CGSize(width: 16, height: 9)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
        capturedLayer.contentsGravity = .resizeAspect
        capturedLayer.masksToBounds = true
        capturedLayer.backgroundColor = NSColor.black.cgColor
        capturedLayer.opacity = 0
        layer?.addSublayer(capturedLayer)
        status.textColor = .white
        status.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        status.drawsBackground = true
        status.alignment = .center
        status.font = .systemFont(ofSize: 14)
        status.isHidden = true
        addSubview(status)
        skipButton.bezelStyle = .rounded
        skipButton.font = .systemFont(ofSize: 13, weight: .semibold)
        skipButton.target = self
        skipButton.action = #selector(skipAnimation)
        skipButton.setAccessibilityLabel("跳过启动动画，快捷键 Escape")
        addSubview(skipButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func skipAnimation() { onSkip?() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
        status.frame = CGRect(x: 20, y: 20, width: max(0, bounds.width - 40), height: 30)
        skipButton.frame = CGRect(x: max(16, bounds.width - 148), y: max(16, bounds.height - 54), width: 128, height: 34)
    }

    var videoRect: Rectangle {
        Geometry.aspectFit(sourceWidth: Double(aspectRatio.width), sourceHeight: Double(aspectRatio.height),
                           in: Rectangle(x: Double(bounds.minX), y: Double(bounds.minY),
                                         width: Double(bounds.width), height: Double(bounds.height)))
    }

    func update(frame: ScreenFrame, opacity: Double) {
        // Start in the video's keyframe rectangle, then expand into the native
        // window aspect ratio so letterboxing does not squash the live client.
        let rect = Geometry.transitionDestination(frame, videoRect: videoRect,
            windowRect: Rectangle(x: Double(bounds.minX), y: Double(bounds.minY),
                                  width: Double(bounds.width), height: Double(bounds.height)), progress: opacity)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        capturedLayer.frame = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        capturedLayer.opacity = Float(opacity)
        CATransaction.commit()
    }
}

final class AnimationWindow: NSWindow {
    var onSkip: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSkip?() } else { super.keyDown(with: event) }
    }
}
#endif
