// MechCommander 2 bundle launcher (Contents/MacOS/MechCommander2).
//
// Default mode: resolves/installs game data (downloading it on first run,
// with a native progress window when launched from Finder), then execs the
// engine with the data directory as cwd. Extra argv is passed to the engine.
//
// --download mode: shows an AppKit progress window while downloading a
// file (used by the default mode when detached from a terminal).
//   MechCommander2 --download --url <url> --out <file>
//   Exit codes: 0 ok, 1 error (message on stderr), 2 user cancelled.

import Cocoa
import Darwin

// MARK: - Helpers

@discardableResult
func runTool(_ launchPath: String, _ args: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = args
    task.standardInput = FileHandle.standardInput
    task.standardOutput = FileHandle.standardError
    do {
        try task.run()
    } catch {
        FileHandle.standardError.write(Data("failed to run \(launchPath): \(error)\n".utf8))
        return 127
    }
    task.waitUntilExit()
    return task.terminationStatus
}

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func toData(_ string: String) -> Data { Data(string.utf8) }

// MARK: - Launcher

final class Launcher {
    let bundleDir: URL
    let contentsDir: URL
    let macosDir: URL
    let resourcesDir: URL
    let engine: URL
    let dylib: URL

    let dataDir: URL
    let marker: URL
    let archiveName = "mc2-data.tar.gz"

    var gui = false
    var assumeYes = false
    var engineArgs: [String] = []

    init() {
        bundleDir = Bundle.main.bundleURL
        contentsDir = bundleDir.appendingPathComponent("Contents")
        macosDir = contentsDir.appendingPathComponent("MacOS")
        resourcesDir = contentsDir.appendingPathComponent("Resources")
        engine = macosDir.appendingPathComponent("mc2")
        dylib = contentsDir.appendingPathComponent("lib/libmc2res_64.dylib")

        let env = ProcessInfo.processInfo.environment
        let dataPath = env["MC2_DATA_DIR"]
            ?? (NSString(string: "~/Library/Application Support/MechCommander2/game-data")
                .expandingTildeInPath)
        dataDir = URL(fileURLWithPath: dataPath)
        marker = dataDir.appendingPathComponent(".mc2-data-ready")
    }

    func start() -> Never {
        var args = Array(CommandLine.arguments.dropFirst())
        if let i = args.firstIndex(of: "--yes") {
            assumeYes = true
            args.remove(at: i)
        }
        engineArgs = args
        gui = isatty(0) == 0

        ensureGameData()
        linkSupportFiles()

        try? FileManager.default.changeCurrentDirectoryPath(dataDir.path)
        let cArgs: [UnsafeMutablePointer<CChar>?] =
            ([engine.path] + engineArgs).map { strdup($0) } + [nil]
        execv(engine.path, cArgs)
        perror("launcher: execv(\(engine.path)) failed")
        exit(127)
    }

    private func notify(_ message: String) {
        eprint(message)
        if gui {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "MechCommander 2"
            alert.informativeText = message
            alert.runModal()
        }
    }

