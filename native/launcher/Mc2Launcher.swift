// MechCommander 2 bundle launcher (Contents/MacOS/MechCommander2).
//
// Default mode: a Mach-O main executable that execs the real bash launcher
// in ../Resources/MechCommander2.sh (notarization requires a Mach-O main
// executable, not a script).
//
// --download mode: shows an AppKit progress window while downloading a
// file.   Usage: MechCommander2 --download --url <url> --out <file>
//   Exit codes: 0 ok, 1 error (message on stderr), 2 user cancelled.

import Cocoa
import Darwin

// MARK: - Launcher stub

func execShellLauncher() -> Never {
    var buf = [CChar](repeating: 0, count: 4096)
    var size = UInt32(buf.count)
    guard _NSGetExecutablePath(&buf, &size) == 0 else {
        FileHandle.standardError.write(Data("launcher: cannot resolve own path\n".utf8))
        exit(127)
    }
    let exePath = String(cString: buf)
    let dir = (exePath as NSString).deletingLastPathComponent
    let script = ((dir as NSString).appendingPathComponent("../Resources/MechCommander2.sh")
                  as NSString).standardizingPath

    let cArgs: [UnsafeMutablePointer<CChar>?] =
        ([script] + Array(CommandLine.arguments.dropFirst())).map { strdup($0) } + [nil]
    execv(script, cArgs)
    perror("launcher: execv(\(script)) failed")
    exit(127)
}

// MARK: - Download window

final class Downloader: NSObject, NSApplicationDelegate, URLSessionDelegate,
                        URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let url: URL
    private let out: URL
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
                                  styleMask: [.titled], backing: .buffered, defer: false)
    private let bar = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "Connecting…")
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var totalBytes: Int64 = -1
    private var receivedBytes: Int64 = 0
    private var lastBytes: Int64 = 0
    private var lastTime = Date()
    private var finished = false

    init(url: URL, out: URL) {
        self.url = url
        self.out = out
        super.init()
        label.frame = NSRect(x: 20, y: 72, width: 440, height: 20)
        bar.frame = NSRect(x: 20, y: 44, width: 440, height: 16)
        bar.style = .bar
        bar.isIndeterminate = true
        bar.minValue = 0
        bar.maxValue = 1
        cancel.frame = NSRect(x: 388, y: 8, width: 72, height: 28)
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        cancel.action = #selector(cancelDownload)
        let content = window.contentView!
        content.addSubview(label)
        content.addSubview(bar)
        content.addSubview(cancel)
        window.title = "MechCommander 2 — Game Data"
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session.downloadTask(with: url)
        task?.resume()
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    @objc private func cancelDownload() {
        task?.cancel()
    }

    private func tick() {
        guard !finished else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        var speedText = ""
        if elapsed > 0.3 {
            let mbps = Double(receivedBytes - lastBytes) / elapsed / 1_000_000.0
            speedText = String(format: "  (%.1f MB/s)", mbps)
            lastBytes = receivedBytes
            lastTime = now
        }
        let mb = Double(receivedBytes) / 1_000_000.0
        if totalBytes > 0 {
            let pct = Int(Double(receivedBytes) / Double(totalBytes) * 100)
            label.stringValue = String(format: "%.0f%% — %.1f MB / %.1f MB%@",
                                       Double(pct), mb, Double(totalBytes) / 1_000_000.0, speedText)
            bar.isIndeterminate = false
            bar.doubleValue = Double(receivedBytes) / Double(totalBytes)
        } else {
            bar.isIndeterminate = true
            label.stringValue = String(format: "%.1f MB downloaded%@", mb, speedText)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        receivedBytes = totalBytesWritten
        totalBytes = totalBytesExpectedToWrite
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard !finished else { return }
        do {
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.copyItem(at: location, to: out)
            finish(0)
        } catch {
            fail("could not write \(out.path): \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error = error else { return }
        if (error as NSError).code == NSURLErrorCancelled {
            if finished { return }
            FileHandle.standardError.write(Data("cancelled\n".utf8))
            exit(2)
        }
        fail(error.localizedDescription)
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        FileHandle.standardError.write(Data("download failed: \(message)\n".utf8))
        DispatchQueue.main.async { exit(1) }
    }

    private func finish(_ code: Int32) {
        guard !finished else { return }
        finished = true
        label.stringValue = "Download complete"
        bar.isIndeterminate = false
        bar.doubleValue = 1
        cancel.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(code) }
    }
}

func runDownload(args: [String]) -> Never {
    guard let u = args.firstIndex(of: "--url"), u + 1 < args.count,
          let o = args.firstIndex(of: "--out"), o + 1 < args.count,
          let url = URL(string: args[u + 1]) else {
        FileHandle.standardError.write(Data("usage: MechCommander2 --download --url <url> --out <file>\n".utf8))
        exit(64)
    }
    let out = URL(fileURLWithPath: args[o + 1])
    try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    let app = NSApplication.shared
    let delegate = Downloader(url: url, out: out)
    app.delegate = delegate
    app.run()
    exit(0)
}

let arguments = CommandLine.arguments
if arguments.contains("--download") {
    runDownload(args: Array(arguments.dropFirst(arguments.firstIndex(of: "--download")! + 1)))
}
execShellLauncher()
