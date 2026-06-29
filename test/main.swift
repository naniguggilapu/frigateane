// Headless test: two cameras with the SAME name must produce unique YAML keys.
import Foundation

var c = AppConfig()
c.storagePath = "/tmp/rec"
var a = CameraConfig(); a.name = "camera"; a.streamURL = "rtsp://10.0.0.5:554/a"
var b = CameraConfig(); b.name = "camera"; b.streamURL = "rtsp://10.0.0.5:554/b"
var empty = CameraConfig(); empty.name = "blank"; empty.streamURL = ""   // should be skipped
c.cameras = [a, b, empty]

let yaml = ConfigGenerator.frigateYAML(c)
print(yaml)
print("=== camera-key count ===")
let keys = yaml.split(separator: "\n").filter { $0.hasPrefix("  ") && $0.hasSuffix(":") && !$0.contains(" ") }
print(keys.joined(separator: " "))