    private func confirmDownload(_ url: String) -> Bool {
        if assumeYes { return true }
        if gui {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "MechCommander 2"
            alert.informativeText = "Game data (~630 MB) will be downloaded from:\n\(url)"
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
        eprint("Game data (~630 MB) will be downloaded from:\n  \(url)")
        eprint("Download now? [y/N] ")
        let reply = readLine(strippingNewline: true) ?? "n"
        return reply.lowercased().hasPrefix("y")
    }

    private func dataURL() -> String? {
        if let env = ProcessInfo.processInfo.environment["MC2_DATA_URL"], !env.isEmpty {
            return env
        }
        let urlFile = resourcesDir.appendingPathComponent("data-url.txt")
        guard let text = try? String(contentsOf: urlFile, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return trimmed
        }
        return nil
    }

    private func ensureGameData() {
        let fm = FileManager.default
        if fm.fileExists(atPath: marker.path) { return }

        guard let url = dataURL() else {
            notify("Game data is not installed and no download URL is configured. Host the data archive yourself, then set its URL in Contents/Resources/data-url.txt inside MechCommander2.app, or launch with MC2_DATA_URL=<url>.")
            exit(1)
        }
        guard confirmDownload(url) else {
            notify("Aborted.")
            exit(1)
        }

        let partial = dataDir.appendingPathComponent(".mc2-data.partial")
        let tmp = dataDir.appendingPathComponent(".mc2-data-tmp")
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        runTool("/bin/rm", ["-f", partial.path])
        runTool("/bin/rm", ["-rf", tmp.path])

        eprint("Downloading game data...")
        let dl: Int32
        if gui, let me = Bundle.main.executablePath {
            dl = runTool(me, ["--download", "--url", url, "--out", partial.path])
        } else {
            dl = runTool("/usr/bin/curl", ["-fL", "--progress-bar", "-o", partial.path, url])
        }
        if dl != 0 {
            runTool("/bin/rm", ["-f", partial.path])
            notify(dl == 2 ? "Download cancelled." : "ERROR: download failed.")
            exit(1)
        }

        eprint("Extracting game data...")
        let ok = extract(url: url, archive: partial, tmp: tmp)
        runTool("/bin/rm", ["-f", partial.path])
        runTool("/bin/rm", ["-rf", tmp.path])
        if !ok {
            runTool("/bin/rm", ["-rf", dataDir.path])
            notify("ERROR: extraction failed; the download was removed.")
            exit(1)
        }
        fm.createFile(atPath: marker.path, contents: Data())
        eprint("Game data installed.")
    }

    private func extract(url: String, archive: URL, tmp: URL) -> Bool {
        if url.hasSuffix(".zip") {
            // GitHub release archives (e.g. alariq/mc2) are zips with a
            // single top directory plus Windows binaries we must not take.
            let rc = runTool("/usr/bin/unzip", ["-qq", archive.path,
                                                "-x", "*.exe", "*.dll", "*.pdb",
                                                "*/shaders/*", "*/testtxm.tga",
                                                "*/options.cfg", "*/options.cfg.old",
                                                "-d", tmp.path])
            guard rc == 0 else { return false }
            let fm = FileManager.default
            let top = (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.isDirectoryKey]))?
                .first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            let src = top ?? tmp
            return runTool("/usr/bin/rsync", ["-a", src.path + "/", dataDir.path + "/"]) == 0
        }
        return runTool("/usr/bin/tar", ["-xzf", archive.path, "-C", dataDir.path]) == 0
    }

    private func linkSupportFiles() {
        let fm = FileManager.default
        runTool("/bin/rm", ["-rf", dataDir.appendingPathComponent("shaders").path])
        runTool("/bin/rm", ["-f", dataDir.appendingPathComponent("libmc2res_64.so").path])
        do {
            try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: dataDir.appendingPathComponent("shaders"),
                                      withDestinationURL: resourcesDir.appendingPathComponent("shaders"))
            try fm.createSymbolicLink(at: dataDir.appendingPathComponent("libmc2res_64.so"),
                                      withDestinationURL: dylib)
        } catch {
            notify("ERROR: cannot link game support files: \(error.localizedDescription)")
            exit(1)
        }
    }
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
            FileHandle.standardError.write(toData("cancelled\n"))
            exit(2)
        }
        fail(error.localizedDescription)
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        FileHandle.standardError.write(toData("download failed: \(message)\n"))
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
        FileHandle.standardError.write(toData("usage: MechCommander2 --download --url <url> --out <file>\n"))
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

// MARK: - Entry point

let arguments = CommandLine.arguments
if let idx = arguments.firstIndex(of: "--download") {
    runDownload(args: Array(arguments[(idx + 1)...]))
}
Launcher().start()
