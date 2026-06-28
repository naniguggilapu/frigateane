// Headless test of ConfigGenerator (compiled with Config.swift + ConfigGenerator.swift).
import Foundation

var c = AppConfig()
c.mqtt.host = "192.168.1.50"; c.mqtt.user = "frigate"; c.mqtt.password = "secret"
c.storagePath = "/Volumes/CCTV/recordings"
c.retentionContinuousDays = 5; c.retentionEventDays = 21
var cam = CameraConfig(); cam.name = "front door"
cam.streamURL = "rtsp://10.0.0.5:554/main"; cam.subStreamURL = "rtsp://10.0.0.5:554/sub"
cam.trackedObjects = ["person", "car"]; cam.detectFPS = 8; cam.detectWidth = 640; cam.detectHeight = 360
cam.extraYAML = "zones:\n  driveway:\n    coordinates: 0,0,100,0,100,100"
c.cameras = [cam]
c.localAI.enabled = true; c.localAI.model = "moondream"

print(ConfigGenerator.frigateYAML(c))
