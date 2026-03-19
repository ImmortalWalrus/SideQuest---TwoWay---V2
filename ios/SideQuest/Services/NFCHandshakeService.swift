import Foundation
import CoreNFC

@Observable
class NFCHandshakeService: NSObject {
    private(set) var isScanning: Bool = false
    private(set) var lastReadToken: String?
    private(set) var errorMessage: String?
    private var session: NFCNDEFReaderSession?
    var onTokenRead: ((String) -> Void)?

    var isNFCAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }

    func scanForGroupToken() {
        guard isNFCAvailable else {
            errorMessage = "NFC not available on this device"
            return
        }
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Hold your phone near your teammate's NFC tag to verify handshake"
        session?.begin()
        isScanning = true
        errorMessage = nil
    }

    func stopScanning() {
        session?.invalidate()
        session = nil
        isScanning = false
    }
}

extension NFCHandshakeService: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                if let url = record.wellKnownTypeURIPayload(),
                   url.scheme == "sidequest",
                   url.host == "group" {
                    let token = url.lastPathComponent
                    Task { @MainActor in
                        self.lastReadToken = token
                        self.isScanning = false
                        self.onTokenRead?(token)
                    }
                    return
                }
            }
        }
        Task { @MainActor in
            self.isScanning = false
            self.errorMessage = "No SideQuest group found on tag"
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
        }
    }

    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}
}
