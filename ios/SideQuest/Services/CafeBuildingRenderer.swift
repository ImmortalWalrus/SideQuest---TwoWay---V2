import WebKit
import UIKit
import MapKit

@MainActor
final class CafeBuildingRenderer: NSObject {
    static let shared = CafeBuildingRenderer()

    private(set) var prerenderedImages: [Int: UIImage] = [:]
    private var webView: WKWebView?
    private var isRendering = false

    var isReady: Bool { prerenderedImages.count >= 24 }

    func image(forBearing bearing: Double) -> UIImage? {
        guard isReady else { return nil }
        let normalized = ((Int(bearing.rounded()) % 360) + 360) % 360
        let snapped = ((normalized + 7) / 15) * 15 % 360
        return prerenderedImages[snapped] ?? prerenderedImages[0]
    }

    func prerenderIfNeeded() {
        guard !isReady, !isRendering else { return }
        isRendering = true
        Task { await performPrerender() }
    }

    private func performPrerender() async {
        defer { isRendering = false }

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(CafeBuildingSchemeHandler(), forURLScheme: "sidequest-building")
        let readyHandler = BuildingReadyMessageHandler()
        config.userContentController.add(readyHandler, name: "buildingState")

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            wv.frame = CGRect(x: -500, y: -500, width: 256, height: 256)
            window.addSubview(wv)
        }

        webView = wv

        guard let url = URL(string: "sidequest-building://host/index.html") else {
            cleanupWebView(wv)
            return
        }
        wv.load(URLRequest(url: url))

        for _ in 0..<200 {
            if readyHandler.isReady { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard readyHandler.isReady else {
            cleanupWebView(wv)
            return
        }

        for angle in stride(from: 0, to: 360, by: 15) {
            do {
                _ = try await wv.evaluateJavaScript("window.setAngle(\(angle))")
            } catch {}
            try? await Task.sleep(for: .milliseconds(120))

            let snapConfig = WKSnapshotConfiguration()
            snapConfig.snapshotWidth = NSNumber(value: 192)
            if let image = try? await wv.takeSnapshot(configuration: snapConfig) {
                prerenderedImages[angle] = image
            }
        }

        cleanupWebView(wv)
    }

    private func cleanupWebView(_ wv: WKWebView) {
        wv.removeFromSuperview()
        wv.configuration.userContentController.removeScriptMessageHandler(forName: "buildingState")
        webView = nil
    }

    static func estimateRoadBearing(at coordinate: CLLocationCoordinate2D) -> Double {
        let latGrid = coordinate.latitude * 1000
        let lonGrid = coordinate.longitude * 1000
        let latFrac = abs(latGrid - latGrid.rounded())
        let lonFrac = abs(lonGrid - lonGrid.rounded())
        if lonFrac < latFrac {
            return 0
        } else {
            return 90
        }
    }

    static func fetchRoadBearing(for coordinate: CLLocationCoordinate2D) async -> Double {
        let offset = CLLocationCoordinate2D(
            latitude: coordinate.latitude + 0.0007,
            longitude: coordinate.longitude
        )
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: offset))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            if let route = response.routes.first {
                let points = route.polyline.points()
                let count = route.polyline.pointCount
                if count >= 2 {
                    let p1 = points[count - 2].coordinate
                    let p2 = points[count - 1].coordinate
                    let dLon = (p2.longitude - p1.longitude) * .pi / 180
                    let lat1 = p1.latitude * .pi / 180
                    let lat2 = p2.latitude * .pi / 180
                    let y = sin(dLon) * cos(lat2)
                    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
                    var bearing = atan2(y, x) * 180 / .pi
                    if bearing < 0 { bearing += 360 }
                    return bearing
                }
            }
        } catch {}

        return estimateRoadBearing(at: coordinate)
    }
}

final class BuildingReadyMessageHandler: NSObject, WKScriptMessageHandler {
    var isReady = false

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            if let body = message.body as? String, body == "ready" {
                self.isReady = true
            }
        }
    }
}

