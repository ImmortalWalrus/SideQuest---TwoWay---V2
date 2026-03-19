import AVFoundation
import UIKit

@Observable
final class DualCameraService: NSObject {
    nonisolated(unsafe) let multiCamSession = AVCaptureMultiCamSession()
    nonisolated(unsafe) let rearPreviewLayer = AVCaptureVideoPreviewLayer()
    nonisolated(unsafe) let frontPreviewLayer = AVCaptureVideoPreviewLayer()

    nonisolated(unsafe) private let sessionQueue = DispatchQueue(label: "DualCameraService.session")
    private var rearOutput: AVCapturePhotoOutput?
    private var frontOutput: AVCapturePhotoOutput?
    private var rearPhotoContinuation: CheckedContinuation<UIImage?, Never>?
    private var frontPhotoContinuation: CheckedContinuation<UIImage?, Never>?

    private(set) var isConfigured: Bool = false
    private(set) var isRunning: Bool = false
    private(set) var supportsMultiCam: Bool = AVCaptureMultiCamSession.isMultiCamSupported
    private(set) var rearImage: UIImage?
    private(set) var frontImage: UIImage?

    func configureAndStart() {
        guard !isConfigured, supportsMultiCam else {
            if isConfigured { startBoth() }
            return
        }

        let session = multiCamSession
        let rearLayer = rearPreviewLayer
        let frontLayer = frontPreviewLayer

        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            session.sessionPreset = .inputPriority

            rearLayer.setSessionWithNoConnection(session)
            rearLayer.videoGravity = .resizeAspectFill
            frontLayer.setSessionWithNoConnection(session)
            frontLayer.videoGravity = .resizeAspectFill

            let rearOK = Self.addCamera(position: .back, to: session, previewLayer: rearLayer, mirrored: false)
            let frontOK = Self.addCamera(position: .front, to: session, previewLayer: frontLayer, mirrored: true)

            var rOut: AVCapturePhotoOutput?
            var fOut: AVCapturePhotoOutput?
            for output in session.outputs {
                if let photo = output as? AVCapturePhotoOutput {
                    let conn = photo.connections.first
                    let pos = conn?.inputPorts.first?.sourceDevicePosition
                    if pos == .back { rOut = photo }
                    else if pos == .front { fOut = photo }
                }
            }

            session.commitConfiguration()

            let configured = rearOK && frontOK

            if configured {
                session.startRunning()
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rearOutput = rOut
                self.frontOutput = fOut
                self.isConfigured = configured
                self.isRunning = configured && session.isRunning
            }
        }
    }

    nonisolated private static func addCamera(
        position: AVCaptureDevice.Position,
        to session: AVCaptureMultiCamSession,
        previewLayer: AVCaptureVideoPreviewLayer,
        mirrored: Bool
    ) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }

        session.addInputWithNoConnections(input)

        guard let videoPort = input.ports.first(where: { $0.mediaType == .video }) else {
            return false
        }

        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutputWithNoConnections(photoOutput)

        let photoConnection = AVCaptureConnection(inputPorts: [videoPort], output: photoOutput)
        guard session.canAddConnection(photoConnection) else { return false }
        session.addConnection(photoConnection)
        if photoConnection.isVideoMirroringSupported {
            photoConnection.automaticallyAdjustsVideoMirroring = false
            photoConnection.isVideoMirrored = mirrored
        }

        let previewConnection = AVCaptureConnection(inputPort: videoPort, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else { return false }
        session.addConnection(previewConnection)
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = mirrored
        }

        return true
    }

    func startBoth() {
        guard isConfigured else { return }
        let session = multiCamSession
        sessionQueue.async { [weak self] in
            guard !session.isRunning else { return }
            session.startRunning()
            Task { @MainActor in self?.isRunning = true }
        }
    }

    func stopBoth() {
        let session = multiCamSession
        sessionQueue.async { [weak self] in
            guard session.isRunning else { return }
            session.stopRunning()
            Task { @MainActor in self?.isRunning = false }
        }
    }

    func captureBoth() async {
        guard isConfigured else { return }
        async let rearCapture = capturePhoto(from: rearOutput, isFrontCamera: false)
        async let frontCapture = capturePhoto(from: frontOutput, isFrontCamera: true)

        rearImage = await rearCapture
        frontImage = await frontCapture
    }

    private func capturePhoto(from output: AVCapturePhotoOutput?, isFrontCamera: Bool) async -> UIImage? {
        guard let output else { return nil }

        return await withCheckedContinuation { continuation in
            if isFrontCamera {
                frontPhotoContinuation = continuation
            } else {
                rearPhotoContinuation = continuation
            }

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func reset() {
        rearImage = nil
        frontImage = nil
    }
}

extension DualCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = nil
        }

        Task { @MainActor in
            if output === self.frontOutput {
                self.frontPhotoContinuation?.resume(returning: image)
                self.frontPhotoContinuation = nil
            } else {
                self.rearPhotoContinuation?.resume(returning: image)
                self.rearPhotoContinuation = nil
            }
        }
    }
}
