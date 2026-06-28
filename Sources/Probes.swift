// Probes.swift — connection tests (MQTT, RTSP, detector self-test) + login item.
import Foundation
import Network
import ServiceManagement

enum ProbeResult {
    case ok(String)
    case fail(String)
    var success: Bool { if case .ok = self { return true } else { return false } }
    var message: String { switch self { case .ok(let m): return m; case .fail(let m): return m } }
}

enum Probes {

    // MARK: TCP reachability

    static func tcpReachable(host: String, port: UInt16, timeout: TimeInterval = 5,
                             done: @escaping (ProbeResult) -> Void) {
        guard !host.isEmpty, let p = NWEndpoint.Port(rawValue: port) else {
            done(.fail("invalid host/port")); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        var finished = false
        func finish(_ r: ProbeResult) {
            if finished { return }; finished = true
            conn.cancel(); DispatchQueue.main.async { done(r) }
        }
        conn.stateUpdateHandler = { st in
            switch st {
            case .ready: finish(.ok("reachable"))
            case .failed(let e): finish(.fail(e.localizedDescription))
            case .waiting(let e): finish(.fail(e.localizedDescription))
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.fail("timed out")) }
    }

    // MARK: MQTT CONNECT

    static func mqtt(_ m: MQTTConfig, done: @escaping (ProbeResult) -> Void) {
        guard !m.host.isEmpty, let port = NWEndpoint.Port(rawValue: UInt16(m.port)) else {
            done(.fail("invalid host/port")); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(m.host), port: port, using: .tcp)
        var finished = false
        func finish(_ r: ProbeResult) {
            if finished { return }; finished = true
            conn.cancel(); DispatchQueue.main.async { done(r) }
        }
        conn.stateUpdateHandler = { st in
            switch st {
            case .ready:
                conn.send(content: buildConnect(m), completion: .contentProcessed { err in
                    if let e = err { finish(.fail(e.localizedDescription)); return }
                    conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, rerr in
                        if let d = data, d.count >= 4, d[0] == 0x20 {
                            let rc = d[3]
                            switch rc {
                            case 0: finish(.ok("broker accepted connection ✓"))
                            case 4: finish(.fail("bad username or password"))
                            case 5: finish(.fail("not authorized"))
                            default: finish(.fail("CONNACK code \(rc)"))
                            }
                        } else if let e = rerr {
                            finish(.fail(e.localizedDescription))
                        } else {
                            finish(.fail("no CONNACK (is this an MQTT broker?)"))
                        }
                    }
                })
            case .failed(let e): finish(.fail(e.localizedDescription))
            case .waiting(let e): finish(.fail(e.localizedDescription))
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) { finish(.fail("timed out")) }
    }

    private static func buildConnect(_ m: MQTTConfig) -> Data {
        func lp(_ s: String) -> [UInt8] {
            let b = Array(s.utf8); return [UInt8(b.count >> 8), UInt8(b.count & 0xff)] + b
        }
        var variable: [UInt8] = [0x00, 0x04] + Array("MQTT".utf8) + [0x04]   // protocol name + level 4
        var flags: UInt8 = 0x02                                              // clean session
        let hasUser = !m.user.isEmpty, hasPass = !m.password.isEmpty
        if hasUser { flags |= 0x80 }
        if hasPass { flags |= 0x40 }
        variable.append(flags)
        variable += [0x00, 0x3c]                                            // keepalive 60s
        var payload = lp("frigateane-probe")
        if hasUser { payload += lp(m.user) }
        if hasPass { payload += lp(m.password) }
        var pkt: [UInt8] = [0x10]
        pkt += encodeRemaining(variable.count + payload.count)
        pkt += variable + payload
        return Data(pkt)
    }

    private static func encodeRemaining(_ n: Int) -> [UInt8] {
        var x = n, out: [UInt8] = []
        repeat { var d = UInt8(x % 128); x /= 128; if x > 0 { d |= 0x80 }; out.append(d) } while x > 0
        return out
    }

    // MARK: RTSP reachability

    static func rtsp(_ url: String, done: @escaping (ProbeResult) -> Void) {
        guard let u = URLComponents(string: url), let host = u.host else {
            done(.fail("invalid RTSP URL")); return
        }
        tcpReachable(host: host, port: UInt16(u.port ?? 554), done: done)
    }

    // MARK: Detector self-test (runs the bundled engine)

    static func detectorSelfTest(done: @escaping (ProbeResult) -> Void) {
        DispatchQueue.global().async {
            let res = Bundle.main.resourceURL!.appendingPathComponent("engine")
            let py = res.appendingPathComponent("python/bin/python3").path
            let script = res.appendingPathComponent("detector/zmq_onnx_client.py").path
            guard FileManager.default.isExecutableFile(atPath: py) else {
                DispatchQueue.main.async { done(.fail("engine not installed")) }; return
            }
            let r = Shell.run("cd '\(res.path)' && '\(py)' '\(script)' --selftest 2>&1", timeout: 90)
            let line = r.out.split(separator: "\n").map(String.init).last(where: { $0.contains("SELFTEST") }) ?? r.out
            DispatchQueue.main.async {
                done(line.contains("SELFTEST OK") ? .ok(line) : .fail(line.isEmpty ? "no output" : String(line.prefix(200))))
            }
        }
    }
}

// MARK: - Login item

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled { if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() } }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch { return false }
    }
}
