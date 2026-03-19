import AVFoundation
import Vision

@Observable
class ReadingCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "readingVideoQueue")
    nonisolated(unsafe) private var _frameSkip: Int = 0

    private(set) var faceDetected: Bool = false
    private(set) var bookDetected: Bool = false
    private(set) var gazeOnBook: Bool = false
    private(set) var horizontalScanDetected: Bool = false
    private(set) var lookingAway: Bool = false
    private(set) var faceConfidence: Float = 0
    private(set) var totalFramesProcessed: Int = 0
    private(set) var framesWithBook: Int = 0
    private(set) var framesWithGaze: Int = 0
    private(set) var framesWithScan: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var updateCounter: Int = 0
    private(set) var isConfigured: Bool = false
    private(set) var bookBoundingBox: CGRect = .zero
    private(set) var bookIsStill: Bool = false

    nonisolated(unsafe) private var _lastGazeX: Double = 0
    nonisolated(unsafe) private var _gazeXHistory: [Double] = []
    nonisolated(unsafe) private var _lastBookBox: CGRect = .zero
    nonisolated(unsafe) private var _bookStillFrames: Int = 0
    nonisolated(unsafe) private var _lookAwayFrames: Int = 0
    nonisolated(unsafe) private var _gazeDownHistory: [Bool] = []
    nonisolated(unsafe) private var _eyeOpenHistory: [Bool] = []
    nonisolated(unsafe) private var _faceHistory: [Bool] = []
    nonisolated(unsafe) private var _bookHistory: [Bool] = []
    nonisolated(unsafe) private var _gazeOnBookHistory: [Bool] = []
    nonisolated(unsafe) private var _prevFaceDetected: Bool = false
    nonisolated(unsafe) private var _prevBookDetected: Bool = false
    nonisolated(unsafe) private var _prevGazeOnBook: Bool = false
    nonisolated(unsafe) private var _prevLookingAway: Bool = false
    nonisolated(unsafe) private var _prevHScan: Bool = false
    nonisolated(unsafe) private var _hScanHistory: [Bool] = []

    private static let bookStillThreshold: Int = 12
    private static let gazeHistorySize: Int = 14
    private static let horizontalScanThreshold: Double = 0.012
    private static let gazeSmoothing: Int = 8
    private static let eyeOpenThreshold: Double = 0.01
    private static let stateSmoothing: Int = 6
    private static let hysteresisOn: Int = 3
    private static let hysteresisOff: Int = 4

    func configure() {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        captureSession.commitConfiguration()
        isConfigured = true
    }

    func start() {
        isRunning = true
        _frameSkip = 0
        totalFramesProcessed = 0
        framesWithBook = 0
        framesWithGaze = 0
        framesWithScan = 0
        updateCounter = 0
        _lastGazeX = 0
        _gazeXHistory = []
        _lastBookBox = .zero
        _bookStillFrames = 0
        _lookAwayFrames = 0
        _gazeDownHistory = []
        _eyeOpenHistory = []
        _faceHistory = []
        _bookHistory = []
        _gazeOnBookHistory = []
        _hScanHistory = []
        _prevFaceDetected = false
        _prevBookDetected = false
        _prevGazeOnBook = false
        _prevLookingAway = false
        _prevHScan = false
        captureSession.startRunning()
    }

    func stop() {
        isRunning = false
        captureSession.stopRunning()
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        _frameSkip += 1
        guard _frameSkip % 4 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumAspectRatio = 0.2
        rectangleRequest.maximumAspectRatio = 1.0
        rectangleRequest.minimumSize = 0.08
        rectangleRequest.minimumConfidence = 0.4
        rectangleRequest.maximumObservations = 8

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([faceLandmarksRequest, rectangleRequest])

        let face = faceLandmarksRequest.results?.first
        let detected = face != nil
        var conf: Float = 0
        var gazeX: Double = 0
        var gazeDown = false
        var away = false
        var hScan = false

        if let face {
            conf = face.confidence

            let yaw = face.yaw?.doubleValue ?? 0
            let pitch = face.pitch?.doubleValue ?? 0

            let headDown = pitch < 0.0
            let lookingStraightOrDown = abs(yaw) < 0.55 && pitch < 0.3
            away = !lookingStraightOrDown

            var eyeGazeDown = false
            var eyesOpen = true

            if let leftEye = face.landmarks?.leftEye,
               let rightEye = face.landmarks?.rightEye,
               let leftPupil = face.landmarks?.leftPupil,
               let rightPupil = face.landmarks?.rightPupil {

                let leftPupilCenter = Self.regionCenter(leftPupil)
                let rightPupilCenter = Self.regionCenter(rightPupil)
                let leftEyeBounds = Self.regionBounds(leftEye)
                let rightEyeBounds = Self.regionBounds(rightEye)

                let leftEyeHeight = leftEyeBounds.height
                let rightEyeHeight = rightEyeBounds.height
                eyesOpen = leftEyeHeight > Self.eyeOpenThreshold || rightEyeHeight > Self.eyeOpenThreshold

                _eyeOpenHistory.append(eyesOpen)
                if _eyeOpenHistory.count > Self.gazeSmoothing {
                    _eyeOpenHistory.removeFirst()
                }

                let leftRelY = leftEyeBounds.height > 0.001
                    ? (leftPupilCenter.y - leftEyeBounds.minY) / leftEyeBounds.height
                    : 0.5
                let rightRelY = rightEyeBounds.height > 0.001
                    ? (rightPupilCenter.y - rightEyeBounds.minY) / rightEyeBounds.height
                    : 0.5
                let avgPupilRelY = (leftRelY + rightRelY) / 2.0

                eyeGazeDown = avgPupilRelY < 0.65

                gazeX = (leftPupilCenter.x + rightPupilCenter.x) / 2.0

                _gazeXHistory.append(gazeX)
                if _gazeXHistory.count > Self.gazeHistorySize {
                    _gazeXHistory.removeFirst()
                }

                if _gazeXHistory.count >= 6 {
                    var directionChanges = 0
                    for i in 1..<_gazeXHistory.count {
                        let delta = _gazeXHistory[i] - _gazeXHistory[i - 1]
                        if i >= 2 {
                            let prevDelta = _gazeXHistory[i - 1] - _gazeXHistory[i - 2]
                            if (delta > Self.horizontalScanThreshold && prevDelta < -Self.horizontalScanThreshold) ||
                               (delta < -Self.horizontalScanThreshold && prevDelta > Self.horizontalScanThreshold) {
                                directionChanges += 1
                            }
                        }
                    }
                    hScan = directionChanges >= 1
                }
            }

            gazeDown = headDown || eyeGazeDown

            _gazeDownHistory.append(gazeDown)
            if _gazeDownHistory.count > Self.gazeSmoothing {
                _gazeDownHistory.removeFirst()
            }
            let downCount = _gazeDownHistory.filter { $0 }.count
            gazeDown = downCount >= (_gazeDownHistory.count / 2)

            let smoothEyesOpen = _eyeOpenHistory.isEmpty || _eyeOpenHistory.filter({ $0 }).count >= (_eyeOpenHistory.count / 3)
            if !smoothEyesOpen {
                away = true
            }
        }

        let bestRect = rectangleRequest.results?
            .filter { rect in
                let box = rect.boundingBox
                let area = box.width * box.height
                let inLowerHalf = box.origin.y < 0.55
                let reasonableSize = area > 0.015 && area < 0.7
                let notTooWide = box.width < 0.9
                let notTooTall = box.height < 0.8
                return inLowerHalf && reasonableSize && notTooWide && notTooTall && rect.confidence > 0.3
            }
            .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })

        let bookBox = bestRect?.boundingBox ?? .zero
        let hasBook = bestRect != nil

        if hasBook {
            let dx = abs(bookBox.origin.x - _lastBookBox.origin.x)
            let dy = abs(bookBox.origin.y - _lastBookBox.origin.y)
            let dw = abs(bookBox.width - _lastBookBox.width)
            if dx < 0.02 && dy < 0.02 && dw < 0.02 {
                _bookStillFrames += 1
            } else {
                _bookStillFrames = max(0, _bookStillFrames - 2)
            }
            _lastBookBox = bookBox
        } else {
            _bookStillFrames = max(0, _bookStillFrames - 1)
        }

        let still = _bookStillFrames >= Self.bookStillThreshold

        if away {
            _lookAwayFrames += 1
        } else {
            _lookAwayFrames = max(0, _lookAwayFrames - 2)
        }

        let isLookingAway = _lookAwayFrames > 10

        let rawGazeOnBook = detected && hasBook && gazeDown && !away

        _faceHistory.append(detected)
        if _faceHistory.count > Self.stateSmoothing { _faceHistory.removeFirst() }
        _bookHistory.append(hasBook)
        if _bookHistory.count > Self.stateSmoothing { _bookHistory.removeFirst() }
        _gazeOnBookHistory.append(rawGazeOnBook)
        if _gazeOnBookHistory.count > Self.stateSmoothing { _gazeOnBookHistory.removeFirst() }
        _hScanHistory.append(hScan)
        if _hScanHistory.count > Self.stateSmoothing { _hScanHistory.removeFirst() }

        let smoothFace = Self.hysteresis(history: _faceHistory, prev: _prevFaceDetected)
        let smoothBook = Self.hysteresis(history: _bookHistory, prev: _prevBookDetected)
        let smoothGaze = Self.hysteresis(history: _gazeOnBookHistory, prev: _prevGazeOnBook)
        let smoothAway = Self.hysteresis(history: _faceHistory.map { !$0 }, prev: _prevLookingAway) && isLookingAway
        let smoothHScan = Self.hysteresis(history: _hScanHistory, prev: _prevHScan)

        _prevFaceDetected = smoothFace
        _prevBookDetected = smoothBook
        _prevGazeOnBook = smoothGaze
        _prevLookingAway = smoothAway
        _prevHScan = smoothHScan

        Task { @MainActor [weak self, conf, hasBook, bookBox, still, smoothFace, smoothBook, smoothGaze, smoothHScan, smoothAway, rawGazeOnBook] in
            guard let self else { return }
            self.faceDetected = smoothFace
            self.faceConfidence = conf
            self.bookDetected = smoothBook
            self.bookBoundingBox = bookBox
            self.bookIsStill = still
            self.gazeOnBook = smoothGaze
            self.horizontalScanDetected = smoothHScan
            self.lookingAway = smoothAway
            self.totalFramesProcessed += 1
            if hasBook { self.framesWithBook += 1 }
            if rawGazeOnBook { self.framesWithGaze += 1 }
            if rawGazeOnBook && hScan { self.framesWithScan += 1 }
            self.updateCounter += 1
        }
    }

    func resetCounters() {
        totalFramesProcessed = 0
        framesWithBook = 0
        framesWithGaze = 0
        framesWithScan = 0
        updateCounter = 0
        _lastGazeX = 0
        _gazeXHistory = []
        _lastBookBox = .zero
        _bookStillFrames = 0
        _lookAwayFrames = 0
        _gazeDownHistory = []
        _eyeOpenHistory = []
        _faceHistory = []
        _bookHistory = []
        _gazeOnBookHistory = []
        _hScanHistory = []
        _prevFaceDetected = false
        _prevBookDetected = false
        _prevGazeOnBook = false
        _prevLookingAway = false
        _prevHScan = false
    }

    nonisolated private static func hysteresis(history: [Bool], prev: Bool) -> Bool {
        let trueCount = history.filter { $0 }.count
        if prev {
            return trueCount >= hysteresisOff - 1
        } else {
            return trueCount >= hysteresisOn
        }
    }

    nonisolated private static func regionCenter(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return .zero }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / Double(points.count), y: sumY / Double(points.count))
    }

    nonisolated private static func regionBounds(_ region: VNFaceLandmarkRegion2D) -> CGRect {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return .zero }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
