// Config.swift — settings model, persistence, and Frigate config generation.
import Foundation
import Security

// MARK: - Model

struct MQTTConfig: Codable {
    var enabled = true
    var host = ""
    var port = 1883
    var user = "frigate"
    var password = ""   // not persisted to config.json — stored in Keychain (see ConfigStore)

    enum CodingKeys: String, CodingKey { case enabled, host, port, user }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        host = (try? c.decode(String.self, forKey: .host)) ?? ""
        port = (try? c.decode(Int.self, forKey: .port)) ?? 1883
        user = (try? c.decode(String.self, forKey: .user)) ?? "frigate"
        // password intentionally left "" — populated from Keychain by ConfigStore.load()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(user, forKey: .user)
    }
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
    var rtspPassword = ""                // not persisted to config.json — stored in Keychain (see ConfigStore)
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
        case id, name, friendlyName, streamURL, subStreamURL, rtspUser, uiOrder, detect, record
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
        uiOrder = (try? c.decode(Int.self, forKey: .uiOrder)) ?? 0
        detect = (try? c.decode(Bool.self, forKey: .detect)) ?? true
        record = (try? c.decode(Bool.self, forKey: .record)) ?? true
        trackedObjects = (try? c.decode([String].self, forKey: .trackedObjects)) ?? ["person"]
        detectFPS = (try? c.decode(Int.self, forKey: .detectFPS)) ?? 5
        detectWidth = (try? c.decode(Int.self, forKey: .detectWidth)) ?? 320
        detectHeight = (try? c.decode(Int.self, forKey: .detectHeight)) ?? 180
        extraYAML = (try? c.decode(String.self, forKey: .extraYAML)) ?? ""
        // rtspPassword intentionally left "" — populated from Keychain by ConfigStore.load()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(friendlyName, forKey: .friendlyName)
        try c.encode(streamURL, forKey: .streamURL)
        try c.encode(subStreamURL, forKey: .subStreamURL)
        try c.encode(rtspUser, forKey: .rtspUser)
        try c.encode(uiOrder, forKey: .uiOrder)
        try c.encode(detect, forKey: .detect)
        try c.encode(record, forKey: .record)
        try c.encode(trackedObjects, forKey: .trackedObjects)
        try c.encode(detectFPS, forKey: .detectFPS)
        try c.encode(detectWidth, forKey: .detectWidth)
        try c.encode(detectHeight, forKey: .detectHeight)
        try c.encode(extraYAML, forKey: .extraYAML)
    }
}

struct YOLOConfig: Codable {
    var modelFile = "yolo.onnx"
    var modelType = "yolo-generic"       // Frigate model.model_type
    var width = 320
    var height = 320
    var computeUnits = "CPUAndNeuralEngine"

    enum CodingKeys: String, CodingKey { case modelFile, modelType, width, height, computeUnits }
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        modelFile = (try? c.decode(String.self, forKey: .modelFile)) ?? "yolo.onnx"
        modelType = (try? c.decode(String.self, forKey: .modelType)) ?? "yolo-generic"
        width = (try? c.decode(Int.self, forKey: .width)) ?? 320
        height = (try? c.decode(Int.self, forKey: .height)) ?? 320
        computeUnits = (try? c.decode(String.self, forKey: .computeUnits)) ?? "CPUAndNeuralEngine"
    }
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
    var scryptedHost = ""                // optional Scrypted host for rebroadcast links

    enum CodingKeys: String, CodingKey {
        case mqtt, ha, storagePath, cameras, retentionContinuousDays, retentionEventDays
        case yolo, localAI, detectorEndpoint, frigateImage, configured
        case launchAtLogin, autostartFrigate, resetAdminPassword, scryptedHost
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
        scryptedHost = (try? c.decode(String.self, forKey: .scryptedHost)) ?? ""
    }
}

// MARK: - Keychain

/// Minimal Keychain wrapper for secrets we don't want sitting in plaintext
/// config.json (MQTT password, per-camera RTSP password).
enum Keychain {
    private static let service = "com.frigateane.detector"

    @discardableResult
    static func set(account: String, value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return true
        }
        let data = Data(value.utf8)
        let addAttrs = query.merging([kSecValueData as String: data]) { _, new in new }
        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return addStatus == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
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
        if var c = try? JSONDecoder().decode(AppConfig.self, from: data) {
            // Passwords are excluded from config.json's Codable representation — pull
            // them back in from the Keychain (see MQTTConfig/CameraConfig custom encode).
            c.mqtt.password = Keychain.get(account: "mqtt") ?? ""
            for i in c.cameras.indices {
                c.cameras[i].rtspPassword = Keychain.get(account: "cam-\(c.cameras[i].id.uuidString)") ?? ""
            }
            config = c
        }
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        mutate(&config)
        save()
    }

    @discardableResult
    func save() -> Bool {
        // Persist secrets to the Keychain; config.json never sees them in plaintext.
        Keychain.set(account: "mqtt", value: config.mqtt.password)
        for cam in config.cameras {
            Keychain.set(account: "cam-\(cam.id.uuidString)", value: cam.rtspPassword)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return false }
        return (try? data.write(to: configJSONURL)) != nil
    }

    /// Backup: write the current config as JSON to a chosen file. Unlike the
    /// auto-managed config.json, a user-chosen backup file includes the actual
    /// passwords (merged in manually, since AppConfig's Codable conformance
    /// omits them) so a restore is a full round-trip.
    func exportConfig(to url: URL) -> Bool {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if var mqtt = obj["mqtt"] as? [String: Any] {
            mqtt["password"] = config.mqtt.password
            obj["mqtt"] = mqtt
        }
        if var cams = obj["cameras"] as? [[String: Any]] {
            for i in cams.indices where i < config.cameras.count {
                cams[i]["rtspPassword"] = config.cameras[i].rtspPassword
            }
            obj["cameras"] = cams
        }
        guard let outData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return false }
        return (try? outData.write(to: url)) != nil
    }

    /// Restore: load config from a JSON file (replaces current settings),
    /// including passwords if the backup file has them (see exportConfig).
    func importConfig(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              var c = try? JSONDecoder().decode(AppConfig.self, from: data) else { return false }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let mqtt = obj["mqtt"] as? [String: Any], let pw = mqtt["password"] as? String {
                c.mqtt.password = pw
            }
            if let cams = obj["cameras"] as? [[String: Any]] {
                for (i, cam) in cams.enumerated() where i < c.cameras.count {
                    if let pw = cam["rtspPassword"] as? String { c.cameras[i].rtspPassword = pw }
                }
            }
        }
        config = c
        return save()
    }
}
