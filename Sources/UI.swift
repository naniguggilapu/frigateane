// UI.swift — setup wizard, status dashboard, menubar, app entry.
import AppKit
import Foundation

// MARK: - Small UI helpers

func label(_ s: String, secondary: Bool = false, bold: Bool = false) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    if secondary { t.textColor = .secondaryLabelColor }
    if bold { t.font = .systemFont(ofSize: 13, weight: .semibold) }
    return t
}
func field(_ value: String, width: CGFloat = 280, placeholder: String = "") -> NSTextField {
    let f = NSTextField(string: value)
    f.placeholderString = placeholder
    f.widthAnchor.constraint(equalToConstant: width).isActive = true
    return f
}
func formRow(_ title: String, _ control: NSView) -> NSStackView {
    let t = label(title, secondary: true)
    t.alignment = .right
    t.widthAnchor.constraint(equalToConstant: 150).isActive = true
    let s = NSStackView(views: [t, control]); s.orientation = .horizontal; s.spacing = 10; s.alignment = .centerY
    return s
}
func vstack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let s = NSStackView(views: views); s.orientation = .vertical; s.alignment = .leading; s.spacing = spacing
    s.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    return s
}
func smallButton(_ title: String, _ target: AnyObject, _ sel: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: sel); b.bezelStyle = .rounded
    b.controlSize = .small; b.font = .systemFont(ofSize: 11)
    return b
}

// MARK: - Sparkline

final class Sparkline: NSView {
    var samples: [Double] = [] { didSet { needsDisplay = true } }
    var maxSamples = 60
    func push(_ v: Double) { samples.append(v); if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) } }
    override func draw(_ rect: NSRect) {
        NSColor.clear.set(); rect.fill()
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor(white: 0.5, alpha: 0.08).setFill(); bg.fill()
        guard samples.count > 1 else { return }
        let maxV = max(samples.max() ?? 1, 1)
        let path = NSBezierPath(); path.lineWidth = 2
        let n = samples.count
        for (i, v) in samples.enumerated() {
            let x = bounds.minX + bounds.width * CGFloat(i) / CGFloat(n - 1)
            let y = bounds.minY + 4 + (bounds.height - 8) * CGFloat(v / maxV)
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        NSColor.systemGreen.setStroke(); path.stroke()
    }
}

/// Flipped container so scroll content lays out top-to-bottom (AppKit views are
/// bottom-origin by default, which makes short content sit at the bottom).
final class FlippedView: NSView { override var isFlipped: Bool { true } }

// MARK: - Camera row

final class CameraRow: NSView {
    let nameF = field("camera", width: 100, placeholder: "id e.g. front_door")
    let friendlyF = field("", width: 150, placeholder: "Display name (alias)")
    let orderF = field("0", width: 40)
    let mainF = field("", width: 420, placeholder: "rtsp://host:554/main   (record stream)")
    let subF  = field("", width: 420, placeholder: "rtsp://host:554/sub   (detect stream, optional)")
    let userF = field("", width: 120, placeholder: "rtsp user")
    let passF = NSSecureTextField(string: "")
    let objF  = field("person", width: 170, placeholder: "person, dog")
    let fpsF  = field("5", width: 44)
    let wF    = field("320", width: 52)
    let hF    = field("180", width: 52)
    let rtspResult = label("", secondary: true)
    var extraYAML = ""
    var onRemove: (() -> Void)?

