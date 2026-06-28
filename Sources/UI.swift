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
    let s = NSStackView(views: [t, control])
    s.orientation = .horizontal
    s.spacing = 10
    s.alignment = .centerY
    return s
}
func vstack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .vertical
    s.alignment = .leading
    s.spacing = spacing
    s.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    return s
}

// MARK: - Camera row widget

final class CameraRow: NSStackView {
    let nameF = field("camera", width: 120, placeholder: "name")
    let mainF = field("", width: 300, placeholder: "rtsp:// main stream")
    let subF  = field("", width: 300, placeholder: "rtsp:// sub stream (optional)")
    var onRemove: (() -> Void)?

    init(_ cam: CameraConfig) {
        super.init(frame: .zero)
        nameF.stringValue = cam.name
        mainF.stringValue = cam.streamURL
        subF.stringValue = cam.subStreamURL
        let rm = NSButton(title: "✕", target: self, action: #selector(remove))
        rm.bezelStyle = .circular
        orientation = .horizontal
        spacing = 8
        alignment = .centerY
        setViews([nameF, mainF, subF, rm], in: .leading)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func remove() { onRemove?() }

    var value: CameraConfig {
        var c = CameraConfig()
        c.name = nameF.stringValue.isEmpty ? "camera" : nameF.stringValue
        c.streamURL = mainF.stringValue
        c.subStreamURL = subF.stringValue
        return c
    }
}

// MARK: - Setup wizard

final class SetupWindowController: NSWindowController {
    let store = ConfigStore.shared
    var onDone: (() -> Void)?

    // field refs
    private let mqttHost = field("")
    private let mqttPort = field("1883", width: 80)
    private let mqttUser = field("frigate")
    private let mqttPass = NSSecureTextField(string: "")
    private let haDiscovery = NSButton(checkboxWithTitle: "Enable Home Assistant MQTT discovery", target: nil, action: nil)
    private let storageField = field("", width: 360)
    private let storageWarn = label("", secondary: true)
    private let yoloPopup = NSPopUpButton()
    private let yoloW = field("320", width: 70)
    private let yoloH = field("320", width: 70)
    private let aiEnable = NSButton(checkboxWithTitle: "Enable local AI scene descriptions (Ollama)", target: nil, action: nil)
    private let aiBase = field("http://127.0.0.1:11434")
    private let aiModel = field("moondream", width: 160)
    private var cameraRows: [CameraRow] = []
    private let camerasStack = NSStackView()

    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Frigate ANE — Setup"
        win.center()
        super.init(window: win)
        build()
        loadFromConfig()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(tab("MQTT", mqttView()))
        tabs.addTabViewItem(tab("Home Assistant", haView()))
        tabs.addTabViewItem(tab("Storage", storageView()))
        tabs.addTabViewItem(tab("Cameras", camerasView()))
        tabs.addTabViewItem(tab("Models", modelsView()))

        let save = NSButton(title: "Save & Generate Config", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), save])
        footer.orientation = .horizontal
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 16, right: 20)

        let root = NSStackView(views: [tabs, footer])
        root.orientation = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        window!.contentView!.addSubview(root)
        let cv = window!.contentView!
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: cv.topAnchor),
            root.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            tabs.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func tab(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private func mqttView() -> NSView {
        return vstack([
            label("MQTT broker", bold: true),
            label("Frigate publishes camera + detection state to MQTT (e.g. Home Assistant's Mosquitto).", secondary: true),
            formRow("Host", mqttHost),
            formRow("Port", mqttPort),
            formRow("User", mqttUser),
            formRow("Password", { mqttPass.widthAnchor.constraint(equalToConstant: 280).isActive = true; return mqttPass }()),
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
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseStorage))
        choose.bezelStyle = .rounded
        let rowS = NSStackView(views: [storageField, choose])
        rowS.spacing = 8
        return vstack([
            label("Recordings storage", bold: true),
            label("Pick the drive/folder for recordings. Use an external drive with space — and one that's actually mounted.", secondary: true),
            formRow("Path", rowS),
            storageWarn,
        ])
    }
    private func camerasView() -> NSView {
        camerasStack.orientation = .vertical
        camerasStack.alignment = .leading
        camerasStack.spacing = 6
        let add = NSButton(title: "+ Add camera", target: self, action: #selector(addCamera))
        add.bezelStyle = .rounded
        let scroll = NSScrollView()
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(camerasStack)
        camerasStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            camerasStack.topAnchor.constraint(equalTo: doc.topAnchor),
            camerasStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            camerasStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
        ])
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 660).isActive = true
        return vstack([
            label("Cameras", bold: true),
            label("Add RTSP streams. Main = recording, Sub = detection (lower res). Retention is set below.", secondary: true),
            add, scroll,
            retentionView(),
        ])
    }
    private let retCont = field("7", width: 60)
    private let retEvent = field("30", width: 60)
    private func retentionView() -> NSView {
        let s = NSStackView(views: [label("Retention:", secondary: true),
                                    label("continuous", secondary: true), retCont, label("days", secondary: true),
                                    label("· events", secondary: true), retEvent, label("days", secondary: true)])
        s.spacing = 6
        return s
    }
    private func modelsView() -> NSView {
        // populate YOLO popup from engine/models
        yoloPopup.removeAllItems()
        let modelsDir = Bundle.main.resourceURL!.appendingPathComponent("engine/models")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path) {
            for f in files.sorted() where f.hasSuffix(".onnx") { yoloPopup.addItem(withTitle: f) }
        }
        if yoloPopup.numberOfItems == 0 { yoloPopup.addItem(withTitle: "yolo.onnx") }

        let aiInstall = NSButton(title: "Install model", target: self, action: #selector(installAIModel))
        aiInstall.bezelStyle = .rounded
        let aiRow = NSStackView(views: [aiModel, aiInstall]); aiRow.spacing = 8

        return vstack([
            label("Detector model (YOLO on Apple Neural Engine)", bold: true),
            formRow("Model", yoloPopup),
            formRow("Input W×H", { let s = NSStackView(views: [yoloW, label("×"), yoloH]); s.spacing = 6; return s }()),
            label("Runs via CoreML on the ANE (CPUAndNeuralEngine).", secondary: true),
            label(" "),
            label("Local AI (optional)", bold: true),
            aiEnable,
            formRow("Base URL", aiBase),
            formRow("Vision model", aiRow),
        ])
    }

    // MARK: actions

    @objc private func chooseStorage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            storageField.stringValue = url.path
            validateStorage()
        }
    }
    private func validateStorage() {
        let p = storageField.stringValue
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
        if p.isEmpty { storageWarn.stringValue = "" }
        else if !exists { storageWarn.stringValue = "⚠︎ Path does not exist / drive not mounted." ; storageWarn.textColor = .systemOrange }
        else { storageWarn.stringValue = "✓ Available." ; storageWarn.textColor = .systemGreen }
    }
    @objc private func addCamera() { appendCamera(CameraConfig()) }
    private func appendCamera(_ cam: CameraConfig) {
        let row = CameraRow(cam)
        row.onRemove = { [weak self, weak row] in
            guard let self = self, let row = row else { return }
            self.cameraRows.removeAll { $0 === row }
            self.camerasStack.removeView(row)
        }
        cameraRows.append(row)
        camerasStack.addArrangedSubview(row)
    }
    @objc private func installAIModel() {
        commitToConfig()
        let orch = Orchestrator()
        orch.installOllamaModel { ok in
            let a = NSAlert()
            a.messageText = ok ? "Model installed." : "Could not install model (is Ollama installed?)."
            a.runModal()
        }
    }

    private func loadFromConfig() {
        let c = store.config
        mqttHost.stringValue = c.mqtt.host
        mqttPort.stringValue = String(c.mqtt.port)
        mqttUser.stringValue = c.mqtt.user
        mqttPass.stringValue = c.mqtt.password
        haDiscovery.state = c.ha.discoveryEnabled ? .on : .off
        storageField.stringValue = c.storagePath
        retCont.stringValue = String(c.retentionContinuousDays)
        retEvent.stringValue = String(c.retentionEventDays)
        yoloW.stringValue = String(c.yolo.width)
        yoloH.stringValue = String(c.yolo.height)
        aiEnable.state = c.localAI.enabled ? .on : .off
        aiBase.stringValue = c.localAI.baseURL
        aiModel.stringValue = c.localAI.model
        for cam in c.cameras { appendCamera(cam) }
        validateStorage()
    }

    private func commitToConfig() {
        store.update { c in
            c.mqtt.host = mqttHost.stringValue
            c.mqtt.port = Int(mqttPort.stringValue) ?? 1883
            c.mqtt.user = mqttUser.stringValue
            c.mqtt.password = mqttPass.stringValue
            c.mqtt.enabled = !mqttHost.stringValue.isEmpty
            c.ha.discoveryEnabled = haDiscovery.state == .on
            c.storagePath = storageField.stringValue
            c.retentionContinuousDays = Int(retCont.stringValue) ?? 7
            c.retentionEventDays = Int(retEvent.stringValue) ?? 30
            c.yolo.modelFile = yoloPopup.titleOfSelectedItem ?? "yolo.onnx"
            c.yolo.width = Int(yoloW.stringValue) ?? 320
            c.yolo.height = Int(yoloH.stringValue) ?? 320
            c.localAI.enabled = aiEnable.state == .on
            c.localAI.baseURL = aiBase.stringValue
            c.localAI.model = aiModel.stringValue
            c.cameras = cameraRows.map { $0.value }
        }
    }

    @objc private func saveTapped() {
        commitToConfig()
        do { try ConfigGenerator.writeAll(store) }
        catch { let a = NSAlert(); a.messageText = "Failed to write config: \(error)"; a.runModal(); return }
        store.update { $0.configured = true }
        let a = NSAlert()
        a.messageText = "Configuration saved."
        a.informativeText = "Frigate config written to:\n\(store.frigateConfigYAML.path)"
        a.runModal()
        onDone?()
        window?.close()
    }
}

