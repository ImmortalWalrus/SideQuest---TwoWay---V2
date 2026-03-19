import Foundation
import UniformTypeIdentifiers
import WebKit

nonisolated enum CharacterPreviewSchemeError: Error {
    case invalidRequest
    case fileNotFound
}

final class CharacterPreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme: String = "sidequest-character-preview"
    nonisolated(unsafe) private static let modelDataCache = NSCache<NSString, NSData>()
    nonisolated(unsafe) private static let bundledAssetDataCache = NSCache<NSString, NSData>()
    private static let bundledAssetResourceMap: [String: String] = [
        "/preview-deps.bundle.js": "preview-deps.bundle.js",
        "/three/three.module.js": "three.module.min.js",
        "/three/addons/controls/OrbitControls.js": "OrbitControls.min.js",
        "/three/addons/loaders/GLTFLoader.js": "GLTFLoader.min.js",
        "/three/addons/utils/BufferGeometryUtils.js": "BufferGeometryUtils.js"
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url else {
                throw CharacterPreviewSchemeError.invalidRequest
            }

            let responseData: (mimeType: String, data: Data)
            switch url.path {
            case "/index.html":
                responseData = ("text/html", Data(Self.previewHTML.utf8))
            case let path where path.hasPrefix("/models/"):
                let fileName: String = url.deletingPathExtension().lastPathComponent
                let model = try Self.cachedModel(named: fileName)
                responseData = (Self.mimeType(for: model.fileURL), model.data)
            case let path where Self.bundledAssetResourceMap[path] != nil:
                let asset = try Self.cachedBundledAsset(forRequestPath: path)
                responseData = (Self.mimeType(for: asset.fileURL), asset.data)
            default:
                throw CharacterPreviewSchemeError.fileNotFound
            }

            let response = URLResponse(
                url: url,
                mimeType: responseData.mimeType,
                expectedContentLength: responseData.data.count,
                textEncodingName: responseData.mimeType == "text/html" ? "utf-8" : nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(responseData.data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }

    nonisolated private static func cachedModel(named fileName: String) throws -> (fileURL: URL, data: Data) {
        guard let fileURL = CharacterModelService.modelURL(named: fileName) else {
            throw CharacterPreviewSchemeError.fileNotFound
        }

        let cacheKey = fileURL.absoluteString as NSString
        if let cached = modelDataCache.object(forKey: cacheKey) {
            return (fileURL, Data(referencing: cached))
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        modelDataCache.setObject(data as NSData, forKey: cacheKey)
        return (fileURL, data)
    }

    nonisolated private static func cachedBundledAsset(forRequestPath requestPath: String) throws -> (fileURL: URL, data: Data) {
        guard let fileName = bundledAssetResourceMap[requestPath],
              let fileURL = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            throw CharacterPreviewSchemeError.fileNotFound
        }

        let cacheKey = fileURL.absoluteString as NSString
        if let cached = bundledAssetDataCache.object(forKey: cacheKey) {
            return (fileURL, Data(referencing: cached))
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        bundledAssetDataCache.setObject(data as NSData, forKey: cacheKey)
        return (fileURL, data)
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "glb":
            return "model/gltf-binary"
        case "html":
            return "text/html"
        default:
            return UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    private static let previewHTML: String = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
<style>
html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}
canvas{display:block;width:100%;height:100%;touch-action:none;outline:none}
</style>
</head>
<body>
<canvas id="c"></canvas>
<script>
window._dbg = function(){};
</script>
<script type="module">
import { THREE, OrbitControls, GLTFLoader } from './preview-deps.bundle.js';

const P = new URL(location.href);
const modelName = P.searchParams.get('model') || 'Gunslinger';
const allowsControl = P.searchParams.get('controls') === '1';
const autoRotate = P.searchParams.get('rotate') === '1';
const framing = P.searchParams.get('framing') || 'fullBody';
const yawDeg = parseFloat(P.searchParams.get('yaw') || '0');
const sceneStyle = P.searchParams.get('sceneStyle') || 'standard';
const isHero = sceneStyle === 'heroProfile' || sceneStyle === 'homeHero';
const isHomeHero = sceneStyle === 'homeHero';

const notify = v => { try { window.webkit.messageHandlers.previewState.postMessage(v); } catch(e){} };
notify({state:'init', model:modelName, hero:isHero});

const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({
    canvas,
    alpha: true,
    antialias: true,
    logarithmicDepthBuffer: true,
    powerPreference: 'high-performance'
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setClearColor(0x000000, 0);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = isHero ? 0.98 : 1.1;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.VSMShadowMap;
renderer.physicallyCorrectLights = true;

const scene = new THREE.Scene();
const fov = isHero ? 32 : 30;
const camera = new THREE.PerspectiveCamera(fov, 1, 0.01, 100);

const ctrl = new OrbitControls(camera, canvas);
ctrl.enableDamping = true;
ctrl.dampingFactor = 0.08;
ctrl.enablePan = false;
ctrl.enableZoom = false;
ctrl.enableRotate = allowsControl && !isHero;
ctrl.autoRotate = autoRotate;
ctrl.autoRotateSpeed = 1.2;
ctrl.minPolarAngle = Math.PI * 0.35;
ctrl.maxPolarAngle = Math.PI * 0.6;

if (isHero) {
    const ambient = new THREE.AmbientLight(0x404048, 0.18);
    scene.add(ambient);

    const hemi = new THREE.HemisphereLight(0x586070, 0x0a0c10, 0.14);
    hemi.position.set(0, 1, 0);
    scene.add(hemi);
} else {
    const ambient = new THREE.AmbientLight(0x606070, 0.45);
    scene.add(ambient);

    const hemi = new THREE.HemisphereLight(0x8090b0, 0x0c0e14, 0.5);
    hemi.position.set(0, 1, 0);
    scene.add(hemi);
}

const sun = new THREE.DirectionalLight(
    isHero ? 0xfff2e0 : 0xffeedd,
    isHero ? 3.2 : 2.8
);
sun.castShadow = true;
sun.shadow.mapSize.set(isHero ? 4096 : 2048, isHero ? 4096 : 2048);
if (isHero) {
    sun.shadow.bias = -0.00025;
    sun.shadow.normalBias = 0.025;
    sun.shadow.radius = 8;
    sun.shadow.blurSamples = 24;
} else {
    sun.shadow.bias = -0.0002;
    sun.shadow.normalBias = 0.012;
    sun.shadow.radius = 5;
    sun.shadow.blurSamples = 16;
}
scene.add(sun);
scene.add(sun.target);

const fill = new THREE.DirectionalLight(
    isHero ? 0xa0b4d0 : 0xb0c8e8,
    isHero ? 0.55 : 0.9
);
fill.castShadow = false;
scene.add(fill);
scene.add(fill.target);

const rim = new THREE.DirectionalLight(
    isHero ? 0xb8c4e0 : 0xd0d8ff,
    isHero ? 0.40 : 1.5
);
rim.castShadow = false;
scene.add(rim);
scene.add(rim.target);

let bounce = null;
let footLift = null;
if (isHero) {
    bounce = new THREE.PointLight(0xffe8c8, 0.28, 0, 2);
    scene.add(bounce);
    footLift = new THREE.SpotLight(0xffddb8, 0.7, 0, 0.9, 1.0, 2);
    footLift.castShadow = false;
    scene.add(footLift);
    scene.add(footLift.target);
}

let floorMesh, contactMesh = null, castShadowMesh = null;
if (isHero) {
    const floorGeo = new THREE.CircleGeometry(80, 96);
    const floorMat = new THREE.ShadowMaterial({ opacity: 0.30 });
    floorMesh = new THREE.Mesh(floorGeo, floorMat);
    floorMesh.rotation.x = -Math.PI / 2;
    floorMesh.position.y = 0;
    floorMesh.receiveShadow = true;
    scene.add(floorMesh);

    const cSize = 256;
    const cCanvas = document.createElement('canvas');
    cCanvas.width = cSize; cCanvas.height = cSize;
    const cCtx = cCanvas.getContext('2d');
    const cGrad = cCtx.createRadialGradient(cSize/2, cSize/2, 0, cSize/2, cSize/2, cSize/2);
    cGrad.addColorStop(0, 'rgba(0,0,0,0.22)');
    cGrad.addColorStop(0.30, 'rgba(0,0,0,0.14)');
    cGrad.addColorStop(0.65, 'rgba(0,0,0,0.04)');
    cGrad.addColorStop(1, 'rgba(0,0,0,0)');
    cCtx.fillStyle = cGrad;
    cCtx.fillRect(0, 0, cSize, cSize);
    const contactTex = new THREE.CanvasTexture(cCanvas);
    const contactGeo = new THREE.PlaneGeometry(1, 1);
    const contactMat = new THREE.MeshBasicMaterial({
        map: contactTex,
        transparent: true,
        depthWrite: false,
        blending: THREE.NormalBlending
    });
    contactMesh = new THREE.Mesh(contactGeo, contactMat);
    contactMesh.rotation.x = -Math.PI / 2;
    contactMesh.position.y = 0.002;
    scene.add(contactMesh);

    const csSize = 256;
    const csCanvas = document.createElement('canvas');
    csCanvas.width = csSize; csCanvas.height = csSize;
    const csCtx = csCanvas.getContext('2d');
    const csGrad = csCtx.createRadialGradient(csSize*0.38, csSize*0.4, 0, csSize*0.45, csSize*0.45, csSize*0.5);
    csGrad.addColorStop(0, 'rgba(0,0,0,0.16)');
    csGrad.addColorStop(0.30, 'rgba(0,0,0,0.09)');
    csGrad.addColorStop(0.65, 'rgba(0,0,0,0.02)');
    csGrad.addColorStop(1, 'rgba(0,0,0,0)');
    csCtx.fillStyle = csGrad;
    csCtx.fillRect(0, 0, csSize, csSize);
    const castTex = new THREE.CanvasTexture(csCanvas);
    const castGeo = new THREE.PlaneGeometry(1, 1);
    const castMat = new THREE.MeshBasicMaterial({
        map: castTex,
        transparent: true,
        depthWrite: false,
        blending: THREE.NormalBlending
    });
    castShadowMesh = new THREE.Mesh(castGeo, castMat);
    castShadowMesh.rotation.x = -Math.PI / 2;
    castShadowMesh.position.y = 0.001;
    scene.add(castShadowMesh);
} else {
    const floorGeo = new THREE.PlaneGeometry(1200, 1200);
    const floorMat = new THREE.ShadowMaterial({ opacity: 0.45 });
    floorMesh = new THREE.Mesh(floorGeo, floorMat);
    floorMesh.rotation.x = -Math.PI / 2;
    floorMesh.position.y = 0;
    floorMesh.receiveShadow = true;
    scene.add(floorMesh);
}

const texSlots = ['map','alphaMap','aoMap','bumpMap','emissiveMap','metalnessMap','normalMap','roughnessMap'];
const seen = new WeakSet();
function crispTex(tex) {
    if (!tex || seen.has(tex)) return;
    tex.generateMipmaps = false;
    tex.minFilter = THREE.NearestFilter;
    tex.magFilter = THREE.NearestFilter;
    tex.anisotropy = 1;
    tex.needsUpdate = true;
    seen.add(tex);
}
function crispMat(mat) {
    if (!mat) return;
    texSlots.forEach(s => crispTex(mat[s]));
    mat.needsUpdate = true;
}

const clock = new THREE.Clock();
let mixer = null;
let model = null;
let raf = 0;

function layout(m) {
    m.updateWorldMatrix(true, true);
    const b = new THREE.Box3().setFromObject(m);
    const c = b.getCenter(new THREE.Vector3());
    m.position.x -= c.x;
    m.position.y -= b.min.y;
    m.position.z -= c.z;
    m.updateWorldMatrix(true, true);

    const b2 = new THREE.Box3().setFromObject(m);
    const s = b2.getSize(new THREE.Vector3());
    const h = s.y || 1, w = s.x || 1, d = s.z || 1;
    const asp = Math.max(canvas.clientWidth,1) / Math.max(canvas.clientHeight,1);
    const hfov = THREE.MathUtils.degToRad(fov) * 0.5;

    if (isHero) {
        if (isHomeHero) {
            sun.position.set(w * 2.8, h * 3.2, d * 2.2);
            sun.target.position.set(0, h * 0.38, 0);

            fill.position.set(-w * 0.4, h * 0.85, d * 3.5);
            fill.target.position.set(0, h * 0.36, 0);

            rim.position.set(-w * 2.4, h * 2.2, -d * 2.0);
            rim.target.position.set(0, h * 0.44, 0);
        } else {
            sun.position.set(-w * 2.8, h * 3.2, d * 2.2);
            sun.target.position.set(0, h * 0.38, 0);

            fill.position.set(w * 0.4, h * 0.85, d * 3.5);
            fill.target.position.set(0, h * 0.36, 0);

            rim.position.set(w * 2.4, h * 2.2, -d * 2.0);
            rim.target.position.set(0, h * 0.44, 0);
        }

        if (bounce) {
            bounce.position.set(0, h * 0.10, d * 1.2);
        }
        if (footLift) {
            footLift.position.set(0, h * 0.30, d * 1.8);
            footLift.target.position.set(0, h * 0.03, 0);
        }

        const sc = sun.shadow.camera;
        const sw = Math.max(w, d) * 2.0;
        sc.left = isHomeHero ? -sw * 2.8 : -sw * 1.5;
        sc.right = isHomeHero ? sw * 1.5 : sw * 2.8;
        sc.bottom = -sw * 1.5;
        sc.top = h * 1.5;
        sc.near = 0.1;
        sc.far = h * 10;
        sc.updateProjectionMatrix();

        if (contactMesh) {
            const footW = w * 1.2;
            const footD = d * 1.4;
            contactMesh.scale.set(footW, footD, 1);
            contactMesh.position.set(0, 0.002, d * 0.05);
        }
        if (castShadowMesh) {
            const csW = w * 3.5;
            const csD = d * 4.0;
            castShadowMesh.scale.set(csW, csD, 1);
            castShadowMesh.position.set(isHomeHero ? -w * 0.6 : w * 0.6, 0.001, -d * 0.8);
        }
    } else {
        sun.position.set(-w * 5.0, h * 1.8, d * 3.0);
        sun.target.position.set(0, h * 0.25, 0);

        fill.position.set(w * 2.5, h * 1.2, d * 2.0);
        fill.target.position.set(0, h * 0.4, 0);

        rim.position.set(w * 2.0, h * 2.0, -d * 2.5);
        rim.target.position.set(0, h * 0.5, 0);

        const sc = sun.shadow.camera;
        const shadowSpan = Math.max(w, d) * 12.0;
        sc.left = -shadowSpan; sc.right = shadowSpan * 2.0;
        sc.bottom = -shadowSpan * 4.0; sc.top = h * 2.5;
        sc.near = 0.1; sc.far = h * 16;
        sc.updateProjectionMatrix();
    }

    if (framing === 'headshot') {
        const ph = h * 0.42;
        const dist = (ph * 0.55) / Math.tan(hfov);
        const tY = h * 0.78;
        camera.aspect = asp;
        camera.near = 0.01; camera.far = dist * 10;
        camera.updateProjectionMatrix();
        camera.position.set(dist * 0.12, tY, dist * 0.95);
        ctrl.target.set(0, tY, 0);
        ctrl.update();
        return;
    }

    if (framing === 'upperBody') {
        const ph = h * 0.68;
        const dist = (ph * 0.55) / Math.tan(hfov);
        const tY = h * 0.60;
        camera.aspect = asp;
        camera.near = 0.01; camera.far = dist * 10;
        camera.updateProjectionMatrix();
        camera.position.set(dist * 0.03, tY - h * 0.015, dist * 0.98);
        ctrl.target.set(0, tY, 0);
        ctrl.update();
        return;
    }

    if (framing === 'portrait') {
        const ph = h * 0.75;
        const dist = (ph * 0.55) / Math.tan(hfov);
        const tY = h * 0.52;
        camera.aspect = asp;
        camera.near = 0.01; camera.far = dist * 10;
        camera.updateProjectionMatrix();
        camera.position.set(dist * 0.08, tY, dist * 0.95);
        ctrl.target.set(0, tY, 0);
        ctrl.update();
        return;
    }

    if (isHero) {
        const padH = h * 1.45;
        const padW = w * 1.1;
        const visW = padH * asp;
        const fH = padW > visW ? padW / asp : padH;
        const dist = (fH * 0.5) / Math.tan(hfov);
        const tY = h * 0.38;
        camera.aspect = asp;
        camera.near = 0.01; camera.far = dist * 10;
        camera.updateProjectionMatrix();
        camera.position.set(0, tY + h * 0.44, dist);
        ctrl.target.set(0, tY, 0);
        ctrl.update();
    } else {
        const padH = h * 1.4;
        const padW = w * 1.1;
        const visW = padH * asp;
        const fH = padW > visW ? padW / asp : padH;
        const dist = (fH * 0.5) / Math.tan(hfov);
        const tY = h * 0.48;
        camera.aspect = asp;
        camera.near = 0.01; camera.far = dist * 10;
        camera.updateProjectionMatrix();
        camera.position.set(0, tY + h * 0.28, dist);
        ctrl.target.set(0, tY - h * 0.02, 0);
        ctrl.update();
    }
}

function resize() {
    const w = Math.max(canvas.clientWidth, 1);
    const h = Math.max(canvas.clientHeight, 1);
    renderer.setSize(w, h, false);
    if (model) layout(model);
}

var _paused = false;
function tick() {
    if (_paused) return;
    raf = requestAnimationFrame(tick);
    const dt = clock.getDelta();
    if (mixer) mixer.update(dt);
    ctrl.update();
    renderer.render(scene, camera);
}
window._pause = function() {
    _paused = true;
    cancelAnimationFrame(raf);
};
window._resume = function() {
    if (!_paused) return;
    _paused = false;
    clock.getDelta();
    tick();
};

resize();
window.addEventListener('resize', resize);

const baseOrigin = P.origin + (P.pathname.includes('/') ? P.pathname.substring(0, P.pathname.lastIndexOf('/')) : '');
const modelURL = baseOrigin + '/models/' + encodeURIComponent(modelName) + '.glb';
new GLTFLoader().load(modelURL, gltf => {
    model = gltf.scene;
    model.rotation.y = THREE.MathUtils.degToRad(yawDeg);
    model.traverse(n => {
        if (!n.isMesh) return;
        n.frustumCulled = false;
        n.castShadow = true;
        n.receiveShadow = false;
        const mats = Array.isArray(n.material) ? n.material : [n.material];
        mats.forEach(m => {
            crispMat(m);
            if (m) {
                m.polygonOffset = true;
                m.polygonOffsetFactor = 1;
                m.polygonOffsetUnits = 1;
            }
        });
    });
    scene.add(model);
    layout(model);

    if (gltf.animations.length > 0) {
        mixer = new THREE.AnimationMixer(model);
        gltf.animations.forEach(clip => {
            const a = mixer.clipAction(clip);
            a.setLoop(THREE.LoopRepeat, Infinity);
            a.play();
        });
    }

    tick();

    requestAnimationFrame(() => { notify('ready'); });
}, undefined, err => {
    notify({state:'loadError', error: String(err)});
});

window.addEventListener('pagehide', () => { window._pause(); ctrl.dispose(); });
</script>
</body>
</html>
"""
}
