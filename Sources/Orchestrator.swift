// Orchestrator.swift — detects and drives the full stack: Apple `container`
// runtime, the Frigate image, Ollama (local AI), and our ANE detector.
import Foundation

struct Shell {
    @discardableResult
    static func run(_ cmd: String, timeout: TimeInterval = 30) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "spawn failed: \(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Find a CLI on PATH or common Homebrew locations.
    static func which(_ tool: String) -> String? {
        let r = run("command -v \(tool) || true", timeout: 5)
        let path = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { return path }
        for p in ["/usr/local/bin/\(tool)", "/opt/homebrew/bin/\(tool)"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}

struct StackStatus {
    var containerCLI = false
    var containerSystemUp = false
    var imagePresent = false
    var frigateRunning = false
    var ollamaInstalled = false
    var ollamaModelPresent = false
    var detectorRunning = false
    var notes: [String] = []
}

final class Orchestrator {
    let store = ConfigStore.shared
    var onProgress: ((String) -> Void)?

    private func log(_ s: String) { DispatchQueue.main.async { self.onProgress?(s + "\n") } }

    // MARK: detection

    func detect(_ done: @escaping (StackStatus) -> Void) {
        DispatchQueue.global().async {
            var st = StackStatus()
            st.containerCLI = Shell.which("container") != nil
            if st.containerCLI {
                let sys = Shell.run("container list >/dev/null 2>&1 && echo up || echo down", timeout: 10)
                st.containerSystemUp = sys.out.contains("up")
                let img = Shell.run("container image list 2>/dev/null | grep -q frigate && echo yes || echo no", timeout: 10)
                st.imagePresent = img.out.contains("yes")
                let run = Shell.run("container list 2>/dev/null | grep -q 'frigate.*running' && echo yes || echo no", timeout: 10)
                st.frigateRunning = run.out.contains("yes")
            } else {
                st.notes.append("Apple `container` CLI not found. Install from https://github.com/apple/container (requires macOS 26).")
            }
            if let _ = Shell.which("ollama") {
                st.ollamaInstalled = true
                let model = self.store.config.localAI.model
                let m = Shell.run("ollama list 2>/dev/null | grep -q '\(model)' && echo yes || echo no", timeout: 10)
                st.ollamaModelPresent = m.out.contains("yes")
            } else if self.store.config.localAI.enabled {
                st.notes.append("Ollama not installed — needed for local AI scene descriptions (https://ollama.com).")
            }
            st.detectorRunning = Shell.run("lsof -nP -iTCP:5555 2>/dev/null | grep -q LISTEN && echo yes || echo no", timeout: 8).out.contains("yes")
            DispatchQueue.main.async { done(st) }
        }
    }

    // MARK: actions

    /// Bring the whole stack up: write config, ensure container system, pull image, start Frigate.
    func startAll(_ done: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            do { try ConfigGenerator.writeAll(self.store) }
            catch { self.log("Failed to write config: \(error)"); DispatchQueue.main.async { done(false) }; return }
            self.log("Wrote Frigate config + start script.")

            // model_cache: link the detector's model into the frigate config dir
            self.linkModelCache()

            guard Shell.which("container") != nil else {
                self.log("Apple `container` CLI missing — cannot start Frigate. See setup notes.")
                DispatchQueue.main.async { done(false) }; return
            }
            self.log("Ensuring container system is running…")
            _ = Shell.run("container system start 2>&1", timeout: 30)

            if !Shell.run("container image list 2>/dev/null | grep -q frigate && echo y || echo n", timeout: 10).out.contains("y") {
                self.log("Pulling Frigate image (first run, this can take a while)…")
                let pull = Shell.run("container image pull \(self.store.config.frigateImage) 2>&1", timeout: 600)
                self.log(pull.out.suffix(400).description)
            }

            self.log("Starting Frigate…")
            let r = Shell.run("bash '\(self.store.startScriptURL.path)' 2>&1", timeout: 120)
            self.log(r.out)
            let ok = r.code == 0
            DispatchQueue.main.async { done(ok) }
        }
    }

    func stopFrigate(_ done: @escaping () -> Void) {
        DispatchQueue.global().async {
            _ = Shell.run("container stop frigate 2>/dev/null; true", timeout: 30)
            self.log("Frigate stopped.")
            DispatchQueue.main.async { done() }
        }
    }

    func installOllamaModel(_ done: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            guard Shell.which("ollama") != nil else {
                self.log("Ollama not installed."); DispatchQueue.main.async { done(false) }; return
            }
            let model = self.store.config.localAI.model
            self.log("Pulling Ollama model \(model)…")
            let r = Shell.run("ollama pull \(model) 2>&1", timeout: 900)
            self.log(r.out.suffix(300).description)
            DispatchQueue.main.async { done(r.code == 0) }
        }
    }

    /// Symlink engine/models into the frigate config's model_cache so the
    /// container `model.path` resolves to the same YOLO file the ANE uses.
    private func linkModelCache() {
        let res = Bundle.main.resourceURL!.appendingPathComponent("engine/models")
        let dest = store.frigateConfigDir.appendingPathComponent("model_cache")
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path) {
            try? fm.createSymbolicLink(at: dest, withDestinationURL: res)
        }
    }
}
