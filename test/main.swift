// Headless test of ConfigGenerator (compiled with Config.swift + ConfigGenerator.swift).
import Foundation

var c = AppConfig()
c.storagePath = "/Volumes/CCTV/recordings"
var cam = CameraConfig()
cam.name = "front door"; cam.friendlyName = "Front Door"; cam.uiOrder = 2
cam.streamURL = "rtsp://10.0.0.5:554/main"; cam.subStreamURL = "rtsp://10.0.0.5:554/sub"
cam.rtspUser = "admin"; cam.rtspPassword = "p@ss/word"
cam.trackedObjects = ["person", "car"]; cam.detectFPS = 8
c.cameras = [cam]

print(ConfigGenerator.frigateYAML(c))
