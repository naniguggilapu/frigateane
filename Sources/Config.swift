// Config.swift — settings model, persistence, and Frigate config generation.
import Foundation

// MARK: - Model

struct MQTTConfig: Codable {
    var enabled = true
    var host = ""
    var port = 1883
    var user = "frigate"
    var password = ""
}

struct HAConfig: Codable {
    var discoveryEnabled = true          // MQTT auto-discovery into Home Assistant
}

struct CameraConfig: Codable, Identifiable {
    var id = UUID()
    var name = "camera"                  // YAML key (sanitized); short id
    var friendlyName = ""                // display alias in Frigate UI (optional)
    var streamURL = ""                   // main / record stream (rtsp://…)
    var subStreamURL = ""                // detect stream (lower res); optional
    var rtspUser = ""                    // optional creds injected into the URLs
    var rtspPassword = ""
    var uiOrder = 0                      // order in the Frigate UI (0 = auto)
    var detect = true
    var record = true
    // advanced (all optional, backward-compatible)
    var trackedObjects: [String] = ["person"]
    var detectFPS = 5
    var detectWidth = 320
    var detectHeight = 180
    var extraYAML = ""                   // power-user YAML appended under the camera

    enum CodingKeys: String, CodingKey {
        case id, name, friendlyName, streamURL, subStreamURL, rtspUser, rtspPassword, uiOrder, detect, record
        case trackedObjects, detectFPS, detectWidth, detectHeight, extraYAML
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "camera"
        friendlyName = (try? c.decode(String.self, forKey: .friendlyName)) ?? ""
        streamURL = (try? c.decode(String.self, forKey: .streamURL)) ?? ""
        subStreamURL = (try? c.decode(String.self, forKey: .subStreamURL)) ?? ""
        rtspUser = (try? c.decode(String.self, forKey: .rtspUser)) ?? ""
        rtspPassword = (try? c.decode(String.self, forKey: .rtspPassword)) ?? ""
        uiOrder = (try? c.decode(Int.self, forKey: .uiOrder)) ?? 0
        detect = (try? c.decode(Bool.self, forKey: .detect)) ?? true
        record = (try? c.decode(Bool.self, forKey: .record)) ?? true
        trackedObjects = (try? c.decode([String].self, forKey: .trackedObjects)) ?? ["person"]
        detectFPS = (try? c.decode(Int.self, forKey: .detectFPS)) ?? 5
        detectWidth = (try? c.decode(Int.self, forKey: .detectWidth)) ?? 320
        detectHeight = (try? c.decode(Int.self, forKey: .detectHeight)) ?? 180
        extraYAML = (try? c.decode(String.self, forKey: .extraYAML)) ?? ""
    }
}

struct YOLOConfig: Codable {
    var modelFile = "yolo.onnx"
    var width = 320
    var height = 320
    var computeUnits = "CPUAndNeuralEngine"
}

struct LocalAIConfig: Codable {
    var enabled = false
    var provider = "ollama"
    var baseURL = "http://127.0.0.1:11434"
    var model = "moondream"
}

struct AppConfig: Codable {
    var mqtt = MQTTConfig()
    var ha = HAConfig()
    var storagePath = ""
    var cameras: [CameraConfig] = []
    var retentionContinuousDays = 7
    var retentionEventDays = 30
    var yolo = YOLOConfig()
    var localAI = LocalAIConfig()
    var detectorEndpoint = "tcp://0.0.0.0:5555"
    var frigateImage = "ghcr.io/blakeblackshear/frigate:0.17.0-beta1-standard-arm64"
    var configured = false
    // new flags (backward-compatible)
    var launchAtLogin = false
    var autostartFrigate = false
    var resetAdminPassword = false       // one-shot: makes Frigate reset the admin pw on next start

    enum CodingKeys: String, CodingKey {
        case mqtt, ha, storagePath, cameras, retentionContinuousDays, retentionEventDays
        case yolo, localAI, detectorEndpoint, frigateImage, configured
        case launchAtLogin, autostartFrigate, resetAdminPassword
    }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        mqtt = (try? c.decode(MQTTConfig.self, forKey: .mqtt)) ?? MQTTConfig()
        ha = (try? c.decode(HAConfig.self, forKey: .ha)) ?? HAConfig()
        storagePath = (try? c.decode(String.self, forKey: .storagePath)) ?? ""
        cameras = (try? c.decode([CameraConfig].self, forKey: .cameras)) ?? []
        retentionContinuousDays = (try? c.decode(Int.self, forKey: .retentionContinuousDays)) ?? 7
        retentionEventDays = (try? c.decode(Int.self, forKey: .retentionEventDays)) ?? 30
        yolo = (try? c.decode(YOLOConfig.self, forKey: .yolo)) ?? YOLOConfig()
        localAI = (try? c.decode(LocalAIConfig.self, forKey: .localAI)) ?? LocalAIConfig()
        detectorEndpoint = (try? c.decode(String.self, forKey: .detectorEndpoint)) ?? "tcp://0.0.0.0:5555"
        frigateImage = (try? c.decode(String.self, forKey: .frigateImage)) ?? "ghcr.io/blakeblackshear/frigate:0.17.0-beta1-standard-arm64"
        configured = (try? c.decode(Bool.self, forKey: .configured)) ?? false
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        autostartFrigate = (try? c.decode(Bool.self, forKey: .autostartFrigate)) ?? false
        resetAdminPassword = (try? c.decode(Bool.self, forKey: .resetAdminPassword)) ?? false
    }
}

// MARK: - Store

final class ConfigStore {
    static let shared = ConfigStore()
    private(set) var config = AppConfig()

    var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FrigateANE", isDirectory: true)
    }
    var configJSONURL: URL { supportDir.appendingPathComponent("config.json") }
    var frigateConfigDir: URL { supportDir.appendingPathComponent("frigate-config", isDirectory: true) }
    var frigateConfigYAML: URL { frigateConfigDir.appendingPathComponent("config.yaml") }
    var startScriptURL: URL { supportDir.appendingPathComponent("start-frigate.sh") }

    private init() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: frigateConfigDir, withIntermediateDirectories: true)
        load()
        if config.storagePath.isEmpty {
            config.storagePath = supportDir.appendingPathComponent("recordings").path
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: configJSONURL) else { return }
        if let c = try? JSONDecoder().decode(AppConfig.self, from: data) { config = c }
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        mutate(&config)
        save()
    }

    @discardableResult
    func save() -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return false }
        return (try? data.write(to: configJSONURL)) != nil
    }
}