// MARK: - Status dashboard

final class DashboardWindowController: NSWindowController {
    let engine: Engine
    let orch = Orchestrator()
    private let logView = NSTextView()
    private let detLabel = label("detector: —")
    private let stackLabel = label("stack: checking…")

    init(engine: Engine) {
        self.engine = engine
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Frigate ANE — Dashboard"
        win.center()
        super.init(window: win)
        build()
        engine.onState = { [weak self] in self?.refreshDetector() }
        engine.onLog = { [weak self] s in self?.appendLog(s) }
        orch.onProgress = { [weak self] s in self?.appendLog(s) }
        refreshDetector()
        refreshStack()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let startAll = NSButton(title: "Start All", target: self, action: #selector(startAll))
        let stop = NSButton(title: "Stop Frigate", target: self, action: #selector(stopFrigate))
        let openUI = NSButton(title: "Open Frigate UI", target: self, action: #selector(openUI))
        let setup = NSButton(title: "Setup…", target: self, action: #selector(openSetup))
        let detToggle = NSButton(title: "Start/Stop Detector", target: self, action: #selector(toggleDetector))
        for b in [startAll, stop, openUI, setup, detToggle] { b.bezelStyle = .rounded }
        let controls = NSStackView(views: [startAll, stop, detToggle, openUI, setup])
        controls.spacing = 10

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let root = vstack([
            label("Frigate ANE", bold: true),
            stackLabel, detLabel, controls, scroll,
        ], spacing: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        let cv = window!.contentView!
        cv.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: cv.topAnchor),
            root.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    private func refreshDetector() {
        detLabel.stringValue = String(format: "detector: %@ · %@ · %.1f inf/s",
            engine.running ? "running" : "stopped", engine.provider, engine.fps)
    }
    private func refreshStack() {
        orch.detect { [weak self] st in
            guard let self = self else { return }
            var parts: [String] = []
            parts.append("container CLI: \(st.containerCLI ? "✓" : "✕")")
            parts.append("image: \(st.imagePresent ? "✓" : "✕")")
            parts.append("frigate: \(st.frigateRunning ? "running" : "stopped")")
            if self.store.config.localAI.enabled { parts.append("ollama: \(st.ollamaInstalled ? "✓" : "✕")") }
            self.stackLabel.stringValue = "stack — " + parts.joined(separator: "  ·  ")
            for n in st.notes { self.appendLog("• " + n + "\n") }
        }
    }
    var store: ConfigStore { ConfigStore.shared }

    @objc private func startAll() {
        appendLog("Starting full stack…\n")
        if engine.isInstalled && !engine.running { engine.start() }
        orch.startAll { [weak self] ok in
            self?.appendLog(ok ? "✓ stack started.\n" : "✕ stack start incomplete — see notes.\n")
            self?.refreshStack()
        }
    }
    @objc private func stopFrigate() { orch.stopFrigate { [weak self] in self?.refreshStack() } }
    @objc private func toggleDetector() { engine.running ? engine.stop() : engine.start() }
    @objc private func openUI() { NSWorkspace.shared.open(URL(string: "http://localhost:8971")!) }
    @objc private func openSetup() { (NSApp.delegate as? AppDelegate)?.showSetup() }

    private func appendLog(_ s: String) {
        logView.textStorage?.append(NSAttributedString(string: s,
            attributes: [.foregroundColor: NSColor.labelColor,
                         .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]))
        if let len = logView.textStorage?.length, len > 200_000 {
            logView.textStorage?.deleteCharacters(in: NSRange(location: 0, length: len - 150_000))
        }
        logView.scrollToEndOfDocument(nil)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = Engine()
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

        if ConfigStore.shared.config.configured {
            showDashboard()
            if engine.isInstalled { engine.start() }
        } else {
            showSetup()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSetup() {
        let s = SetupWindowController()
        s.onDone = { [weak self] in self?.showDashboard() }
        setup = s
        s.showWindow(nil)
        s.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showDashboard() {
        if dashboard == nil { dashboard = DashboardWindowController(engine: engine) }
        dashboard?.showWindow(nil)
        dashboard?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func rebuildMenu() {
        let m = NSMenu()
        let head = NSMenuItem(title: "Detector: \(engine.running ? "running" : "stopped")", action: nil, keyEquivalent: "")
        head.isEnabled = false
        m.addItem(head)
        m.addItem(.separator())
        add(m, "Dashboard", #selector(menuDashboard))
        add(m, "Setup…", #selector(menuSetup))
        add(m, engine.running ? "Stop Detector" : "Start Detector", #selector(menuToggle))
        m.addItem(.separator())
        add(m, "Quit", #selector(menuQuit), key: "q")
        statusItem.menu = m
    }
    private func add(_ m: NSMenu, _ title: String, _ sel: Selector, key: String = "") {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        m.addItem(i)
    }
    @objc func menuDashboard() { showDashboard() }
    @objc func menuSetup() { showSetup() }
    @objc func menuToggle() { engine.running ? engine.stop() : engine.start() }
    @objc func menuQuit() { engine.autoRestart = false; engine.stop(); NSApp.terminate(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ note: Notification) { engine.autoRestart = false; engine.stop() }
}
