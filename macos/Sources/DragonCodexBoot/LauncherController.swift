#if os(macOS)
import AppKit
import AVFoundation
import ApplicationServices
import LauncherCore

@MainActor
final class LauncherController: NSObject, NSApplicationDelegate {
    private let config: Configuration
    private let videoURL: URL
    private let client: TargetClient
    private let logger = EventLog()
    private var state: PlaybackState
    private var window: AnimationWindow?
    private var backdrop: AnimationWindow?
    private var view: LauncherView?
    private var player: AVPlayer?
    private var timer: Timer?
    private var itemObservation: NSKeyValueObservation?
    private var endedObservation: NSObjectProtocol?
    private var preparation: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var capture: WindowCapture?
    private let startTime = ProcessInfo.processInfo.systemUptime
    private var lastProbe = -Double.infinity
    private var stableID: CGWindowID?
    private var stableSince = 0.0
    private var windowReady = false
    private var target: TargetWindow?
    private var alignedID: CGWindowID?
    private var captureID: CGWindowID?
    private var captureStarted = 0.0
    private var lastFrameTime = 0.0
    private var hasFrame = false
    private var captureFallback = false
    private var mediaLoaded = false
    private var mediaEnded = false
    private var mediaFailed = false
    private var seeking = false
    private var wantsPlay = false
    private var closing = false
    private var mediaDuration = 0.0
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    init(configuration: Configuration, videoURL: URL) {
        self.config = configuration; self.videoURL = videoURL
        client = TargetClient(configuration: configuration)
        state = PlaybackState(config: configuration)
        super.init()
        client.log = { [weak self] in self?.logger.write($0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let screenAllowed = CGPreflightScreenCaptureAccess(), axAllowed = AXIsProcessTrusted()
        captureFallback = !screenAllowed || !axAllowed
        logger.write("launcher-started; ax=\(axAllowed); screenCapture=\(screenAllowed)")
        if captureFallback { logger.write("plain-fade-mode: Screen Recording or Accessibility permission absent") }
        showWindow()
        client.launchOrAttach()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        preparation = Task { [weak self] in await self?.prepareMedia() }
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit Dragon Codex Boot", action: #selector(skip), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    private func showWindow() {
        let mouse = NSEvent.mouseLocation
        // Cover the existing client's display before launching/restoring it. The
        // old fixed-size window exposed larger clients until the late AX resize.
        let existing = client.probe()
        let clientRect = existing.map { target -> CGRect in
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            return CGRect(x: target.bounds.minX, y: primaryHeight - target.bounds.maxY,
                          width: target.bounds.width, height: target.bounds.height)
        }
        let clientScreen = clientRect.flatMap { rect in
            NSScreen.screens.filter { $0.frame.intersects(rect) }.max {
                let a = $0.frame.intersection(rect), b = $1.frame.intersection(rect)
                return a.width * a.height < b.width * b.height
            }
        }
        let screen = clientScreen ?? NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let curtain = AnimationWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        curtain.title = "Dragon Codex Boot Background"
        curtain.isReleasedWhenClosed = false
        curtain.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.16, alpha: 1)
        curtain.isOpaque = true
        curtain.level = .floating
        curtain.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        curtain.onSkip = { [weak self] in self?.skip() }
        curtain.orderFrontRegardless()
        backdrop = curtain
        let host = AnimationWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        host.title = "Dragon Codex Boot"
        host.isReleasedWhenClosed = false
        host.backgroundColor = .black
        host.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        host.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let content = LauncherView(frame: CGRect(origin: .zero, size: frame.size))
        content.onSkip = { [weak self] in self?.skip() }
        host.contentView = content
        host.onSkip = { [weak self] in self?.skip() }
        window = host; view = content
        host.makeKeyAndOrderFront(nil)
        logger.write("display-covered; animation=\(Int(frame.width))x\(Int(frame.height)); backdrop=\(Int(screen.frame.width))x\(Int(screen.frame.height))")
        NSApp.activate(ignoringOtherApps: true)
        // Local monitor also handles Esc while a subview owns the first responder.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.skip() }
                return nil
            }
            return event
        }
        if AXIsProcessTrusted() {
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { MainActor.assumeIsolated { self?.skip() } }
            }
        }
    }

    private func prepareMedia() async {
        do {
            let asset = AVURLAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            try config.validateMedia(duration: duration.seconds, hasVideo: !tracks.isEmpty)
            guard let track = tracks.first else { throw ValidationError.invalid("Video track missing") }
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            guard !closing, !Task.isCancelled else { return }
            let transformed = CGRect(origin: .zero, size: size).applying(transform)
            view?.aspectRatio = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            mediaDuration = duration.seconds
            let item = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.volume = Float(config.volume)
            avPlayer.actionAtItemEnd = .pause
            player = avPlayer
            view?.videoLayer.player = avPlayer
            itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                DispatchQueue.main.async {
                    guard let self = self, !self.closing else { return }
                    switch status {
                    case .readyToPlay:
                        if !self.mediaLoaded {
                            self.mediaLoaded = true; self.wantsPlay = true
                            self.player?.play(); self.logger.write("video-playing")
                        }
                    case .failed:
                        self.mediaFailed = true; self.logger.write("video-player-failed")
                    default: break
                    }
                }
            }
            endedObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                object: item, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.mediaEnded = true }
                }
        } catch {
            guard !closing else { return }
            logger.write("video-load-failed: \(error)")
            mediaFailed = true
        }
    }

    private func tick() {
        guard !closing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - startTime
        let rawTime = player?.currentTime().seconds ?? 0
        let time = seeking ? config.holdAt : (rawTime.isFinite ? max(0, rawTime) : 0)
        if now - lastProbe >= 0.25 {
            lastProbe = now
            target = client.probe()
            if let found = target {
                if stableID != found.id { stableID = found.id; stableSince = now; windowReady = false }
                else { windowReady = now - stableSince >= config.stableWindowSeconds }
            } else {
                stableID = nil; windowReady = false
                if state.transitioning { usePlainFade("client-window-disappeared") }
            }
        }
        if windowReady, let found = target, time >= config.holdAt - 0.5 {
            if alignedID != found.id, let host = window {
                alignedID = found.id
                client.align(to: host.frame)
            }
            if !captureFallback && captureID != found.id { startCapture(found, now: now) }
        }
        if capture != nil && !hasFrame && now - captureStarted >= config.captureStartTimeout {
            usePlainFade("capture-first-frame-timeout")
        }
        if hasFrame && now - lastFrameTime > 2 { usePlainFade("capture-stream-stalled") }
        let ready = windowReady && (captureFallback || hasFrame)
        let command = state.tick(elapsed: elapsed, mediaTime: time, mediaLoaded: mediaLoaded,
            ready: ready, ended: !seeking && (mediaEnded || (mediaLoaded && mediaDuration > 0 && time >= mediaDuration - 0.02)),
            failed: mediaFailed)
        switch command {
        case .hold:
            wantsPlay = false; player?.pause(); seeking = true
            player?.seek(to: CMTime(seconds: config.holdAt, preferredTimescale: 600),
                         toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                DispatchQueue.main.async {
                    guard let self = self, !self.closing else { return }
                    self.seeking = false; self.mediaEnded = false
                    if !completed { self.mediaFailed = true; self.logger.write("hold-seek-failed"); return }
                    if self.wantsPlay { self.player?.play() }
                }
            }
            view?.status.stringValue = "Codex 正在启动…  Esc 跳过"
            view?.status.isHidden = false
            logger.write("waiting-at-configured-node")
        case .resume:
            mediaEnded = false
            wantsPlay = true
            if !seeking { player?.play() }
            view?.status.isHidden = true
            logger.write("client-window-ready: stable-window heuristic")
        case .finish(let reason): finish(reason); return
        case .none: break
        }
        if state.transitioning {
            let alpha = Geometry.ease((time - config.transitionStart) / (config.transitionEnd - config.transitionStart))
            if captureFallback {
                window?.alphaValue = 1 - alpha
                backdrop?.alphaValue = 1 - alpha
            }
            else { view?.update(frame: Geometry.interpolate(config.screenFrames, at: time), opacity: alpha) }
        }
    }

    private func startCapture(_ target: TargetWindow, now: Double) {
        releaseCapture()
        let source = WindowCapture()
        capture = source; captureID = target.id; captureStarted = now; hasFrame = false
        source.onFrame = { [weak self, weak source] image in
            guard let self = self, let source = source, self.capture === source, !self.closing else { return }
            if !self.hasFrame { self.logger.write("first-real-window-frame") }
            self.hasFrame = true; self.lastFrameTime = ProcessInfo.processInfo.systemUptime
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.view?.capturedLayer.contents = image
            CATransaction.commit()
        }
        source.onHeartbeat = { [weak self, weak source] in
            guard let self = self, let source = source, self.capture === source, !self.closing, self.hasFrame else { return }
            self.lastFrameTime = ProcessInfo.processInfo.systemUptime
        }
        source.onFailure = { [weak self, weak source] message in
            guard let self = self, let source = source, self.capture === source, !self.closing else { return }
            self.usePlainFade("capture-failed: \(message)")
        }
        let scale = window?.screen?.backingScaleFactor ?? 2
        let size = window?.frame.size ?? CGSize(width: config.playerWidth, height: config.playerHeight)
        let factor = min(scale, 2560 / max(1, size.width), 1440 / max(1, size.height))
        captureTask = Task { [weak self] in
            do {
                try await source.start(windowID: target.id, pixelSize: CGSize(width: size.width * factor, height: size.height * factor))
                guard let self = self, self.capture === source, !self.closing, !Task.isCancelled else {
                    await source.stop(); return
                }
            } catch {
                if let self = self, self.capture === source, !self.closing { self.usePlainFade("capture-start-failed: \(error)") }
                await source.stop()
            }
        }
    }

    private func usePlainFade(_ reason: String) {
        guard !captureFallback else { return }
        captureFallback = true
        logger.write("plain-fade-mode: \(reason)")
        releaseCapture()
        view?.capturedLayer.opacity = 0
    }

    private func releaseCapture() {
        captureTask?.cancel(); captureTask = nil
        let previous = capture
        capture = nil; captureID = nil; hasFrame = false
        previous?.onFrame = nil; previous?.onHeartbeat = nil; previous?.onFailure = nil
        if let previous = previous { Task { await previous.stop() } }
    }

    @objc private func skip() { finish(.skipped) }

    private func finish(_ reason: FinishReason) {
        guard !closing else { return }
        closing = true
        logger.write("handoff: \(reason.rawValue)")
        timer?.invalidate(); timer = nil
        preparation?.cancel(); preparation = nil
        player?.pause(); itemObservation = nil
        if let observer = endedObservation { NotificationCenter.default.removeObserver(observer) }
        endedObservation = nil
        if let monitor = escapeMonitor { NSEvent.removeMonitor(monitor) }
        escapeMonitor = nil
        if let monitor = globalEscapeMonitor { NSEvent.removeMonitor(monitor) }
        globalEscapeMonitor = nil
        releaseCapture()
        // A bounded fade also handles early skip, timeout, and media failures.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reason == .skipped ? 0.08 : 0.2
            window?.animator().alphaValue = 0
            backdrop?.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [self] in
            window?.orderOut(nil); window?.close()
            backdrop?.orderOut(nil); backdrop?.close(); backdrop = nil
            view?.capturedLayer.contents = nil
            view?.videoLayer.player = nil; player = nil
            client.handOff()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        skip(); return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !closing { skip(); return .terminateCancel }
        return .terminateNow
    }
}

final class EventLog {
    private let url: URL?
    init() {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/DragonCodexBoot", isDirectory: true)
        if let directory = directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        url = directory?.appendingPathComponent("launcher.log")
    }
    func write(_ event: String) {
        guard let url = url else { return }
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue > 512_000 {
            let previous = url.appendingPathExtension("previous")
            try? manager.removeItem(at: previous); try? manager.moveItem(at: url, to: previous)
        }
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let line = ISO8601DateFormatter().string(from: Date()) + " " + event.replacingOccurrences(of: "\n", with: " ") + "\n"
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
#endif
