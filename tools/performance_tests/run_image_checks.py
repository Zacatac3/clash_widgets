"""Run production image helpers against built assets in an isolated simulator app.
Requires a booted simulator and a simulator build of Clashboard.
python3 tools/performance_tests/run_image_checks.py /tmp/clashboard-performance-build/Build/Products/Debug-iphonesimulator/Clashboard.app
"""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
app = Path(sys.argv[1])
assets = app / 'Assets.car'
assert assets.exists(), assets

def between(s, a, b):
    return s[s.index(a):s.index(b)]

progress = (root / 'clash_widgets/ContentView/ProgressView.swift').read_text()
cache = between(progress, 'nonisolated final class ProgressImageCache:', '\n#endif\n\nprivate enum ProgressStructureImageCache')
processing = between(progress, 'private enum ProgressStructureImageCache', 'private struct ProgressBadgeFlow:')
content = (root / 'clash_widgets/ContentView/ContentView.swift').read_text()
badges = between(content, 'nonisolated private final class TownHallBadgeCache:', '\nstruct ClanBadgeView:')
source = 'import UIKit\n' + cache + '\n' + processing + '\n' + badges + r'''
@main
class CheckApp: UIResponder, UIApplicationDelegate {
 func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
  let config = UISceneConfiguration(name: "Checks", sessionRole: session.role)
  config.delegateClass = CheckScene.self
  return config
 }
}
class CheckScene: UIResponder, UIWindowSceneDelegate {
 var window: UIWindow?
 func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
  window = UIWindow(windowScene: scene as! UIWindowScene)
  window?.rootViewController = UIViewController()
  window?.makeKeyAndVisible()
  Task { @MainActor in
   for level in [13, 18] {
    let source = UIImage(named: "town_hall/th\(level)")!
    precondition(source.cgImage!.width == 4096)
    for scale: CGFloat in [1, 2, 3] {
     let image = await TownHallBadgeCache.shared.image(level: level, scale: scale)!
     let cached = await TownHallBadgeCache.shared.image(level: level, scale: scale)!
     precondition(image === cached, "Warm badges must reuse the thumbnail")
     let pixels = image.cgImage!
     precondition(pixels.width <= Int(48 * scale) && pixels.height <= Int(48 * scale))
     precondition(abs(Double(pixels.width) / Double(pixels.height) - Double(source.size.width / source.size.height)) < 0.03)
     precondition(image.imageOrientation == source.imageOrientation)
     print("Badge TH\(level) @\(scale)x: \(pixels.width)x\(pixels.height), \(pixels.bytesPerRow * pixels.height) bytes")
    }
   }
   let missing = await TownHallBadgeCache.shared.image(level: 0, scale: 3)
   precondition(missing == nil)
   let name = "buildings_home/archer_tower"
   let images = await withTaskGroup(of: UIImage?.self, returning: [UIImage].self) { group in
    for _ in 0..<40 { group.addTask { await ProgressStructureImageCache.loadImage(named: name) } }
    var results: [UIImage] = []
    for await image in group { if let image { results.append(image) } }
    return results
   }
   precondition(images.count == 40)
   precondition(images.allSatisfy { $0 === images[0] }, "Concurrent requests must share a cached image")
   let reference = ProgressStructureImageCache.trimmedImage(named: name)!
   precondition(images[0].pngData() == reference.pngData())
   let cancelled = Task { await ProgressStructureImageCache.loadImage(named: name) }
   cancelled.cancel()
   let cancelledImage = await cancelled.value
   precondition(cancelledImage == nil, "A cancelled request must not process an image")
   let unknown = await ProgressStructureImageCache.loadImage(named: "missing-performance-fixture")
   precondition(unknown == nil)
   print("PASS: production image helpers; badge size/aspect/cache/fallback and concurrent/cancelled Progress requests")
   fflush(stdout)
   exit(0)
  }
 }
}
'''
identifier = 'com.clashboard.performance-image-checks'
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '-j']))
device = next(d['udid'] for group in devices['devices'].values() for d in group if d['state'] == 'Booted')
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='clashboard-image-checks-') as directory:
    temp = Path(directory)
    harness = temp / 'ImageChecks.app'
    harness.mkdir()
    swift = temp / 'checks.swift'
    swift.write_text(source)
    shutil.copy2(assets, harness / 'Assets.car')
    (harness / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'ImageChecks',
        'CFBundleName': 'ImageChecks', 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
        'MinimumOSVersion': '18.0', 'UILaunchScreen': {},
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
    }))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-sdk', sdk,
                    '-target', 'arm64-apple-ios18.0-simulator', str(swift), '-o', str(harness / 'ImageChecks')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(harness)], check=True)
    subprocess.run(['xcrun', 'simctl', 'install', device, str(harness)], check=True)
    try:
        result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', device, identifier],
                                capture_output=True, text=True, timeout=60)
        print(result.stdout)
        if result.returncode or 'PASS: production image helpers' not in result.stdout:
            print(result.stderr)
            raise SystemExit('Image checks failed')
    finally:
        subprocess.run(['xcrun', 'simctl', 'uninstall', device, identifier], check=True)
