// Engine.swift — supervises the bundled Python ZMQ detector (YOLO on the ANE).
import Foundation

final class Engine {
    private var process: Process?
    private(set) var running = false

    var endpoint = "tcp://0.0.0.0:5555"
    var autoRestart = true

    var modelName = "—"
    var provider = "—"
    var aneActive = false
    var fps: Double = 0
    var startedAt: Date?

    var onLog: ((String) -> Void)?
    var onState: (() -> Void)?

    private var rapidFailures = 0        // consecutive immediate exits (e.g. port in use)
    private let pythonURL: URL
    private let scriptPath: String
    private let workdir: URL

    init() {
        let res = Bundle.main.resourceURL!.appendingPathComponent("engine")
        workdir = res
        pythonURL = res.appendingPathComponent("python/bin/python3")
        scriptPath = res.appendingPathComponent("detector/zmq_onnx_client.py").path
    }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: pythonURL.path)
    }

    func start() {
        guard !running, isInstalled else { return }
        let p = Process()
        p.executableURL = pythonURL
        p.arguments = [scriptPath, "--endpoint", endpoint, "--model", "AUTO"]
        p.currentDirectoryURL = workdir
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { self?.ingest(s) }
            }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // A previous process's terminationHandler can fire after a new one has
                // already been started (e.g. stop() immediately followed by start()).
                // Ignore stale callbacks so they don't clobber state for the current process.
                guard self.process === proc else { return }
                self.running = false
                self.onLog?("\n— engine exited (\(proc.terminationStatus)) —\n")
                self.onState?()
                guard self.autoRestart && proc.terminationStatus != 0 else { return }
                // Detect a crash loop: if the process dies within a few seconds it's
                // usually a startup failure (e.g. port 5555 already in use). Back off
                // after a few of those instead of restarting forever.
                let ranBriefly = (self.startedAt.map { Date().timeIntervalSince($0) < 4 }) ?? true
                self.rapidFailures = ranBriefly ? self.rapidFailures + 1 : 0
                if self.rapidFailures >= 3 {
                    self.rapidFailures = 0
                    self.provider = "not running"
                    self.onState?()
                    self.onLog?("Detector keeps exiting immediately — is \(self.endpoint) already in use? Auto-restart paused; use “Start/Stop Detector” to retry.\n")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !self.running { self.start() }
                }
            }
        }
        do { try p.run() } catch {
            onLog?("Failed to launch engine: \(error)\n"); return
        }
        process = p
        running = true
        startedAt = Date()
        aneActive = false
        provider = "loading…"
        onState?()
        onLog?("▶︎ detector started on \(endpoint)\n")
    }

    func stop() {
        let prev = autoRestart
        autoRestart = false
        process?.terminate()
        running = false
        onState?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.autoRestart = prev }
    }

    private func ingest(_ chunk: String) {
        onLog?(chunk)
        for raw in chunk.split(separator: "\n") {
            let line = String(raw)
            if line.contains("listening") { rapidFailures = 0 }   // healthy start
            if line.contains("Loaded ") {
                if let m = match(line, #"Loaded (\S+) in"#) { modelName = m }
                aneActive = line.contains("CoreML")
                provider = aneActive ? "CoreML · Neural Engine" : "CPU"
                onState?()
            }
            if line.contains("inferences in last"),
               let secs = match(line, #"last (\d+)s"#),
               let cnt = match(line, #": (\d+)"#),
               let sv = Double(secs), let cv = Double(cnt), sv > 0 {
                fps = cv / sv
                onState?()
            }
        }
    }

    private func match(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let r = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: r), m.numberOfRanges > 1,
              let g = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[g])
    }
}