    init(_ cam: CameraConfig) {
        super.init(frame: .zero)
        nameF.stringValue = cam.name
        friendlyF.stringValue = cam.friendlyName
        orderF.stringValue = String(cam.uiOrder)
        mainF.stringValue = cam.streamURL
        subF.stringValue = cam.subStreamURL
        userF.stringValue = cam.rtspUser
        passF.stringValue = cam.rtspPassword
        passF.placeholderString = "rtsp password"
        passF.widthAnchor.constraint(equalToConstant: 120).isActive = true
        objF.stringValue = cam.trackedObjects.joined(separator: ", ")
        fpsF.stringValue = String(cam.detectFPS)
        wF.stringValue = String(cam.detectWidth)
        hF.stringValue = String(cam.detectHeight)
        extraYAML = cam.extraYAML

        let yamlBtn = smallButton("Zones/YAML…", self, #selector(editYAML))
        let testBtn = smallButton("Test RTSP", self, #selector(testRTSP))
        let rm = NSButton(title: "✕", target: self, action: #selector(remove)); rm.bezelStyle = .circular

        func lbl(_ t: String) -> NSTextField { label(t, secondary: true) }
        let line1 = NSStackView(views: [lbl("id"), nameF, lbl("name"), friendlyF, lbl("order"), orderF, yamlBtn, rm])
        line1.spacing = 6; line1.alignment = .centerY
        let line2 = NSStackView(views: [lbl("main"), mainF, testBtn, rtspResult]); line2.spacing = 6; line2.alignment = .centerY
        let line3 = NSStackView(views: [lbl("sub"), subF]); line3.spacing = 6; line3.alignment = .centerY
        let line4 = NSStackView(views: [lbl("login"), userF, passF,
                                        lbl("track"), objF, lbl("fps"), fpsF,
                                        lbl("size"), wF, lbl("×"), hF]); line4.spacing = 6; line4.alignment = .centerY

        let v = NSStackView(views: [line1, line2, line3, line4]); v.orientation = .vertical; v.alignment = .leading; v.spacing = 4
        let box = NSBox(); box.boxType = .custom; box.cornerRadius = 6; box.borderWidth = 1
        box.borderColor = NSColor(white: 0.5, alpha: 0.25); box.contentView = v
        v.translatesAutoresizingMaskIntoConstraints = false
        box.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            box.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(equalTo: trailingAnchor),
            v.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            v.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func remove() { onRemove?() }
    @objc func testRTSP() {
        rtspResult.stringValue = "testing…"; rtspResult.textColor = .secondaryLabelColor
        Probes.rtsp(mainF.stringValue) { [weak self] r in
            self?.rtspResult.stringValue = r.success ? "✓ \(r.message)" : "✕ \(r.message)"
            self?.rtspResult.textColor = r.success ? .systemGreen : .systemOrange
        }
    }
    @objc func editYAML() {
        let a = NSAlert(); a.messageText = "Advanced YAML for \(nameF.stringValue)"
        a.informativeText = "Appended under this camera — e.g. zones:, motion:, mqtt:. Use Frigate's YAML indentation (relative to the camera)."
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
        tv.string = extraYAML; tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular); tv.isRichText = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 180))
        scroll.documentView = tv; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        a.accessoryView = scroll
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { extraYAML = tv.string }
    }

    var value: CameraConfig {
        var c = CameraConfig()
        c.name = nameF.stringValue.isEmpty ? "camera" : nameF.stringValue.replacingOccurrences(of: " ", with: "_")
        c.friendlyName = friendlyF.stringValue
        c.uiOrder = Int(orderF.stringValue) ?? 0
        c.streamURL = mainF.stringValue
        c.subStreamURL = subF.stringValue
        c.rtspUser = userF.stringValue
        c.rtspPassword = passF.stringValue
        c.trackedObjects = objF.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if c.trackedObjects.isEmpty { c.trackedObjects = ["person"] }
        c.detectFPS = Int(fpsF.stringValue) ?? 5
        c.detectWidth = Int(wF.stringValue) ?? 320
        c.detectHeight = Int(hF.stringValue) ?? 180
        c.extraYAML = extraYAML
        return c
    }
}

// MARK: - Setup wizard

final class SetupWindowController: NSWindowController {
    let store = ConfigStore.shared
    var onDone: (() -> Void)?

