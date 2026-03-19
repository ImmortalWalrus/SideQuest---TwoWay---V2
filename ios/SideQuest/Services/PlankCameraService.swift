import AVFoundation
import Vision

@Observable
class PlankCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "plankVideoQueue")

    nonisolated(unsafe) private var _frameSkip: Int = 0
    nonisolated(unsafe) private var _smoothedJoints: [String: CGPoint] = [:]
    nonisolated(unsafe) private var _bodyLostFrames: Int = 0
    nonisolated(unsafe) private var _plankGoodFrames: Int = 0
    nonisolated(unsafe) private var _plankBadFrames: Int = 0
    nonisolated(unsafe) private var _stablePlankDetected: Bool = false
    nonisolated(unsafe) private var _kneeDisplayTrueFrames: Int = 0
    nonisolated(unsafe) private var _kneeDisplayFalseFrames: Int = 0
    nonisolated(unsafe) private var _stableKneesOnGround: Bool = false
    nonisolated(unsafe) private var _bodyDisplayLostFrames: Int = 0
    nonisolated(unsafe) private var _bodyDisplayFoundFrames: Int = 0
    nonisolated(unsafe) private var _stableBodyDetected: Bool = false
    nonisolated(unsafe) private var _standingTrueFrames: Int = 0
    nonisolated(unsafe) private var _standingFalseFrames: Int = 0
    nonisolated(unsafe) private var _stableStanding: Bool = false

    private let jointSmoothingFactor: Double = 0.35
    private let displayDebounceFrames: Int = 6

    private(set) var bodyDetected: Bool = false
    private(set) var jointPositions: [String: CGPoint] = [:]
    private(set) var poseConfidence: Float = 0
    private(set) var visibleJointCount: Int = 0
    private(set) var totalFramesProcessed: Int = 0
    private(set) var framesWithBody: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var isConfigured: Bool = false
    private(set) var cameraAvailable: Bool = false

    private(set) var inPlankPosition: Bool = false
    private(set) var displayPlankDetected: Bool = false
    private(set) var kneesOnGround: Bool = false
    private(set) var displayKneesOnGround: Bool = false
    private(set) var displayBodyDetected: Bool = false
    private(set) var isStanding: Bool = false
    private(set) var displayStanding: Bool = false
    private(set) var positioningHint: PositioningHint = .none
    private(set) var bodyCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var bodySpanX: Double = 0
    private(set) var bodySpanY: Double = 0
    private(set) var armsVisible: Bool = false
    private(set) var goodDistance: Bool = false

    var positioningReady: Bool {
        bodyDetected && armsVisible && goodDistance
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            captureSession.commitConfiguration()
            return
        }

        cameraAvailable = true

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
    }

    func start() {
        isRunning = true
        _frameSkip = 0
        _smoothedJoints = [:]
        _bodyLostFrames = 0
        _plankGoodFrames = 0
        _plankBadFrames = 0
        _stablePlankDetected = false
        _kneeDisplayTrueFrames = 0
        _kneeDisplayFalseFrames = 0
        _stableKneesOnGround = false
        _bodyDisplayLostFrames = 0
        _bodyDisplayFoundFrames = 0
        _stableBodyDetected = false
        _standingTrueFrames = 0
        _standingFalseFrames = 0
        _stableStanding = false
        totalFramesProcessed = 0
        framesWithBody = 0
        positioningHint = .none
        captureSession.startRunning()
    }

    func stop() {
        isRunning = false
        captureSession.stopRunning()
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        _frameSkip += 1
        guard _frameSkip % 2 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])

        let pose = request.results?.first
        var rawJoints: [String: CGPoint] = [:]
        var totalConf: Float = 0
        var count = 0

        if let pose {
            let mapping: [(VNHumanBodyPoseObservation.JointName, String)] = [
                (.nose, "nose"),
                (.leftEar, "leftEar"), (.rightEar, "rightEar"),
                (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
                (.leftElbow, "leftElbow"), (.rightElbow, "rightElbow"),
                (.leftWrist, "leftWrist"), (.rightWrist, "rightWrist"),
                (.leftHip, "leftHip"), (.rightHip, "rightHip"),
                (.leftKnee, "leftKnee"), (.rightKnee, "rightKnee"),
                (.leftAnkle, "leftAnkle"), (.rightAnkle, "rightAnkle"),
            ]

            for (joint, name) in mapping {
                if let pt = try? pose.recognizedPoint(joint), pt.confidence > 0.15 {
                    rawJoints[name] = pt.location
                    totalConf += pt.confidence
                    count += 1
                }
            }
        }

        let avgConf = count > 0 ? totalConf / Float(count) : 0
        let detected = count >= 3

        if !detected { _bodyLostFrames += 1 } else { _bodyLostFrames = 0 }

        var smoothed: [String: CGPoint] = [:]
        let alpha = jointSmoothingFactor
        for (name, rawPt) in rawJoints {
            if let prev = _smoothedJoints[name] {
                smoothed[name] = CGPoint(
                    x: prev.x + alpha * (rawPt.x - prev.x),
                    y: prev.y + alpha * (rawPt.y - prev.y)
                )
            } else {
                smoothed[name] = rawPt
            }
        }
        _smoothedJoints = smoothed

        let shoulderMid = ExerciseCameraService.midpoint(smoothed["leftShoulder"], smoothed["rightShoulder"])
        let hipMid = ExerciseCameraService.midpoint(smoothed["leftHip"], smoothed["rightHip"])
        let ankleMid = ExerciseCameraService.midpoint(smoothed["leftAnkle"], smoothed["rightAnkle"])

        var standingDetected = false
        if let sMid = shoulderMid, let hMid = hipMid {
            let verticalDiff = abs(sMid.y - hMid.y)
            let horizontalDiff = abs(sMid.x - hMid.x)
            standingDetected = verticalDiff > 0.15 && horizontalDiff < 0.12
        }

        var plankDetected = false
        if detected && !standingDetected {
            if let sMid = shoulderMid, let hMid = hipMid {
                let verticalDiff = abs(sMid.y - hMid.y)
                plankDetected = verticalDiff < 0.15
            }
            if plankDetected, let hMid = hipMid, let aMid = ankleMid {
                let bodyAlignment = ExerciseCameraService.jointAngle(a: shoulderMid, b: hipMid, c: ankleMid)
                let hipSag = hMid.y - max(shoulderMid?.y ?? 0, aMid.y)
                if bodyAlignment < 120 || hipSag > 0.08 {
                    plankDetected = false
                }
            }
        }

        let lKnee = ExerciseCameraService.jointAngle(
            a: smoothed["leftHip"], b: smoothed["leftKnee"], c: smoothed["leftAnkle"]
        )
        let rKnee = ExerciseCameraService.jointAngle(
            a: smoothed["rightHip"], b: smoothed["rightKnee"], c: smoothed["rightAnkle"]
        )
        var kneesDown = false
        if lKnee > 5 || rKnee > 5 {
            let kneeThreshold: Double = 120
            let leftBent = lKnee > 5 && lKnee < kneeThreshold
            let rightBent = rKnee > 5 && rKnee < kneeThreshold
            let leftNear = ExerciseCameraService.kneeNearAnkleVertically(knee: smoothed["leftKnee"], ankle: smoothed["leftAnkle"])
            let rightNear = ExerciseCameraService.kneeNearAnkleVertically(knee: smoothed["rightKnee"], ankle: smoothed["rightAnkle"])
            kneesDown = (leftBent && leftNear) || (rightBent && rightNear)
        }

        if plankDetected {
            _plankGoodFrames += 1
            _plankBadFrames = 0
        } else {
            _plankBadFrames += 1
            _plankGoodFrames = 0
        }
        if _plankGoodFrames >= displayDebounceFrames { _stablePlankDetected = true }
        if _plankBadFrames >= displayDebounceFrames { _stablePlankDetected = false }

        if kneesDown {
            _kneeDisplayTrueFrames += 1
            _kneeDisplayFalseFrames = 0
        } else {
            _kneeDisplayFalseFrames += 1
            _kneeDisplayTrueFrames = 0
        }
        if _kneeDisplayTrueFrames >= displayDebounceFrames { _stableKneesOnGround = true }
        if _kneeDisplayFalseFrames >= displayDebounceFrames { _stableKneesOnGround = false }

        if detected {
            _bodyDisplayFoundFrames += 1
            _bodyDisplayLostFrames = 0
        } else {
            _bodyDisplayLostFrames += 1
            _bodyDisplayFoundFrames = 0
        }
        if _bodyDisplayFoundFrames >= displayDebounceFrames { _stableBodyDetected = true }
        if _bodyDisplayLostFrames >= displayDebounceFrames { _stableBodyDetected = false }

        if standingDetected {
            _standingTrueFrames += 1
            _standingFalseFrames = 0
        } else {
            _standingFalseFrames += 1
            _standingTrueFrames = 0
        }
        if _standingTrueFrames >= displayDebounceFrames { _stableStanding = true }
        if _standingFalseFrames >= displayDebounceFrames { _stableStanding = false }

        let hasArms = (smoothed["leftElbow"] != nil || smoothed["rightElbow"] != nil) &&
                      (smoothed["leftWrist"] != nil || smoothed["rightWrist"] != nil)

        let allXs = smoothed.values.map(\.x)
        let allYs = smoothed.values.map(\.y)
        let centerX = allXs.isEmpty ? 0.5 : allXs.reduce(0, +) / Double(allXs.count)
        let centerY = allYs.isEmpty ? 0.5 : allYs.reduce(0, +) / Double(allYs.count)
        let spanX = (allXs.max() ?? 0.5) - (allXs.min() ?? 0.5)
        let spanY = (allYs.max() ?? 0.5) - (allYs.min() ?? 0.5)
        let bodySpan = max(spanX, spanY)

        var hint: PositioningHint = .none
        if !detected {
            hint = .noBody
        } else if bodySpan > 0.85 {
            hint = .tooClose
        } else if bodySpan < 0.2 {
            hint = .tooFar
        } else if centerX < 0.25 {
            hint = .moveRight
        } else if centerX > 0.75 {
            hint = .moveLeft
        } else if hasArms && detected && bodySpan >= 0.2 && bodySpan <= 0.85 {
            hint = .goodPosition
        }

        let isGoodDist = bodySpan >= 0.2 && bodySpan <= 0.85

        let stablePlank = _stablePlankDetected
        let stableKnee = _stableKneesOnGround
        let stableBody = _stableBodyDetected
        let stableStand = _stableStanding

        Task { @MainActor [weak self, smoothed, count] in
            guard let self else { return }
            self.bodyDetected = detected
            self.jointPositions = smoothed
            self.poseConfidence = avgConf
            self.visibleJointCount = count
            self.totalFramesProcessed += 1
            if detected { self.framesWithBody += 1 }
            self.inPlankPosition = plankDetected
            self.displayPlankDetected = stablePlank
            self.kneesOnGround = kneesDown
            self.displayKneesOnGround = stableKnee
            self.displayBodyDetected = stableBody
            self.isStanding = standingDetected
            self.displayStanding = stableStand
            self.positioningHint = hint
            self.armsVisible = hasArms
            self.goodDistance = isGoodDist
            self.bodyCenter = CGPoint(x: centerX, y: centerY)
            self.bodySpanX = spanX
            self.bodySpanY = spanY
        }
    }
}
