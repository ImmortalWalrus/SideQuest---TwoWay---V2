import AVFoundation
import Vision

nonisolated enum PositioningHint: Equatable, Sendable {
    case none
    case noBody
    case tooClose
    case tooFar
    case moveLeft
    case moveRight
    case tiltUp
    case tiltDown
    case noHead
    case noChairSupport
    case goodPosition

    var message: String {
        switch self {
        case .none: return ""
        case .noBody: return "Step into frame"
        case .tooClose: return "Move back — too close"
        case .tooFar: return "Get closer to camera"
        case .moveLeft: return "Move left"
        case .moveRight: return "Move right"
        case .tiltUp: return "Tilt phone up"
        case .tiltDown: return "Tilt phone down"
        case .noHead: return "Head not visible — adjust camera"
        case .noChairSupport: return "No chair support — hover against the wall"
        case .goodPosition: return "Perfect — hold position!"
        }
    }

    var icon: String {
        switch self {
        case .none: return ""
        case .noBody: return "person.fill.questionmark"
        case .tooClose: return "arrow.left.and.right.square"
        case .tooFar: return "arrow.right.and.line.vertical.and.arrow.left"
        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        case .tiltUp: return "arrow.up"
        case .tiltDown: return "arrow.down"
        case .noHead: return "eye.slash.fill"
        case .noChairSupport: return "exclamationmark.triangle.fill"
        case .goodPosition: return "checkmark.circle.fill"
        }
    }
}

