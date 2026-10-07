#if os(macOS)
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreImage

/// Captures only the selected client window; frames stay in memory and are never written to disk.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "community.DragonCodexBoot.capture", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var framePending = false
    var onFrame: ((CGImage) -> Void)?
    var onHeartbeat: (() -> Void)?
    var onFailure: ((String) -> Void)?

    @MainActor
    func start(windowID: CGWindowID, pixelSize: CGSize) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowUnavailable
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(2, Int(pixelSize.width))
        config.height = max(2, Int(pixelSize.height))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        stream = newStream
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await newStream.startCapture()
    }

    @MainActor
    func stop() async {
        guard let current = stream else { return }
        stream = nil
        try? await current.stopCapture()
        try? current.removeStreamOutput(self, type: .screen)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onFailure?(error.localizedDescription) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let value = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: value) else { return }
        if status == .idle {
            DispatchQueue.main.async { [weak self] in self?.onHeartbeat?() }
            return
        }
        guard status == .complete, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        guard !framePending else { lock.unlock(); return }
        framePending = true
        lock.unlock()
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else {
            lock.lock(); framePending = false; lock.unlock()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onFrame?(image)
            self.lock.lock(); self.framePending = false; self.lock.unlock()
        }
    }
}

enum CaptureError: Error { case windowUnavailable }
#endif
