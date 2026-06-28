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
    var name = "camera"
    var streamURL = ""                   // main / record stream (rtsp://…)
    var subStreamURL = ""                // detect stream (lower res); optional
    var detect = true
    var record = true
}

struct YOLOConfig: Codable {
    var modelFile = "yolo.onnx"          // file inside engine/models
    var width = 320
    var height = 320
    var computeUnits = "CPUAndNeuralEngine"   // ANE
}

struct LocalAIConfig: Codable {
    var enabled = false
    var provider = "ollama"
    var baseURL = "http://127.0.0.1:11434"
    var model = "moondream"              // vision model for scene descriptions
}

struct AppConfig: Codable {
    var mqtt = MQTTConfig()
    var ha = HAConfig()
    var storagePath = ""                 // recordings folder (must be a mounted volume)
    var cameras: [CameraConfig] = []
    var retentionContinuousDays = 7
    var retentionEventDays = 30
    var yolo = YOLOConfig()
    var localAI = LocalAIConfig()
    var detectorEndpoint = "tcp://0.0.0.0:5555"
    var frigateImage = "ghcr.io/blakeblackshear/frigate:0.17.0-beta1-standard-arm64"
    var configured = false               // set true once the wizard completes
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