    private let mqttHost = field("")
    private let mqttPort = field("1883", width: 80)
    private let mqttUser = field("frigate")
    private let mqttPass = NSSecureTextField(string: "")
    private let mqttResult = label("", secondary: true)
    private let haDiscovery = NSButton(checkboxWithTitle: "Enable Home Assistant MQTT discovery", target: nil, action: nil)
    private let storageField = field("", width: 360)
    private let storageWarn = label("", secondary: true)
    private let yoloPopup = NSPopUpButton()
    private let typePopup = NSPopUpButton()
    private let yoloW = field("320", width: 70)
    private let yoloH = field("320", width: 70)
    private let detResult = label("", secondary: true)
    private let orch = Orchestrator()
    private let scryptedField = field("", width: 160, placeholder: "Scrypted host (optional)")
    private let scryptedResult = label("", secondary: true)
    private let aiEnable = NSButton(checkboxWithTitle: "Enable local AI scene descriptions (Ollama)", target: nil, action: nil)
    private let aiBase = field("http://127.0.0.1:11434")
    private let aiModel = field("moondream", width: 160)
    private let loginCheck = NSButton(checkboxWithTitle: "Launch Frigate ANE at login", target: nil, action: nil)
    private let autostartCheck = NSButton(checkboxWithTitle: "Auto-start Frigate + detector on launch", target: nil, action: nil)
    private let retCont = field("7", width: 60)
    private let retEvent = field("30", width: 60)
    private var cameraRows: [CameraRow] = []
    private let camerasStack = NSStackView()

    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Frigate ANE — Setup"; win.center()
        super.init(window: win)
        build(); loadFromConfig()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let tabs = NSTabView(); tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(tab("MQTT", mqttView()))
        tabs.addTabViewItem(tab("Home Assistant", haView()))
        tabs.addTabViewItem(tab("Storage", storageView()))
        tabs.addTabViewItem(tab("Cameras", camerasView()))
        tabs.addTabViewItem(tab("Models", modelsView()))
        tabs.addTabViewItem(tab("Startup", startupView()))

