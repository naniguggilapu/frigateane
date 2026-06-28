// Headless test of ConfigGenerator (compiled with Config.swift + ConfigGenerator.swift).
import Foundation

var c = AppConfig()
c.mqtt.host = "192.168.1.50"; c.mqtt.user = "frigate"; c.mqtt.password = "secret"
c.ha.discoveryEnabled = true
c.storagePath = "/Volumes/CCTV/recordings"
c.retentionContinuousDays = 5; c.retentionEventDays = 21
var cam = CameraConfig(); cam.name = "front_door"
cam.streamURL = "rtsp://10.0.0.5:554/main"; cam.subStreamURL = "rtsp://10.0.0.5:554/sub"
c.cameras = [cam]
c.localAI.enabled = true; c.localAI.model = "moondream"

print("===== config.yaml =====")
print(ConfigGenerator.frigateYAML(c))
print("===== start-frigate.sh =====")
print(ConfigGenerator.startScript(c, configDir: "/Users/x/Library/Application Support/FrigateANE/frigate-config"))