@MainActor
final class CafeBuildingSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        switch url.path {
        case "/index.html":
            let data = Data(Self.html.utf8)
            let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        case let path where path.hasPrefix("/models/"):
            let name = url.deletingPathExtension().lastPathComponent
            guard let fileURL = Bundle.main.url(forResource: name, withExtension: "glb", subdirectory: "Resources/Buildings")
                    ?? Bundle.main.url(forResource: name, withExtension: "glb"),
                  let data = try? Data(contentsOf: fileURL) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let response = URLResponse(url: url, mimeType: "model/gltf-binary", expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        default:
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static let html: String = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}canvas{display:block;width:100%;height:100%}</style>
<script type="importmap">
{"imports":{"three":"https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js","three/addons/":"https://cdn.jsdelivr.net/npm/three@0.170.0/examples/jsm/"}}
</script>
</head>
<body>
<canvas id="c"></canvas>
<script type="module">
import * as THREE from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';

const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({canvas, alpha:true, antialias:true});
renderer.setPixelRatio(2);
renderer.setClearColor(0x000000, 0);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.3;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
const fov = 28;
const camera = new THREE.PerspectiveCamera(fov, 1, 0.01, 200);

const elevationDeg = 35;
const elevationRad = elevationDeg * Math.PI / 180;

scene.add(new THREE.AmbientLight(0x808898, 0.7));
const hemi = new THREE.HemisphereLight(0x90a0c0, 0x101418, 0.5);
hemi.position.set(0, 10, 0);
scene.add(hemi);

const key = new THREE.DirectionalLight(0xfff4e0, 3.0);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.bias = -0.0004;
key.shadow.normalBias = 0.03;
key.shadow.radius = 4;
scene.add(key);
scene.add(key.target);

const fill = new THREE.DirectionalLight(0xc0d0f0, 0.8);
scene.add(fill);

const rim = new THREE.DirectionalLight(0xe0e8ff, 0.6);
scene.add(rim);

const floorGeo = new THREE.PlaneGeometry(30, 30);
const floorMat = new THREE.ShadowMaterial({opacity: 0.4});
const floorMesh = new THREE.Mesh(floorGeo, floorMat);
floorMesh.rotation.x = -Math.PI / 2;
floorMesh.receiveShadow = true;
scene.add(floorMesh);

let model = null;

function resize() {
    const w = Math.max(canvas.clientWidth, 1);
    const h = Math.max(canvas.clientHeight, 1);
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
}
resize();

window.setAngle = function(deg) {
    if (!model) return;
    model.rotation.y = THREE.MathUtils.degToRad(deg);
    renderer.render(scene, camera);
};

const origin = new URL(location.href).origin;
new GLTFLoader().load(origin + '/models/cozy_corner_cafe.glb', function(gltf) {
    model = gltf.scene;
    model.traverse(function(n) {
        if (!n.isMesh) return;
        n.frustumCulled = false;
        n.castShadow = true;
        n.receiveShadow = false;
    });
    scene.add(model);

    model.updateWorldMatrix(true, true);
    var box = new THREE.Box3().setFromObject(model);
    var center = box.getCenter(new THREE.Vector3());
    var size = box.getSize(new THREE.Vector3());

    model.position.x -= center.x;
    model.position.y -= box.min.y;
    model.position.z -= center.z;

    var h = size.y || 1;
    var w = Math.max(size.x, size.z) || 1;
    var halfFov = (fov * 0.5) * Math.PI / 180;
    var fitH = h * 1.3;
    var dist = (fitH * 0.5) / Math.tan(halfFov);

    camera.position.set(0, dist * Math.sin(elevationRad), dist * Math.cos(elevationRad));
    camera.lookAt(0, h * 0.3, 0);
    camera.updateProjectionMatrix();

    key.position.set(-w * 2.5, h * 3.5, w * 2.0);
    key.target.position.set(0, 0, 0);
    var sc = key.shadow.camera;
    sc.left = -w * 4; sc.right = w * 4;
    sc.bottom = -w * 4; sc.top = h * 3;
    sc.near = 0.1; sc.far = h * 12;
    sc.updateProjectionMatrix();

    fill.position.set(w * 2, h * 1.5, -w);
    rim.position.set(w * 1.5, h * 2.5, -w * 2);

    renderer.render(scene, camera);
    try { window.webkit.messageHandlers.buildingState.postMessage('ready'); } catch(e) {}
});
</script>
</body>
</html>
"""
}