        let save = NSButton(title: "Save & Generate Config", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), save]); footer.orientation = .horizontal
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 16, right: 20)

        let root = NSStackView(views: [tabs, footer]); root.orientation = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        let cv = window!.contentView!; cv.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: cv.topAnchor), root.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: cv.trailingAnchor), root.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            tabs.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }
    private func tab(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title); item.label = title; item.view = view; return item
    }

    private func mqttView() -> NSView {
        let test = NSButton(title: "Test connection", target: self, action: #selector(testMQTT)); test.bezelStyle = .rounded
        return vstack([
            label("MQTT broker", bold: true),
            label("Frigate publishes camera + detection state to MQTT (e.g. Home Assistant's Mosquitto).", secondary: true),
            formRow("Host", mqttHost), formRow("Port", mqttPort), formRow("User", mqttUser),
            formRow("Password", { mqttPass.widthAnchor.constraint(equalToConstant: 280).isActive = true; return mqttPass }()),
            NSStackView(views: [test, mqttResult]),
        ])
    }
    private func haView() -> NSView {
        return vstack([
            label("Home Assistant", bold: true),
            label("With discovery on, cameras and sensors appear in Home Assistant automatically over MQTT.", secondary: true),
            haDiscovery,
        ])
    }
    private func storageView() -> NSView {
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseStorage)); choose.bezelStyle = .rounded
        let rowS = NSStackView(views: [storageField, choose]); rowS.spacing = 8
        return vstack([
            label("Recordings storage", bold: true),
            label("Pick the drive/folder for recordings. Use a mounted drive with space.", secondary: true),
            formRow("Path", rowS), storageWarn,
        ])
    }
    private func camerasView() -> NSView {
        camerasStack.orientation = .vertical; camerasStack.alignment = .leading; camerasStack.spacing = 4
        let add = NSButton(title: "+ Add camera", target: self, action: #selector(addCamera)); add.bezelStyle = .rounded
        let scroll = NSScrollView(); let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(camerasStack); camerasStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            camerasStack.topAnchor.constraint(equalTo: doc.topAnchor),
            camerasStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            camerasStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            camerasStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),   // drives doc height
            doc.widthAnchor.constraint(equalToConstant: 690),
        ])
        scroll.documentView = doc; scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 700).isActive = true
        let ret = NSStackView(views: [label("Retention:", secondary: true), label("continuous", secondary: true), retCont,
                                      label("days · events", secondary: true), retEvent, label("days", secondary: true)]); ret.spacing = 6
        let detectBtn = NSButton(title: "Detect Scrypted", target: self, action: #selector(detectScryptedTapped)); detectBtn.bezelStyle = .rounded
        let openBtn = NSButton(title: "Open", target: self, action: #selector(openScryptedTapped)); openBtn.bezelStyle = .rounded
        let scryptedRow = NSStackView(views: [label("Scrypted:", secondary: true), scryptedField, detectBtn, openBtn]); scryptedRow.spacing = 6
        return vstack([
            label("Cameras", bold: true),
            label("Main = recording, Sub = detection. Per-camera objects, fps, size; “Zones/YAML…” for advanced.", secondary: true),
            add, scroll, ret, scryptedRow, scryptedResult,
        ])
    }
    private func modelsView() -> NSView {
        yoloPopup.removeAllItems()
        let modelsDir = Bundle.main.resourceURL!.appendingPathComponent("engine/models")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path) {
            for f in files.sorted() where f.hasSuffix(".onnx") { yoloPopup.addItem(withTitle: f) }
        }
        if yoloPopup.numberOfItems == 0 { yoloPopup.addItem(withTitle: "yolo.onnx") }
        if typePopup.numberOfItems == 0 {
            typePopup.addItems(withTitles: ["yolo-generic", "yolonas", "yolov9", "rfdetr", "dfine"])
        }
        let selftest = NSButton(title: "Self-test detector (ANE)", target: self, action: #selector(selfTestDetector)); selftest.bezelStyle = .rounded
        let aiInstall = NSButton(title: "Install model", target: self, action: #selector(installAIModel)); aiInstall.bezelStyle = .rounded
        let aiRow = NSStackView(views: [aiModel, aiInstall]); aiRow.spacing = 8
        return vstack([
            label("Detector model (runs on the Apple Neural Engine)", bold: true),
            formRow("Model file", yoloPopup),
            formRow("Model type", typePopup),
            label("yolo-generic fits the bundled YOLO; other types need a matching .onnx model.", secondary: true),
            formRow("Input W×H", { let s = NSStackView(views: [yoloW, label("×"), yoloH]); s.spacing = 6; return s }()),
            NSStackView(views: [selftest, detResult]),
            label(" "),
            label("Local AI (optional)", bold: true),
            aiEnable, formRow("Base URL", aiBase), formRow("Vision model", aiRow),
        ])
    }
    private func startupView() -> NSView {
        return vstack([
            label("Startup", bold: true),
            label("Make Frigate ANE fully turnkey — start with the Mac and bring the stack up automatically.", secondary: true),
            loginCheck, autostartCheck,
            label("Auto-start runs the detector and (if the container runtime is present) Frigate when the app launches.", secondary: true),
        ])
    }

    // actions
    @objc private func testMQTT() {
        commitToConfig(); mqttResult.stringValue = "testing…"; mqttResult.textColor = .secondaryLabelColor
        Probes.mqtt(store.config.mqtt) { [weak self] r in
            self?.mqttResult.stringValue = r.success ? "✓ \(r.message)" : "✕ \(r.message)"
            self?.mqttResult.textColor = r.success ? .systemGreen : .systemOrange
        }
    }
    @objc private func selfTestDetector() {
        detResult.stringValue = "running ANE self-test…"; detResult.textColor = .secondaryLabelColor
        Probes.detectorSelfTest { [weak self] r in
            self?.detResult.stringValue = r.success ? "✓ \(r.message)" : "✕ \(r.message)"
            self?.detResult.textColor = r.success ? .systemGreen : .systemOrange
        }
    }
    @objc private func chooseStorage() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { storageField.stringValue = url.path; validateStorage() }
    }
    private func validateStorage() {
        let p = storageField.stringValue; var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
        if p.isEmpty { storageWarn.stringValue = "" }
        else if !exists { storageWarn.stringValue = "⚠︎ Path does not exist / drive not mounted."; storageWarn.textColor = .systemOrange }
        else { storageWarn.stringValue = "✓ Available."; storageWarn.textColor = .systemGreen }
    }
    @objc private func addCamera() {
        var cam = CameraConfig()
        // Pick a default id that isn't already in use — camera count alone can
        // collide after a row in the middle has been removed.
        let used = Set(cameraRows.map { $0.nameF.stringValue })
        var n = cameraRows.count + 1
        var name = "camera\(n)"
        while used.contains(name) { n += 1; name = "camera\(n)" }
        cam.name = name
        appendCamera(cam)
    }
    private func appendCamera(_ cam: CameraConfig) {
        let row = CameraRow(cam)
        row.onRemove = { [weak self, weak row] in
            guard let self = self, let row = row else { return }
            self.cameraRows.removeAll { $0 === row }; self.camerasStack.removeView(row)
        }
        cameraRows.append(row); camerasStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: camerasStack.widthAnchor).isActive = true
    }
    @objc private func installAIModel() {
        commitToConfig()
        orch.installOllamaModel { ok in let a = NSAlert(); a.messageText = ok ? "Model installed." : "Could not install model (is Ollama installed?)."; a.runModal() }
    }
    @objc private func detectScryptedTapped() {
        scryptedResult.stringValue = "checking…"; scryptedResult.textColor = .secondaryLabelColor
        orch.detectScrypted(host: scryptedField.stringValue) { [weak self] found, _ in
            if found {
                self?.scryptedResult.stringValue = "✓ Scrypted found — Open it, copy rebroadcast RTSP URLs into the fields above (no login)."
                self?.scryptedResult.textColor = .systemGreen
            } else {
                self?.scryptedResult.stringValue = "✕ No Scrypted at that host (checked ports 10443 / 11080)."
                self?.scryptedResult.textColor = .systemOrange
            }
        }
    }
    @objc private func openScryptedTapped() {
        let host = scryptedField.stringValue.isEmpty ? "localhost" : scryptedField.stringValue
        if let u = URL(string: "https://\(host):10443") { NSWorkspace.shared.open(u) }
    }

    private func loadFromConfig() {
        let c = store.config
        mqttHost.stringValue = c.mqtt.host; mqttPort.stringValue = String(c.mqtt.port)
        mqttUser.stringValue = c.mqtt.user; mqttPass.stringValue = c.mqtt.password
        haDiscovery.state = c.ha.discoveryEnabled ? .on : .off
        storageField.stringValue = c.storagePath
        retCont.stringValue = String(c.retentionContinuousDays); retEvent.stringValue = String(c.retentionEventDays)
        yoloW.stringValue = String(c.yolo.width); yoloH.stringValue = String(c.yolo.height)
        typePopup.selectItem(withTitle: c.yolo.modelType)
        scryptedField.stringValue = c.scryptedHost
        aiEnable.state = c.localAI.enabled ? .on : .off; aiBase.stringValue = c.localAI.baseURL; aiModel.stringValue = c.localAI.model
        loginCheck.state = (c.launchAtLogin || LoginItem.isEnabled) ? .on : .off
        autostartCheck.state = c.autostartFrigate ? .on : .off
        for cam in c.cameras { appendCamera(cam) }
        validateStorage()
    }
    private func commitToConfig() {
        store.update { c in
            c.mqtt.host = mqttHost.stringValue; c.mqtt.port = Int(mqttPort.stringValue) ?? 1883
            c.mqtt.user = mqttUser.stringValue; c.mqtt.password = mqttPass.stringValue
            c.mqtt.enabled = !mqttHost.stringValue.isEmpty
            c.ha.discoveryEnabled = haDiscovery.state == .on
            c.storagePath = storageField.stringValue
            c.retentionContinuousDays = Int(retCont.stringValue) ?? 7
            c.retentionEventDays = Int(retEvent.stringValue) ?? 30
            c.yolo.modelFile = yoloPopup.titleOfSelectedItem ?? "yolo.onnx"
            c.yolo.modelType = typePopup.titleOfSelectedItem ?? "yolo-generic"
            c.scryptedHost = scryptedField.stringValue
            c.yolo.width = Int(yoloW.stringValue) ?? 320; c.yolo.height = Int(yoloH.stringValue) ?? 320
            c.localAI.enabled = aiEnable.state == .on; c.localAI.baseURL = aiBase.stringValue; c.localAI.model = aiModel.stringValue
            c.launchAtLogin = loginCheck.state == .on; c.autostartFrigate = autostartCheck.state == .on
            c.cameras = cameraRows.map { $0.value }
        }
    }
    @objc private func saveTapped() {
        commitToConfig()
        LoginItem.set(store.config.launchAtLogin)
        do { try ConfigGenerator.writeAll(store) }
        catch { let a = NSAlert(); a.messageText = "Failed to write config: \(error)"; a.runModal(); return }
        store.update { $0.configured = true }
        let a = NSAlert(); a.messageText = "Configuration saved."
        a.informativeText = "Frigate config written to:\n\(store.frigateConfigYAML.path)"; a.runModal()
        onDone?(); window?.close()
    }
}

