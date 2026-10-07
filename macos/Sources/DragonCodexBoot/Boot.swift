import Foundation
import LauncherCore
#if os(macOS)
import AppKit
import AVFoundation
import ApplicationServices

@main
struct Boot {
    @MainActor
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let modes = ["--validate-config", "--diagnose", "--request-permissions", "--smoke-test"]
            if arguments.contains("--help") {
                print("DragonCodexBoot [--config /absolute/config.json] [--validate-config | --diagnose | --request-permissions | --smoke-test]")
                return
            }
            let modeArguments = arguments.filter { modes.contains($0) }
            guard modeArguments.count <= 1 else { throw ValidationError.invalid("Select one command mode") }
            var customConfig: URL?
            var index = 0
            while index < arguments.count {
                if arguments[index] == "--config" {
                    guard index + 1 < arguments.count, arguments[index + 1].hasPrefix("/"), customConfig == nil else {
                        throw ValidationError.invalid("--config requires one absolute JSON path")
                    }
                    customConfig = URL(fileURLWithPath: arguments[index + 1]); index += 2
                } else if modes.contains(arguments[index]) { index += 1 }
                else { throw ValidationError.invalid("Unknown argument: \(arguments[index])") }
            }
            guard let resources = Bundle.main.resourceURL else { throw ValidationError.invalid("Run the packaged .app") }
            let userConfig = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("DragonCodexBoot/launcher.json")
            let configURL = customConfig ?? userConfig.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? resources.appendingPathComponent("launcher.example.json")
            let configuration = try Configuration.load(from: configURL)
            guard configuration.bundleIdentifier != Bundle.main.bundleIdentifier else {
                throw ValidationError.invalid("Target cannot be the launcher itself")
            }
            let videoURL = configuration.video.hasPrefix("/") ? URL(fileURLWithPath: configuration.video)
                : resources.appendingPathComponent(configuration.video)
            if arguments.contains("--validate-config") {
                try emit(["configuration": "valid", "path": configURL.path]); return
            }
            if arguments.contains("--diagnose") {
                let client = TargetClient(configuration: configuration)
                try emit([
                    "os": ProcessInfo.processInfo.operatingSystemVersionString,
                    "architecture": architecture,
                    "configuration": configURL.path,
                    "targetBundleIdentifier": configuration.bundleIdentifier,
                    "targetApplication": client.applicationURL()?.path ?? "not found",
                    "targetRunning": client.application != nil,
                    "accessibility": AXIsProcessTrusted(),
                    "screenRecording": CGPreflightScreenCaptureAccess(),
                    "videoExists": FileManager.default.fileExists(atPath: videoURL.path)
                ]); return
            }
            if arguments.contains("--request-permissions") {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                let accessible = AXIsProcessTrustedWithOptions(options)
                let recordable = CGRequestScreenCaptureAccess()
                try emit(["accessibility": accessible, "screenRecording": recordable,
                          "nextStep": "Enable this .app in System Settings > Privacy & Security; quit and relaunch."])
                return
            }
            if arguments.contains("--smoke-test") {
                NSApplication.shared.setActivationPolicy(.prohibited)
                Task { @MainActor in
                    do {
                        let asset = AVURLAsset(url: videoURL)
                        let duration = try await asset.load(.duration)
                        let tracks = try await asset.loadTracks(withMediaType: .video)
                        try configuration.validateMedia(duration: duration.seconds, hasVideo: !tracks.isEmpty)
                        guard try await asset.load(.isPlayable) else { throw ValidationError.invalid("AVFoundation cannot play video") }
                        // Run a real AVPlayerItem preparation; AVAsset metadata alone is insufficient.
                        let item = AVPlayerItem(asset: asset)
                        let player = AVPlayer(playerItem: item)
                        player.isMuted = true
                        player.play()
                        let deadline = ProcessInfo.processInfo.systemUptime + configuration.mediaLoadTimeout
                        while item.status != .readyToPlay || player.currentTime().seconds < 0.1 {
                            if item.status == .failed || ProcessInfo.processInfo.systemUptime >= deadline {
                                throw ValidationError.invalid("AVPlayer readiness/playback failed or timed out")
                            }
                            try await Task.sleep(nanoseconds: 50_000_000)
                        }
                        player.pause()
                        try emit(["smokeTest": "passed", "duration": duration.seconds,
                                  "videoTracks": tracks.count, "playbackTime": player.currentTime().seconds,
                                  "scope": "bundled AVFoundation media playback; no Codex, AX, or screen capture"])
                        exit(0)
                    } catch { fail(error) }
                }
                NSApplication.shared.run()
                return
            }
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = LauncherController(configuration: configuration, videoURL: videoURL)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch { fail(error) }
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data("DragonCodexBoot: \(error)\n".utf8))
        exit(1)
    }
}
#else
@main
struct Boot {
    static func main() {
        FileHandle.standardError.write(Data("DragonCodexBoot requires macOS 13+; LauncherCore tests can run on Linux.\n".utf8))
        exit(1)
    }
}
#endif
