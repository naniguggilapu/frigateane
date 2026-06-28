// Orchestrator.swift — detects and drives the full stack: Apple `container`
// runtime, container NAT networking, the Frigate image, Ollama (local AI),
// and our ANE detector.
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

    static func which(_ tool: String) -> String? {
        let r = run("command -v \(tool) || true", timeout: 5)
        let path = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { return path }
        for p in ["/usr/local/bin/\(tool)", "/opt/homebrew/bin/\(tool)"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Run a privileged shell command via one Authorization prompt.
    @discardableResult
    static func runAdmin(_ script: String) -> (code: Int32, out: String) {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", osa]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "spawn failed: \(error)") }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

struct StackStatus {
    var macOSMajor = 0
    var macOSCompatible = false        // Apple `container` needs macOS 26+
    var containerCLI = false
    var containerVersion: String? = nil
    var containerSystemUp = false
    var natConfigured = false
    var imagePresent = false
    var frigateRunning = false
    var frigateHealthy = false
    var ollamaInstalled = false
    var ollamaModelPresent = false
    var detectorRunning = false
    var notes: [String] = []
}

final class Orchestrator {
    let store = ConfigStore.shared
    var onProgress: ((String) -> Void)?

    private let natPlistPath = "/Library/LaunchDaemons/com.frigateane.nat.plist"
    private let natConfPath  = "/etc/pf.anchors/frigateane-nat.conf"

    private func log(_ s: String) { DispatchQueue.main.async { self.onProgress?(s + "\n") } }

    private var networkingDir: URL { Bundle.main.resourceURL!.appendingPathComponent("networking") }

    // MARK: detection

    func detect(_ done: @escaping (StackStatus) -> Void) {
        DispatchQueue.global().async {
            var st = StackStatus()
            st.macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            st.macOSCompatible = st.macOSMajor >= 26
            st.containerCLI = Shell.which("container") != nil
            if st.containerCLI {
                let v = Shell.run("container --version 2>/dev/null", timeout: 6).out
                if let m = v.range(of: #"[0-9]+\.[0-9]+\.[0-9]+"#, options: .regularExpression) {
                    st.containerVersion = String(v[m])
                }
            }
            if !st.macOSCompatible {
                st.notes.append("Running Frigate needs macOS 26+ (Apple `container`). The ANE detector still works on this macOS.")
            } else if !st.containerCLI {
                st.notes.append("Apple `container` not installed — use “Install Container Runtime” to set it up.")
            }
            if st.containerCLI {
                st.containerSystemUp = Shell.run("container list >/dev/null 2>&1 && echo up || echo down", timeout: 10).out.contains("up")
                st.imagePresent = Shell.run("container image list 2>/dev/null | grep -q frigate && echo yes || echo no", timeout: 10).out.contains("yes")
                st.frigateRunning = Shell.run("container list 2>/dev/null | grep -q 'frigate.*running' && echo yes || echo no", timeout: 10).out.contains("yes")
            }
            st.natConfigured = FileManager.default.fileExists(atPath: self.natPlistPath)
            if st.containerCLI && !st.natConfigured {
                st.notes.append("Container NAT networking not installed — the container may not reach LAN cameras/MQTT. Use “Install Networking”.")
            }
            if st.frigateRunning {
                st.frigateHealthy = Shell.run("curl -s -o /dev/null -w '%{http_code}' --max-time 4 http://localhost:8971 | grep -qE '200|401|302' && echo ok || echo no", timeout: 8).out.contains("ok")
            }
            if Shell.which("ollama") != nil {
                st.ollamaInstalled = true
                let model = self.store.config.localAI.model
                st.ollamaModelPresent = Shell.run("ollama list 2>/dev/null | grep -q '\(model)' && echo yes || echo no", timeout: 10).out.contains("yes")
            } else if self.store.config.localAI.enabled {
                st.notes.append("Ollama not installed — needed for local AI scene descriptions (https://ollama.com).")
            }
            st.detectorRunning = Shell.run("lsof -nP -iTCP:5555 2>/dev/null | grep -q LISTEN && echo yes || echo no", timeout: 8).out.contains("yes")
            DispatchQueue.main.async { done(st) }
        }
    }

    // MARK: networking

    /// Install the container NAT LaunchDaemon + pf rules (one admin prompt).
    func installNetworking(_ done: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let conf = self.networkingDir.appendingPathComponent("frigate-nat.conf").path
            let plist = self.networkingDir.appendingPathComponent("com.frigateane.nat.plist").path
            let script = [
                "mkdir -p /etc/pf.anchors",
                "cp '\(conf)' '\(self.natConfPath)'",
                "cp '\(plist)' '\(self.natPlistPath)'",
                "chown root:wheel '\(self.natPlistPath)' '\(self.natConfPath)'",
                "chmod 644 '\(self.natPlistPath)' '\(self.natConfPath)'",
                "launchctl bootout system '\(self.natPlistPath)' 2>/dev/null || true",
                "launchctl bootstrap system '\(self.natPlistPath)' 2>/dev/null || true",
                "/sbin/pfctl -f '\(self.natConfPath)' -e 2>/dev/null || true",
                "echo installed",
            ].joined(separator: " && ")
            self.log("Installing container NAT networking (admin required)…")
            let r = Shell.runAdmin(script)
            let ok = r.out.contains("installed")
            self.log(ok ? "✓ NAT networking installed." : "✕ NAT install failed/cancelled.")
            DispatchQueue.main.async { done(ok) }
        }
    }

    // MARK: container runtime

    /// Download Apple's signed `container` installer and install it (one admin prompt).
    func installContainerRuntime(_ done: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
                self.log("Apple `container` requires macOS 26 or newer — cannot install on this macOS.")
                DispatchQueue.main.async { done(false) }; return
            }
            self.log("Resolving latest Apple container installer…")
            let pinned = "https://github.com/apple/container/releases/download/1.0.0/container-1.0.0-installer-signed.pkg"
            var url = pinned
            let api = "https://api.github.com/repos/apple/container/releases/latest"
            let found = Shell.run("curl -fsSL '\(api)' 2>/dev/null | grep -oE 'https://[^\"]*installer-signed\\.pkg' | head -1", timeout: 20).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if found.hasPrefix("https://") { url = found }
            self.log("  \(url)")

            let pkg = "/tmp/frigateane-container-installer.pkg"
            let dl = Shell.run("curl -fL '\(url)' -o '\(pkg)' && echo ok || echo fail", timeout: 600)
            guard dl.out.contains("ok") else {
                self.log("Download failed."); DispatchQueue.main.async { done(false) }; return
            }
            self.log("Installing container runtime (admin required)…")
            let r = Shell.runAdmin("installer -pkg '\(pkg)' -target / && echo installed")
            let ok = r.out.contains("installed")
            self.log(ok ? "✓ Container runtime installed." : "✕ Install failed/cancelled.")
            if ok {
                _ = Shell.run("container system start 2>&1", timeout: 30)
                self.log("Container system started.")
            }
            _ = Shell.run("rm -f '\(pkg)'", timeout: 5)
            DispatchQueue.main.async { done(ok) }
        }
    }

    // MARK: lifecycle

    func startAll(_ done: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            do { try ConfigGenerator.writeAll(self.store) }
            catch { self.log("Failed to write config: \(error)"); DispatchQueue.main.async { done(false) }; return }
            self.log("Wrote Frigate config + start script.")
            self.linkModelCache()

            // Storage guard
            if !FileManager.default.fileExists(atPath: self.store.config.storagePath) {
                self.log("✕ Storage path not available: \(self.store.config.storagePath). Fix it in Setup → Storage.")
                DispatchQueue.main.async { done(false) }; return
            }

            guard Shell.which("container") != nil else {
                self.log("Apple `container` CLI missing — cannot start Frigate. See setup notes.")
                DispatchQueue.main.async { done(false) }; return
            }

            self.log("Ensuring container system is running…")
            _ = Shell.run("container system start 2>&1", timeout: 30)

            if !FileManager.default.fileExists(atPath: self.natPlistPath) {
                self.log("Note: NAT networking not installed — container may not reach the LAN. Use “Install Networking”.")
            }

            if !Shell.run("container image list 2>/dev/null | grep -q frigate && echo y || echo n", timeout: 10).out.contains("y") {
                self.log("Pulling Frigate image (first run — can take several minutes)…")
                let pull = Shell.run("container image pull \(self.store.config.frigateImage) 2>&1", timeout: 1200)
                self.log(String(pull.out.suffix(400)))
            }

            self.log("Starting Frigate…")
            let r = Shell.run("bash '\(self.store.startScriptURL.path)' 2>&1", timeout: 120)
            self.log(r.out)

            // Health check: wait for the container to report running.
            var healthy = false
            for _ in 0..<15 {
                if Shell.run("container list 2>/dev/null | grep -q 'frigate.*running' && echo y || echo n", timeout: 8).out.contains("y") {
                    healthy = true; break
                }
                Thread.sleep(forTimeInterval: 2)
            }
            if healthy {
                let ui = Shell.run("curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8971 || true", timeout: 8).out
                self.log("✓ Frigate running. UI http://localhost:8971 (HTTP \(ui.trimmingCharacters(in: .whitespacesAndNewlines))).")
            } else {
                self.log("⚠︎ Frigate did not report running within 30s — check logs above.")
            }
            DispatchQueue.main.async { done(healthy) }
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
            let r = Shell.run("ollama pull \(model) 2>&1", timeout: 1200)
            self.log(String(r.out.suffix(300)))
            DispatchQueue.main.async { done(r.code == 0) }
        }
    }

    private func linkModelCache() {
        let res = Bundle.main.resourceURL!.appendingPathComponent("engine/models")
        let dest = store.frigateConfigDir.appendingPathComponent("model_cache")
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path) {
            try? fm.createSymbolicLink(at: dest, withDestinationURL: res)
        }
    }
}