// MARK: - Status dashboard

final class DashboardWindowController: NSWindowController {
    let engine: Engine
    let orch = Orchestrator()
    private let logView = NSTextView()
    private let detLabel = label("detector: —")
    private let stackLabel = label("stack: checking…")
    private let spark = Sparkline()
    private var timer: Timer?
    private var detecting = false        // guard against overlapping stack probes

    init(engine: Engine) {
        self.engine = engine
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Frigate ANE — Dashboard"; win.center()
        super.init(window: win)
        build()
        engine.onState = { [weak self] in self?.refreshDetector() }
        engine.onLog = { [weak self] s in self?.appendLog(s) }
        orch.onProgress = { [weak self] s in self?.appendLog(s) }
        refreshDetector(); refreshStack()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let startAll = NSButton(title: "Start All", target: self, action: #selector(startAll))
        let stop = NSButton(title: "Stop Frigate", target: self, action: #selector(stopFrigate))
        let openUI = NSButton(title: "Open Frigate UI", target: self, action: #selector(openUI))
        let setup = NSButton(title: "Setup…", target: self, action: #selector(openSetup))
        let detToggle = NSButton(title: "Start/Stop Detector", target: self, action: #selector(toggleDetector))
        let netInstall = NSButton(title: "Install Networking", target: self, action: #selector(installNetworking))
        let reveal = NSButton(title: "Reveal Config", target: self, action: #selector(revealConfig))
        let copyCfg = NSButton(title: "Copy config.yaml", target: self, action: #selector(copyConfig))
        let installRuntime = NSButton(title: "Install Container Runtime", target: self, action: #selector(installRuntime))
        let showPw = NSButton(title: "Show Admin Password", target: self, action: #selector(showPw))
        let resetPw = NSButton(title: "Reset Admin Password", target: self, action: #selector(resetPw))
        let backup = NSButton(title: "Backup Config…", target: self, action: #selector(backupConfig))
        let restore = NSButton(title: "Restore Config…", target: self, action: #selector(restoreConfig))
        for b in [startAll, stop, openUI, setup, detToggle, netInstall, reveal, copyCfg, installRuntime, showPw, resetPw, backup, restore] { b.bezelStyle = .rounded }
        let controls = NSStackView(views: [startAll, stop, detToggle, openUI]); controls.spacing = 10
        let controls2 = NSStackView(views: [installRuntime, netInstall, reveal, copyCfg, setup]); controls2.spacing = 10
        let controls3 = NSStackView(views: [showPw, resetPw, backup, restore]); controls3.spacing = 10

        spark.translatesAutoresizingMaskIntoConstraints = false
        spark.heightAnchor.constraint(equalToConstant: 44).isActive = true
        spark.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let sparkRow = NSStackView(views: [label("inf/s", secondary: true), spark]); sparkRow.spacing = 8; sparkRow.alignment = .centerY

        logView.isEditable = false; logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView(); scroll.documentView = logView; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder; scroll.translatesAutoresizingMaskIntoConstraints = false

        let root = vstack([label("Frigate ANE", bold: true), stackLabel, detLabel, sparkRow, controls, controls2, controls3, scroll], spacing: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        let cv = window!.contentView!; cv.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: cv.topAnchor), root.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: cv.trailingAnchor), root.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    private func tick() {
        guard window?.isVisible == true else { return }   // don't probe while hidden
        spark.push(engine.fps)
        refreshStack()
    }
    private func refreshDetector() {
        detLabel.stringValue = String(format: "detector: %@ · %@ · %.1f inf/s",
            engine.running ? "running" : "stopped", engine.provider, engine.fps)
    }
    private func refreshStack() {
        if detecting { return }          // don't stack up probes if one is still running
        detecting = true
        orch.detect { [weak self] st in
            guard let self = self else { return }
            self.detecting = false
            var parts: [String] = []
            parts.append("macOS \(st.macOSMajor)\(st.macOSCompatible ? "" : " (needs 26+)")")
            parts.append("container: \(st.containerCLI ? (st.containerVersion ?? "✓") : "✕")")
            parts.append("NAT: \(st.natConfigured ? "✓" : "✕")")
            parts.append("image: \(st.imagePresent ? "✓" : "✕")")
            parts.append("frigate: \(st.frigateRunning ? (st.frigateHealthy ? "healthy" : "running") : "stopped")")
            if self.store.config.localAI.enabled { parts.append("ollama: \(st.ollamaInstalled ? "✓" : "✕")") }
            self.stackLabel.stringValue = "stack — " + parts.joined(separator: "  ·  ")
        }
    }
    var store: ConfigStore { ConfigStore.shared }

    @objc private func startAll() {
        appendLog("Starting full stack…\n")
        if engine.isInstalled && !engine.running { engine.start() }
        orch.startAll { [weak self] ok in self?.appendLog(ok ? "✓ stack started.\n" : "✕ stack start incomplete — see notes.\n"); self?.refreshStack() }
    }
    @objc private func stopFrigate() { orch.stopFrigate { [weak self] in self?.refreshStack() } }
    @objc private func installNetworking() { appendLog("Installing container NAT networking…\n"); orch.installNetworking { [weak self] _ in self?.refreshStack() } }
    @objc private func installRuntime() { appendLog("Installing Apple container runtime…\n"); orch.installContainerRuntime { [weak self] _ in self?.refreshStack() } }
    @objc private func showPw() { appendLog("Fetching Frigate admin login from logs…\n"); orch.showAdminPassword { _ in } }
    @objc private func resetPw() {
        let a = NSAlert(); a.messageText = "Reset Frigate admin password?"
        a.informativeText = "Restarts Frigate and generates a new admin password (shown in the log below)."
        a.addButton(withTitle: "Reset"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            appendLog("Resetting admin password…\n")
            orch.resetAdminPassword { [weak self] _ in self?.refreshStack() }
        }
    }
    @objc private func toggleDetector() { engine.running ? engine.stop() : engine.start() }
    @objc private func openUI() {
        orch.frigateUIURL { [weak self] url in
            self?.appendLog("Opening \(url)\n")
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
    }
    @objc private func backupConfig() {
        let p = NSSavePanel(); p.nameFieldStringValue = "frigateane-config.json"
        if p.runModal() == .OK, let url = p.url {
            appendLog(store.exportConfig(to: url) ? "✓ Config backed up to \(url.path)\n" : "✕ Backup failed.\n")
        }
    }
    @objc private func restoreConfig() {
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url {
            if store.importConfig(from: url) {
                appendLog("✓ Config restored from \(url.lastPathComponent). Open Setup to review, then Start All.\n")
            } else { appendLog("✕ Restore failed — not a valid config file.\n") }
        }
    }
    @objc private func openSetup() { (NSApp.delegate as? AppDelegate)?.showSetup() }
    @objc private func revealConfig() {
        do { try ConfigGenerator.writeAll(store) }
        catch { appendLog("✕ Failed to write config: \(error)\n"); return }
        NSWorkspace.shared.activateFileViewerSelecting([store.frigateConfigYAML])
    }
    @objc private func copyConfig() {
        let yaml = ConfigGenerator.frigateYAML(store.config)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(yaml, forType: .string)
        appendLog("config.yaml copied to clipboard.\n")
    }

    private func appendLog(_ s: String) {
        logView.textStorage?.append(NSAttributedString(string: s,
            attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]))
        if let len = logView.textStorage?.length, len > 200_000 {
            logView.textStorage?.deleteCharacters(in: NSRange(location: 0, length: len - 150_000))
        }
        logView.scrollToEndOfDocument(nil)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = Engine()
    let orch = Orchestrator()
    var statusItem: NSStatusItem!
    var dashboard: DashboardWindowController?
    var setup: SetupWindowController?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "eye.trianglebadge.exclamationmark", accessibilityDescription: "Frigate ANE")
            b.image?.isTemplate = true
        }
        rebuildMenu()
        engine.onState = { [weak self] in self?.rebuildMenu() }

        let cfg = ConfigStore.shared.config
        if cfg.configured {
            showDashboard()
            if engine.isInstalled { engine.start() }
            if cfg.autostartFrigate { orch.startAll { _ in } }
        } else {
            showSetup()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSetup() {
        let s = SetupWindowController(); s.onDone = { [weak self] in self?.showDashboard() }
        setup = s; s.showWindow(nil); s.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showDashboard() {
        if dashboard == nil { dashboard = DashboardWindowController(engine: engine) }
        dashboard?.showWindow(nil); dashboard?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func rebuildMenu() {
        let m = NSMenu()
        let head = NSMenuItem(title: "Detector: \(engine.running ? "running" : "stopped")", action: nil, keyEquivalent: ""); head.isEnabled = false
        m.addItem(head)
        if engine.running {
            let f = NSMenuItem(title: String(format: "  %.1f inf/s · %@", engine.fps, engine.aneActive ? "ANE" : "CPU"), action: nil, keyEquivalent: ""); f.isEnabled = false
            m.addItem(f)
        }
        m.addItem(.separator())
        add(m, "Dashboard", #selector(menuDashboard)); add(m, "Setup…", #selector(menuSetup))
        add(m, engine.running ? "Stop Detector" : "Start Detector", #selector(menuToggle))
        m.addItem(.separator())
        add(m, "Quit", #selector(menuQuit), key: "q")
        statusItem.menu = m
        if let b = statusItem.button { b.title = engine.running ? String(format: " %.0f", engine.fps) : "" }
    }
    private func add(_ m: NSMenu, _ title: String, _ sel: Selector, key: String = "") {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; m.addItem(i)
    }
    @objc func menuDashboard() { showDashboard() }
    @objc func menuSetup() { showSetup() }
    @objc func menuToggle() { engine.running ? engine.stop() : engine.start() }
    @objc func menuQuit() { engine.autoRestart = false; engine.stop(); NSApp.terminate(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ note: Notification) { engine.autoRestart = false; engine.stop() }
}
