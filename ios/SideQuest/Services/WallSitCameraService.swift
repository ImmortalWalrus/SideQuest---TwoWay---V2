import AVFoundation
import Vision

@Observable
class WallSitCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "wallSitVideoQueue")

    nonisolated(unsafe) private var _frameSkip: Int = 0
    nonisolated(unsafe) private var _smoothedJoints: [String: CGPoint] = [:]
    nonisolated(unsafe) private var _bodyLostFrames: Int = 0
    nonisolated(unsafe) private var _wallSitGoodFrames: Int = 0
    nonisolated(unsafe) private var _wallSitBadFrames: Int = 0
    nonisolated(unsafe) private var _stableWallSitDetected: Bool = false
    nonisolated(unsafe) private var _bodyDisplayLostFrames: Int = 0
    nonisolated(unsafe) private var _bodyDisplayFoundFrames: Int = 0
    nonisolated(unsafe) private var _stableBodyDetected: Bool = false
    nonisolated(unsafe) private var _standingTrueFrames: Int = 0
    nonisolated(unsafe) private var _standingFalseFrames: Int = 0
    nonisolated(unsafe) private var _stableStanding: Bool = false
    nonisolated(unsafe) private var _chairSupportTrueFrames: Int = 0
    nonisolated(unsafe) private var _chairSupportFalseFrames: Int = 0
    nonisolated(unsafe) private var _stableChairSupport: Bool = false

    private let jointSmoothingFactor: Double = 0.35
    private let displayDebounceFrames: Int = 4

    private(set) var bodyDetected: Bool = false
    private(set) var jointPositions: [String: CGPoint] = [:]
    private(set) var poseConfidence: Float = 0
    private(set) var visibleJointCount: Int = 0
    private(set) var totalFramesProcessed: Int = 0
    private(set) var framesWithBody: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var isConfigured: Bool = false
    private(set) var cameraAvailable: Bool = false

    private(set) var inWallSitPosition: Bool = false
    private(set) var displayWallSitDetected: Bool = false
    private(set) var displayBodyDetected: Bool = false
    private(set) var isStanding: Bool = false
    private(set) var displayStanding: Bool = false
    private(set) var displayChairSupportDetected: Bool = false
    private(set) var leftKneeAngle: Double = 0
    private(set) var rightKneeAngle: Double = 0
    private(set) var positioningHint: PositioningHint = .none
    private(set) var bodyCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var bodySpanX: Double = 0
    private(set) var bodySpanY: Double = 0
    private(set) var armsVisible: Bool = false
    private(set) var goodDistance: Bool = false

    var positioningReady: Bool {
        displayWallSitDetected && displayBodyDetected && goodDistance && !displayStanding && !displayChairSupportDetected
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
        _wallSitGoodFrames = 0
        _wallSitBadFrames = 0
        _stableWallSitDetected = false
        _bodyDisplayLostFrames = 0
        _bodyDisplayFoundFrames = 0
        _stableBodyDetected = false
        _standingTrueFrames = 0
        _standingFalseFrames = 0
        _stableStanding = false
        _chairSupportTrueFrames = 0
        _chairSupportFalseFrames = 0
        _stableChairSupport = false
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
        let kneeMid = ExerciseCameraService.midpoint(smoothed["leftKnee"], smoothed["rightKnee"])
        let ankleMid = ExerciseCameraService.midpoint(smoothed["leftAnkle"], smoothed["rightAnkle"])

        let lKnee = ExerciseCameraService.jointAngle(
            a: smoothed["leftHip"], b: smoothed["leftKnee"], c: smoothed["leftAnkle"]
        )
        let rKnee = ExerciseCameraService.jointAngle(
            a: smoothed["rightHip"], b: smoothed["rightKnee"], c: smoothed["rightAnkle"]
        )
        let bestKnee = max(lKnee, rKnee)

        var torsoHeight: Double = 0
        var torsoOffsetX: Double = 1
        if let sMid = shoulderMid, let hMid = hipMid {
            torsoHeight = abs(sMid.y - hMid.y)
            torsoOffsetX = abs(sMid.x - hMid.x)
        }

        var thighHeightDelta: Double = 1
        var thighRun: Double = 0
        var hipsNotTooLow: Bool = false
        if let hMid = hipMid, let kMid = kneeMid {
            thighHeightDelta = abs(hMid.y - kMid.y)
            thighRun = abs(hMid.x - kMid.x)
            hipsNotTooLow = hMid.y >= kMid.y - 0.05
        }

        var shinOffsetX: Double = 1
        var shinLength: Double = 0
        if let kMid = kneeMid, let aMid = ankleMid {
            shinOffsetX = abs(kMid.x - aMid.x)
            shinLength = abs(kMid.y - aMid.y)
        }

        let torsoUpright = torsoHeight > 0.08 && torsoOffsetX < 0.095
        let thighsParallel = thighHeightDelta < 0.08
        let hipsForwardEnough = thighRun > 0.055
        let shinsVertical = shinOffsetX < 0.085 && shinLength > 0.06
        let kneesBent = bestKnee > 65 && bestKnee < 130

        var hipAnkleOffset: Double = 0
        if let hMid = hipMid, let aMid = ankleMid {
            hipAnkleOffset = abs(hMid.x - aMid.x)
        }
        let hasLShapeOffset = hipAnkleOffset > 0.04

        var torsoThighAngle: Double = 90
        if let sMid = shoulderMid, let hMid = hipMid, let kMid = kneeMid {
            torsoThighAngle = ExerciseCameraService.jointAngle(a: sMid, b: hMid, c: kMid)
        }
        let torsoThighSquare = torsoThighAngle > 60 && torsoThighAngle < 120

        var standingDetected = false
        if torsoHeight > 0 {
            standingDetected = torsoHeight > 0.2 && torsoOffsetX < 0.12
            if standingDetected && bestKnee > 5 && bestKnee < 150 {
                standingDetected = false
            }
        }

        let chairSupportSuspected = detected && !standingDetected && torsoUpright && thighsParallel && shinsVertical && (thighRun < 0.04 || !hasLShapeOffset)
        let wallSitDetected = detected && !standingDetected && torsoUpright && thighsParallel && hipsForwardEnough && shinsVertical && hipsNotTooLow && kneesBent && hasLShapeOffset && torsoThighSquare && !chairSupportSuspected

        if wallSitDetected {
            _wallSitGoodFrames += 1
            _wallSitBadFrames = 0
        } else {
            _wallSitBadFrames += 1
            _wallSitGoodFrames = 0
        }
        if _wallSitGoodFrames >= displayDebounceFrames { _stableWallSitDetected = true }
        if _wallSitBadFrames >= displayDebounceFrames { _stableWallSitDetected = false }

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

        if chairSupportSuspected {
            _chairSupportTrueFrames += 1
            _chairSupportFalseFrames = 0
        } else {
            _chairSupportFalseFrames += 1
            _chairSupportTrueFrames = 0
        }
        if _chairSupportTrueFrames >= displayDebounceFrames { _stableChairSupport = true }
        if _chairSupportFalseFrames >= displayDebounceFrames { _stableChairSupport = false }

        let hasArms = (smoothed["leftElbow"] != nil || smoothed["rightElbow"] != nil)

        let allXs = smoothed.values.map(\.x)
        let allYs = smoothed.values.map(\.y)
        let centerX = allXs.isEmpty ? 0.5 : allXs.reduce(0, +) / Double(allXs.count)
        let centerY = allYs.isEmpty ? 0.5 : allYs.reduce(0, +) / Double(allYs.count)
        let spanX = (allXs.max() ?? 0.5) - (allXs.min() ?? 0.5)
        let spanY = (allYs.max() ?? 0.5) - (allYs.min() ?? 0.5)
        let bodySpan = max(spanX, spanY)
        let stableWS = _stableWallSitDetected
        let stableBody = _stableBodyDetected
        let stableStand = _stableStanding
        let stableChairSupport = _stableChairSupport

        var hint: PositioningHint = .none
        if !detected {
            hint = .noBody
        } else if bodySpan > 0.9 {
            hint = .tooClose
        } else if bodySpan < 0.12 {
            hint = .tooFar
        } else if centerX < 0.25 {
            hint = .moveRight
        } else if centerX > 0.75 {
            hint = .moveLeft
        } else if stableChairSupport {
            hint = .noChairSupport
        } else if detected && bodySpan >= 0.15 && bodySpan <= 0.85 {
            hint = .goodPosition
        }

        let isGoodDist = bodySpan >= 0.12 && bodySpan <= 0.9

        Task { @MainActor [weak self, smoothed, count] in
            guard let self else { return }
            self.bodyDetected = detected
            self.jointPositions = smoothed
            self.poseConfidence = avgConf
            self.visibleJointCount = count
            self.totalFramesProcessed += 1
            if detected { self.framesWithBody += 1 }
            self.inWallSitPosition = wallSitDetected
            self.displayWallSitDetected = stableWS
            self.displayBodyDetected = stableBody
            self.isStanding = standingDetected
            self.displayStanding = stableStand
            self.displayChairSupportDetected = stableChairSupport
            self.leftKneeAngle = lKnee
            self.rightKneeAngle = rKnee
            self.positioningHint = hint
            self.armsVisible = hasArms
            self.goodDistance = isGoodDist
            self.bodyCenter = CGPoint(x: centerX, y: centerY)
            self.bodySpanX = spanX
            self.bodySpanY = spanY
        }
    }
}
