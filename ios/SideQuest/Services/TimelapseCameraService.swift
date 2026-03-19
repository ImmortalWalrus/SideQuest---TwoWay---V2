import AVFoundation
import UIKit

@Observable
final class TimelapseCameraService: NSObject {
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated(unsafe) private let sessionQueue = DispatchQueue(label: "TimelapseCameraService.session")
    private(set) var isConfigured: Bool = false
    private(set) var isRunning: Bool = false
    private(set) var capturedImage: UIImage?
    var recordedVideoURL: URL?

    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?
    private var movieContinuation: CheckedContinuation<URL?, Never>?

    func configure(front: Bool = false, includeAudio: Bool = false) {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if includeAudio,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        let photo = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photo) {
            captureSession.addOutput(photo)
            photoOutput = photo
        }

        let movie = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movie) {
            captureSession.addOutput(movie)
            movieOutput = movie
        }

        captureSession.commitConfiguration()
        isConfigured = true
    }

    func start() {
        guard isConfigured, !isRunning else { return }
        isRunning = true
        let session = captureSession
        sessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let session = captureSession
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func capturePhoto() async -> UIImage? {
        guard let photoOutput else { return nil }
        return await withCheckedContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startVideoRecording() async {
        guard let movieOutput, !movieOutput.isRecording else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: ())
                    return
                }
                movieOutput.startRecording(to: tempURL, recordingDelegate: self)
                continuation.resume(returning: ())
            }
        }
    }

    func stopVideoRecording() async -> URL? {
        guard let movieOutput, movieOutput.isRecording else { return nil }
        return await withCheckedContinuation { continuation in
            movieContinuation = continuation
            sessionQueue.async {
                movieOutput.stopRecording()
            }
        }
    }
}

extension TimelapseCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = nil
        }
        Task { @MainActor in
            self.capturedImage = image
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}

extension TimelapseCameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let url = error == nil ? outputFileURL : nil
        Task { @MainActor in
            self.recordedVideoURL = url
            self.movieContinuation?.resume(returning: url)
            self.movieContinuation = nil
        }
    }
}
