import AVFoundation
import Vision

@Observable
class JumpRopeDetectionService: NSObject {
    var jumpCount: Int = 0
    var isBodyDetected: Bool = false
    var currentConfidence: Double = 0
    var bodyLostCount: Int = 0
    var totalFramesAnalyzed: Int = 0
    var framesWithBody: Int = 0
    var bestStreak: Int = 0
    var currentStreak: Int = 0
    var jointPositions: [String: CGPoint] = [:]
    var visibleJointCount: Int = 0
    var positioningHint: PositioningHint = .none
    var displayBodyDetected: Bool = false
    var goodDistance: Bool = false
    var fullBodyVisible: Bool = false
    private(set) var cameraAvailable: Bool = false
    private(set) var isConfigured: Bool = false

    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated(unsafe) private let sessionQueue = DispatchQueue(label: "jumpRopeCamera")
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let videoQueue = DispatchQueue(label: "jumpRopeVideoQueue")
    nonisolated(unsafe) private var frameCount: Int = 0
    nonisolated(unsafe) private var smoothedJoints: [String: CGPoint] = [:]
    nonisolated(unsafe) private var bodyDisplayFoundFrames: Int = 0
    nonisolated(unsafe) private var bodyDisplayLostFrames: Int = 0
    nonisolated(unsafe) private var stableBodyDetected: Bool = false

    private let displayDebounceFrames: Int = 4
    nonisolated(unsafe) private var previousAnkleY: CGFloat?
    nonisolated(unsafe) private var isInJump: Bool = false
    private let jumpThreshold: CGFloat = 0.012
    nonisolated(unsafe) private var lastJumpTime: Date?
    private let minJumpInterval: TimeInterval = 0.15
    private(set) var countingEnabled: Bool = false

    var positioningReady: Bool {
        displayBodyDetected && goodDistance && fullBodyVisible && positioningHint == .goodPosition
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        sessionQueue.async { [weak self] in
            self?.setupSession()
        }
    }