@Observable
class ExerciseCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "exerciseVideoQueue")

    nonisolated(unsafe) private var _frameSkip: Int = 0
    nonisolated(unsafe) private var _pushUpPhase: Int = 0
    nonisolated(unsafe) private var _prevAvgArm: Double = 0
    nonisolated(unsafe) private var _repCooldown: Int = 0
    nonisolated(unsafe) private var _armAngleHistory: [Double] = []
    nonisolated(unsafe) private var _bodyLostFrames: Int = 0
    nonisolated(unsafe) private var _smoothedJoints: [String: CGPoint] = [:]
    nonisolated(unsafe) private var _downFrameCount: Int = 0
    nonisolated(unsafe) private var _upFrameCount: Int = 0
    nonisolated(unsafe) private var _kneeDownCooldown: Int = 0
    nonisolated(unsafe) private var _kneesWereDown: Bool = false
    nonisolated(unsafe) private var _kneeDisplayTrueFrames: Int = 0
    nonisolated(unsafe) private var _kneeDisplayFalseFrames: Int = 0
    nonisolated(unsafe) private var _formDisplayBadFrames: Int = 0
    nonisolated(unsafe) private var _formDisplayGoodFrames: Int = 0
    nonisolated(unsafe) private var _bodyDisplayLostFrames: Int = 0
    nonisolated(unsafe) private var _bodyDisplayFoundFrames: Int = 0
    nonisolated(unsafe) private var _stableKneesOnGround: Bool = false
    nonisolated(unsafe) private var _stableFormGood: Bool = true
    nonisolated(unsafe) private var _stableBodyDetected: Bool = false
    nonisolated(unsafe) private var _standingDisplayTrueFrames: Int = 0
    nonisolated(unsafe) private var _standingDisplayFalseFrames: Int = 0
    nonisolated(unsafe) private var _stableStanding: Bool = false
    nonisolated(unsafe) private var _headLostDisplayFrames: Int = 0
    nonisolated(unsafe) private var _headFoundDisplayFrames: Int = 0
    nonisolated(unsafe) private var _stableHeadDetected: Bool = true
    nonisolated(unsafe) private var _pushUpPostureActive: Bool = false
    nonisolated(unsafe) private var _postureGoodFrames: Int = 0
    nonisolated(unsafe) private var _postureBadFrames: Int = 0

    private let displayDebounceFrames: Int = 6
    private let postureDebounceFrames: Int = 4

    private(set) var bodyDetected: Bool = false
    private(set) var jointPositions: [String: CGPoint] = [:]
    private(set) var poseConfidence: Float = 0
    private(set) var leftArmAngle: Double = 0
    private(set) var rightArmAngle: Double = 0
    private(set) var bodyAlignmentAngle: Double = 0
    private(set) var leftKneeAngle: Double = 0
    private(set) var rightKneeAngle: Double = 0
    private(set) var visibleJointCount: Int = 0
    private(set) var totalFramesProcessed: Int = 0
    private(set) var framesWithBody: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var updateCounter: Int = 0
    private(set) var isConfigured: Bool = false

    private(set) var cameraAvailable: Bool = false

    private(set) var pushUpCount: Int = 0
    private(set) var pushUpPhaseLabel: String = "Ready"

    private(set) var positioningHint: PositioningHint = .none
    private(set) var armsVisible: Bool = false
    private(set) var goodDistance: Bool = false
    private(set) var lowerBodyVisible: Bool = false
    private(set) var fullBodyVisible: Bool = false
    private(set) var bodyCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var bodySpanX: Double = 0
    private(set) var bodySpanY: Double = 0
    private(set) var videoAspectRatio: CGFloat = 3.0 / 4.0

    private(set) var kneesOnGround: Bool = false
    private(set) var formGood: Bool = true
    private(set) var displayKneesOnGround: Bool = false
    private(set) var displayFormGood: Bool = true
    private(set) var displayBodyDetected: Bool = false
    private(set) var headDetected: Bool = true
    private(set) var displayHeadDetected: Bool = true
    private(set) var isStanding: Bool = false
    private(set) var displayStanding: Bool = false
    private(set) var inPushUpPosture: Bool = false

    private let jointSmoothingFactor: Double = 0.55
    private let armHistorySize: Int = 8
    private let hysteresisDownFrames: Int = 2
    private let hysteresisUpFrames: Int = 2
    private let repCooldownFrames: Int = 4
    private let kneeRecoveryCooldownFrames: Int = 8

    var positioningReady: Bool {
        bodyDetected && armsVisible && goodDistance && headDetected && lowerBodyVisible
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        captureSession.beginConfiguration()
        if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
        } else if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        } else {
            captureSession.sessionPreset = .medium
        }

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
        _pushUpPhase = 0
        _prevAvgArm = 0
        _repCooldown = 0
        _armAngleHistory = []
        _bodyLostFrames = 0
        _smoothedJoints = [:]
        _downFrameCount = 0
        _upFrameCount = 0
        _kneeDownCooldown = 0
        _kneesWereDown = false
        _kneeDisplayTrueFrames = 0
        _kneeDisplayFalseFrames = 0
        _formDisplayBadFrames = 0
        _formDisplayGoodFrames = 0
        _bodyDisplayLostFrames = 0
        _bodyDisplayFoundFrames = 0
        _stableKneesOnGround = false
        _stableFormGood = true
        _stableBodyDetected = false
        _standingDisplayTrueFrames = 0
        _standingDisplayFalseFrames = 0
        _stableStanding = false
        _headLostDisplayFrames = 0
        _headFoundDisplayFrames = 0
        _stableHeadDetected = true
        _pushUpPostureActive = false
        _postureGoodFrames = 0
        _postureBadFrames = 0
        totalFramesProcessed = 0
        framesWithBody = 0
        updateCounter = 0
        pushUpCount = 0
        pushUpPhaseLabel = "Ready"
        positioningHint = .none
        kneesOnGround = false
        formGood = true
        lowerBodyVisible = false
        fullBodyVisible = false
        captureSession.startRunning()
    }

    func resetPushUpCount() {
        pushUpCount = 0
        _pushUpPhase = 0
        _prevAvgArm = 0
        _repCooldown = 0
        _armAngleHistory = []
        _downFrameCount = 0
        _upFrameCount = 0
        _kneeDownCooldown = 0
        _kneesWereDown = false
        _kneeDisplayTrueFrames = 0
        _kneeDisplayFalseFrames = 0
        _formDisplayBadFrames = 0
        _formDisplayGoodFrames = 0
        _stableKneesOnGround = false
        _stableFormGood = true
        pushUpPhaseLabel = "Ready"
        kneesOnGround = false
        formGood = true
        displayKneesOnGround = false
        displayFormGood = true
        displayStanding = false
        isStanding = false
        displayHeadDetected = true
        headDetected = true
        inPushUpPosture = false
        lowerBodyVisible = false
        fullBodyVisible = false
    }

    func stop() {
        isRunning = false
        captureSession.stopRunning()
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        _frameSkip += 1

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pixelWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let pixelHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let portraitAspectRatio = min(pixelWidth, pixelHeight) / max(pixelWidth, pixelHeight)

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
                (.leftEye, "leftEye"), (.rightEye, "rightEye"),
                (.leftEar, "leftEar"), (.rightEar, "rightEar"),
                (.neck, "neck"),
                (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
                (.leftElbow, "leftElbow"), (.rightElbow, "rightElbow"),
                (.leftWrist, "leftWrist"), (.rightWrist, "rightWrist"),
                (.root, "root"),
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

        if !detected {
            _bodyLostFrames += 1
        } else {
            _bodyLostFrames = 0
        }

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

        let lAngle = Self.jointAngle(
            a: smoothed["leftShoulder"], b: smoothed["leftElbow"], c: smoothed["leftWrist"]
        )
        let rAngle = Self.jointAngle(
            a: smoothed["rightShoulder"], b: smoothed["rightElbow"], c: smoothed["rightWrist"]
        )
        let alignment = Self.jointAngle(
            a: Self.midpoint(smoothed["leftShoulder"], smoothed["rightShoulder"]),
            b: Self.midpoint(smoothed["leftHip"], smoothed["rightHip"]),
            c: Self.midpoint(smoothed["leftAnkle"], smoothed["rightAnkle"])
        )

        let lKnee = Self.jointAngle(
            a: smoothed["leftHip"], b: smoothed["leftKnee"], c: smoothed["leftAnkle"]
        )
        let rKnee = Self.jointAngle(
            a: smoothed["rightHip"], b: smoothed["rightKnee"], c: smoothed["rightAnkle"]
        )

        let kneeAnglesValid = lKnee > 5 || rKnee > 5
        var kneesDown = false
        if kneeAnglesValid {
            let kneeThreshold: Double = 120
            let leftKneeBent = lKnee > 5 && lKnee < kneeThreshold
            let rightKneeBent = rKnee > 5 && rKnee < kneeThreshold

            let leftKneeNearGround = Self.kneeNearAnkleVertically(
                knee: smoothed["leftKnee"], ankle: smoothed["leftAnkle"]
            )
            let rightKneeNearGround = Self.kneeNearAnkleVertically(
                knee: smoothed["rightKnee"], ankle: smoothed["rightAnkle"]
            )

            kneesDown = (leftKneeBent && leftKneeNearGround) || (rightKneeBent && rightKneeNearGround)

            if !kneesDown {
                let hipY = Self.midpoint(smoothed["leftHip"], smoothed["rightHip"])?.y ?? 0
                let kneeY = Self.midpoint(smoothed["leftKnee"], smoothed["rightKnee"])?.y ?? 0
                let ankleY = Self.midpoint(smoothed["leftAnkle"], smoothed["rightAnkle"])?.y ?? 0

                if kneeY > 0 && ankleY > 0 && hipY > 0 {
                    let kneeToAnkleDist = abs(kneeY - ankleY)
                    let hipToAnkleDist = abs(hipY - ankleY)
                    if hipToAnkleDist > 0.01 && kneeToAnkleDist / hipToAnkleDist < 0.25 {
                        kneesDown = true
                    }
                }
            }
        }

        if kneesDown {
            _kneesWereDown = true
            _kneeDownCooldown = kneeRecoveryCooldownFrames
        } else if _kneesWereDown {
            if _kneeDownCooldown > 0 {
                _kneeDownCooldown -= 1
            } else {
                _kneesWereDown = false
            }
        }

        let goodForm = !kneesDown && !_kneesWereDown

        let hasHead = smoothed["nose"] != nil
            || smoothed["leftEye"] != nil
            || smoothed["rightEye"] != nil
            || smoothed["leftEar"] != nil
            || smoothed["rightEar"] != nil
        let hasLowerBody = (smoothed["leftKnee"] != nil || smoothed["rightKnee"] != nil)
            && (smoothed["leftAnkle"] != nil || smoothed["rightAnkle"] != nil)

        let shoulderMid = Self.midpoint(smoothed["leftShoulder"], smoothed["rightShoulder"])
        let hipMid = Self.midpoint(smoothed["leftHip"], smoothed["rightHip"])
        var standingDetected = false
        if let sMid = shoulderMid, let hMid = hipMid {
            let verticalDiff = abs(sMid.y - hMid.y)
            let horizontalDiff = abs(sMid.x - hMid.x)
            let ankleMid = Self.midpoint(smoothed["leftAnkle"], smoothed["rightAnkle"])
            let hipToAnkleVert = ankleMid.map { abs(hMid.y - $0.y) } ?? 0
            standingDetected = verticalDiff > 0.22 && horizontalDiff < 0.12 && hipToAnkleVert > 0.15
        }

        var pushUpPosture = false
        if detected && !standingDetected {
            if let sMid = shoulderMid, let hMid = hipMid {
                let verticalDiff = abs(sMid.y - hMid.y)
                pushUpPosture = verticalDiff < 0.18
            }
        }

        if pushUpPosture {
            _postureGoodFrames += 1
            _postureBadFrames = 0
        } else {
            _postureBadFrames += 1
            _postureGoodFrames = 0
        }
        if _postureGoodFrames >= postureDebounceFrames { _pushUpPostureActive = true }
        if _postureBadFrames >= postureDebounceFrames { _pushUpPostureActive = false }

        let rawAvgArm = (lAngle + rAngle) / 2.0
        _armAngleHistory.append(rawAvgArm)
        if _armAngleHistory.count > armHistorySize {
            _armAngleHistory.removeFirst()
        }
        let smoothedArm = _armAngleHistory.reduce(0, +) / Double(_armAngleHistory.count)

        var newRepCount: Int? = nil
        var phaseLabel = "Ready"

        let hasArms = (smoothed["leftElbow"] != nil || smoothed["rightElbow"] != nil) &&
                      (smoothed["leftWrist"] != nil || smoothed["rightWrist"] != nil)

        let requiredJointsForRep = hasArms && hasHead && !standingDetected && _pushUpPostureActive

        if detected && (lAngle > 5 || rAngle > 5) && requiredJointsForRep {
            let downThreshold: Double = 100
            let upThreshold: Double = 140

            if _repCooldown > 0 {
                _repCooldown -= 1
            }

            if smoothedArm < downThreshold {
                _downFrameCount += 1
                _upFrameCount = 0
            } else if smoothedArm > upThreshold {
                _upFrameCount += 1
                _downFrameCount = 0
            } else {
                _downFrameCount = max(0, _downFrameCount - 1)
                _upFrameCount = max(0, _upFrameCount - 1)
            }

            if _pushUpPhase == 0 && _downFrameCount >= hysteresisDownFrames {
                _pushUpPhase = 1
                phaseLabel = "Down"
            } else if _pushUpPhase == 1 && _upFrameCount >= hysteresisUpFrames && _repCooldown == 0 {
                if goodForm {
                    _pushUpPhase = 0
                    _repCooldown = repCooldownFrames
                    newRepCount = 1
                    phaseLabel = "Up"
                    _downFrameCount = 0
                    _upFrameCount = 0
                } else {
                    phaseLabel = "Fix Form!"
                }
            } else {
                phaseLabel = _pushUpPhase == 1 ? "Down" : "Up"
            }
        } else if standingDetected {
            phaseLabel = "Standing"
            _downFrameCount = 0
            _upFrameCount = 0
        } else if detected && !_pushUpPostureActive {
            phaseLabel = "Get Down"
            _downFrameCount = 0
            _upFrameCount = 0
        }

        _prevAvgArm = smoothedArm

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
        } else if centerY < 0.25 {
            hint = .tiltDown
        } else if centerY > 0.75 {
            hint = .tiltUp
        } else if !hasLowerBody && detected {
            hint = .tiltDown
        } else if !hasHead && detected {
            hint = .noHead
        } else if hasArms && hasHead && hasLowerBody && detected && bodySpan >= 0.2 && bodySpan <= 0.85 {
            hint = .goodPosition
        }

        let isGoodDist = bodySpan >= 0.2 && bodySpan <= 0.85

        if kneesDown {
            _kneeDisplayTrueFrames += 1
            _kneeDisplayFalseFrames = 0
        } else {
            _kneeDisplayFalseFrames += 1
            _kneeDisplayTrueFrames = 0
        }
        if _kneeDisplayTrueFrames >= displayDebounceFrames { _stableKneesOnGround = true }
        if _kneeDisplayFalseFrames >= displayDebounceFrames { _stableKneesOnGround = false }

        if goodForm {
            _formDisplayGoodFrames += 1
            _formDisplayBadFrames = 0
        } else {
            _formDisplayBadFrames += 1
            _formDisplayGoodFrames = 0
        }
        if _formDisplayGoodFrames >= displayDebounceFrames { _stableFormGood = true }
        if _formDisplayBadFrames >= displayDebounceFrames { _stableFormGood = false }

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
            _standingDisplayTrueFrames += 1
            _standingDisplayFalseFrames = 0
        } else {
            _standingDisplayFalseFrames += 1
            _standingDisplayTrueFrames = 0
        }
        if _standingDisplayTrueFrames >= displayDebounceFrames { _stableStanding = true }
        if _standingDisplayFalseFrames >= displayDebounceFrames { _stableStanding = false }

        if hasHead {
            _headFoundDisplayFrames += 1
            _headLostDisplayFrames = 0
        } else {
            _headLostDisplayFrames += 1
            _headFoundDisplayFrames = 0
        }
        if _headFoundDisplayFrames >= displayDebounceFrames { _stableHeadDetected = true }
        if _headLostDisplayFrames >= displayDebounceFrames { _stableHeadDetected = false }

        let stableKnee = _stableKneesOnGround
        let stableForm = _stableFormGood
        let stableBody = _stableBodyDetected
        let stableStand = _stableStanding
        let stableHead = _stableHeadDetected
        let stablePosture = _pushUpPostureActive

        Task { @MainActor [weak self, smoothed, count] in
            guard let self else { return }
            self.bodyDetected = detected
            self.jointPositions = smoothed
            self.poseConfidence = avgConf
            self.leftArmAngle = lAngle
            self.rightArmAngle = rAngle
            self.bodyAlignmentAngle = alignment
            self.leftKneeAngle = lKnee
            self.rightKneeAngle = rKnee
            self.visibleJointCount = count
            self.totalFramesProcessed += 1
            if detected { self.framesWithBody += 1 }
            self.updateCounter += 1
            self.pushUpPhaseLabel = phaseLabel
            self.positioningHint = hint
            self.armsVisible = hasArms
            self.goodDistance = isGoodDist
            self.lowerBodyVisible = hasLowerBody
            self.fullBodyVisible = hasArms && hasHead && hasLowerBody
            self.bodyCenter = CGPoint(x: centerX, y: centerY)
            self.bodySpanX = spanX
            self.bodySpanY = spanY
            self.videoAspectRatio = max(portraitAspectRatio, 0.0001)
            self.kneesOnGround = kneesDown
            self.formGood = goodForm
            self.displayKneesOnGround = stableKnee
            self.displayFormGood = stableForm
            self.displayBodyDetected = stableBody
            self.headDetected = hasHead
            self.displayHeadDetected = stableHead
            self.isStanding = standingDetected
            self.displayStanding = stableStand
            self.inPushUpPosture = stablePosture
            if let inc = newRepCount {
                self.pushUpCount += inc
            }
        }
    }

    nonisolated static func kneeNearAnkleVertically(knee: CGPoint?, ankle: CGPoint?) -> Bool {
        guard let knee, let ankle else { return false }
        let vertDist = abs(knee.y - ankle.y)
        return vertDist < 0.06
    }

    nonisolated static func jointAngle(a: CGPoint?, b: CGPoint?, c: CGPoint?) -> Double {
        guard let a, let b, let c else { return 0 }
        let ba = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let bc = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let dot = ba.x * bc.x + ba.y * bc.y
        let magBA = sqrt(ba.x * ba.x + ba.y * ba.y)
        let magBC = sqrt(bc.x * bc.x + bc.y * bc.y)
        guard magBA > 0, magBC > 0 else { return 0 }
        return acos(min(1, max(-1, dot / (magBA * magBC)))) * 180.0 / .pi
    }

    nonisolated static func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        guard let a, let b else { return a ?? b }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}
