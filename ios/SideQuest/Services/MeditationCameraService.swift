import AVFoundation
import Vision

@Observable
class MeditationCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "meditationVideoQueue")
    private let sessionQueue = DispatchQueue(label: "meditationSessionQueue")
    nonisolated(unsafe) private var _frameSkip: Int = 0

    private(set) var faceDetected: Bool = false
    private(set) var eyesClosed: Bool = false
    private(set) var faceConfidence: Float = 0
    private(set) var leftEyeOpenness: Double = 1.0
    private(set) var rightEyeOpenness: Double = 1.0
    private(set) var headStill: Bool = true
    private(set) var totalFramesProcessed: Int = 0
    private(set) var framesWithFace: Int = 0
    private(set) var framesWithEyesClosed: Int = 0
    private(set) var framesHeadStill: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var updateCounter: Int = 0
    private(set) var isConfigured: Bool = false

    nonisolated(unsafe) private var _lastYaw: Double = 0
    nonisolated(unsafe) private var _lastPitch: Double = 0
    nonisolated(unsafe) private var _lastRoll: Double = 0

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
        let session = captureSession
        sessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func resetCounters() {
        totalFramesProcessed = 0
        framesWithFace = 0
        framesWithEyesClosed = 0
        framesHeadStill = 0
        updateCounter = 0
        _lastYaw = 0
        _lastPitch = 0
        _lastRoll = 0
    }

    func stop() {
        isRunning = false
        let session = captureSession
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        _frameSkip += 1
        guard _frameSkip % 5 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([faceLandmarksRequest])

        let face = faceLandmarksRequest.results?.first
        let detected = face != nil
        var conf: Float = 0
        var leftOpen: Double = 1.0
        var rightOpen: Double = 1.0
        var closed = false
        var still = true

        if let face {
            conf = face.confidence

            if let leftEye = face.landmarks?.leftEye,
               let rightEye = face.landmarks?.rightEye {
                leftOpen = Self.eyeAspectRatio(leftEye)
                rightOpen = Self.eyeAspectRatio(rightEye)
                let avgOpenness = (leftOpen + rightOpen) / 2.0
                closed = avgOpenness < 0.22
            }

            let yaw = face.yaw?.doubleValue ?? 0
            let pitch = face.pitch?.doubleValue ?? 0
            let roll = face.roll?.doubleValue ?? 0

            if _lastYaw != 0 || _lastPitch != 0 {
                let yawDelta = abs(yaw - _lastYaw)
                let pitchDelta = abs(pitch - _lastPitch)
                let rollDelta = abs(roll - _lastRoll)
                still = yawDelta < 0.15 && pitchDelta < 0.15 && rollDelta < 0.15
            }

            _lastYaw = yaw
            _lastPitch = pitch
            _lastRoll = roll
        }

        Task { @MainActor [weak self, conf, leftOpen, rightOpen, closed, still] in
            guard let self else { return }
            self.faceDetected = detected
            self.faceConfidence = conf
            self.leftEyeOpenness = leftOpen
            self.rightEyeOpenness = rightOpen
            self.eyesClosed = closed
            self.headStill = still
            self.totalFramesProcessed += 1
            if detected { self.framesWithFace += 1 }
            if detected && closed { self.framesWithEyesClosed += 1 }
            if detected && still { self.framesHeadStill += 1 }
            self.updateCounter += 1
        }
    }

    nonisolated private static func eyeAspectRatio(_ region: VNFaceLandmarkRegion2D) -> Double {
        let points = region.normalizedPoints
        guard points.count >= 6 else { return 1.0 }

        let topBottom1 = abs(points[1].y - points[5].y)
        let topBottom2 = abs(points[2].y - points[4].y)
        let leftRight = abs(points[0].x - points[3].x)

        guard leftRight > 0.001 else { return 1.0 }
        return (topBottom1 + topBottom2) / (2.0 * leftRight)
    }
}