    func start() {
        configure()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    nonisolated private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            captureSession.commitConfiguration()
            Task { @MainActor in
                self.cameraAvailable = false
            }
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
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

        Task { @MainActor in
            self.cameraAvailable = true
        }

        captureSession.startRunning()
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    func reset() {
        jumpCount = 0
        isBodyDetected = false
        currentConfidence = 0
        bodyLostCount = 0
        totalFramesAnalyzed = 0
        framesWithBody = 0
        bestStreak = 0
        currentStreak = 0
        jointPositions = [:]
        visibleJointCount = 0
        positioningHint = .none
        displayBodyDetected = false
        goodDistance = false
        fullBodyVisible = false
        previousAnkleY = nil
        isInJump = false
        lastJumpTime = nil
        frameCount = 0
        countingEnabled = false
        smoothedJoints = [:]
        bodyDisplayFoundFrames = 0
        bodyDisplayLostFrames = 0
        stableBodyDetected = false
    }

    func setCountingEnabled(_ enabled: Bool) {
        countingEnabled = enabled
        currentStreak = 0
        previousAnkleY = nil
        isInJump = false
        lastJumpTime = nil
    }

    nonisolated private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest { [weak self] request, _ in
            guard let self else { return }
            let pose = (request.results as? [VNHumanBodyPoseObservation])?.first
            self.analyzePose(pose)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
    }

    nonisolated private func analyzePose(_ pose: VNHumanBodyPoseObservation?) {
        let mapping: [(VNHumanBodyPoseObservation.JointName, String)] = [
            (.nose, "nose"),
            (.leftEar, "leftEar"), (.rightEar, "rightEar"),
            (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
            (.leftElbow, "leftElbow"), (.rightElbow, "rightElbow"),
            (.leftWrist, "leftWrist"), (.rightWrist, "rightWrist"),
            (.leftHip, "leftHip"), (.rightHip, "rightHip"),
            (.leftKnee, "leftKnee"), (.rightKnee, "rightKnee"),
            (.leftAnkle, "leftAnkle"), (.rightAnkle, "rightAnkle")
        ]

        var rawJoints: [String: CGPoint] = [:]
        var totalConfidence: Float = 0
        var visibleCount: Int = 0

        if let pose {
            for (joint, name) in mapping {
                if let point = try? pose.recognizedPoint(joint), point.confidence > 0.15 {
                    rawJoints[name] = point.location
                    totalConfidence += point.confidence
                    visibleCount += 1
                }
            }
        }

        let detected = visibleCount >= 6
        let averageConfidence = visibleCount > 0 ? Double(totalConfidence / Float(visibleCount)) : 0

        if detected {
            bodyDisplayFoundFrames += 1
            bodyDisplayLostFrames = 0
        } else {
            bodyDisplayLostFrames += 1
            bodyDisplayFoundFrames = 0
        }
        if bodyDisplayFoundFrames >= displayDebounceFrames {
            stableBodyDetected = true
        }
        if bodyDisplayLostFrames >= displayDebounceFrames {
            stableBodyDetected = false
        }

        var smoothed: [String: CGPoint] = [:]
        let alpha: Double = 0.55
        for (name, rawPoint) in rawJoints {
            if let previous = smoothedJoints[name] {
                smoothed[name] = CGPoint(
                    x: previous.x + alpha * (rawPoint.x - previous.x),
                    y: previous.y + alpha * (rawPoint.y - previous.y)
                )
            } else {
                smoothed[name] = rawPoint
            }
        }
        smoothedJoints = smoothed

        let shoulderMid = ExerciseCameraService.midpoint(smoothed["leftShoulder"], smoothed["rightShoulder"])
        let hipMid = ExerciseCameraService.midpoint(smoothed["leftHip"], smoothed["rightHip"])
        let kneeMid = ExerciseCameraService.midpoint(smoothed["leftKnee"], smoothed["rightKnee"])
        let ankleMid = ExerciseCameraService.midpoint(smoothed["leftAnkle"], smoothed["rightAnkle"])

        let hasUpperBody = shoulderMid != nil && hipMid != nil
        let hasLowerBody = kneeMid != nil && ankleMid != nil
        let fullBodyVisible = hasUpperBody && hasLowerBody

        let allXs = smoothed.values.map(\.x)
        let allYs = smoothed.values.map(\.y)
        let centerX = allXs.isEmpty ? 0.5 : allXs.reduce(0, +) / Double(allXs.count)
        let spanX = (allXs.max() ?? 0.5) - (allXs.min() ?? 0.5)
        let spanY = (allYs.max() ?? 0.5) - (allYs.min() ?? 0.5)
        let bodySpan = max(spanX, spanY)
        let isGoodDistance = bodySpan >= 0.22 && bodySpan <= 0.9

        let hint: PositioningHint
        if !detected {
            hint = .noBody
        } else if bodySpan > 0.9 {
            hint = .tooClose
        } else if bodySpan < 0.22 {
            hint = .tooFar
        } else if centerX < 0.25 {
            hint = .moveRight
        } else if centerX > 0.75 {
            hint = .moveLeft
        } else if !hasUpperBody && hasLowerBody {
            hint = .tiltUp
        } else if hasUpperBody && !hasLowerBody {
            hint = .tiltDown
        } else if fullBodyVisible {
            hint = .goodPosition
        } else {
            hint = .noBody
        }

        Task { @MainActor in
            self.totalFramesAnalyzed += 1
            self.isBodyDetected = detected
            self.displayBodyDetected = self.stableBodyDetected
            self.framesWithBody += detected ? 1 : 0
            self.currentConfidence = averageConfidence
            self.jointPositions = smoothed
            self.visibleJointCount = visibleCount
            self.positioningHint = hint
            self.goodDistance = isGoodDistance
            self.fullBodyVisible = fullBodyVisible

            guard self.countingEnabled else {
                self.previousAnkleY = ankleMid?.y
                self.isInJump = false
                if !detected {
                    self.bodyLostCount += 1
                }
                return
            }

            guard fullBodyVisible, let ankleY = ankleMid?.y, let hipY = hipMid?.y else {
                self.previousAnkleY = ankleMid?.y
                self.isInJump = false
                if !detected {
                    self.bodyLostCount += 1
                }
                return
            }

            if let previousAnkleY = self.previousAnkleY {
                let ankleRise = ankleY - previousAnkleY
                let hipAnkleDelta = hipY - ankleY

                if ankleRise > self.jumpThreshold && hipAnkleDelta > 0.05 && !self.isInJump {
                    let now = Date()
                    let timeSinceLastJump = self.lastJumpTime.map { now.timeIntervalSince($0) } ?? 1.0
                    if timeSinceLastJump >= self.minJumpInterval {
                        self.isInJump = true
                        self.jumpCount += 1
                        self.currentStreak += 1
                        self.bestStreak = max(self.bestStreak, self.currentStreak)
                        self.lastJumpTime = now
                    }
                } else if ankleRise < -self.jumpThreshold * 0.5 {
                    self.isInJump = false
                }
            }

            self.previousAnkleY = ankleY
        }
    }

    func recordMissedBeat() {
        currentStreak = 0
    }
}

extension JumpRopeDetectionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % 2 == 0 else { return }
        processFrame(sampleBuffer)
    }
}
