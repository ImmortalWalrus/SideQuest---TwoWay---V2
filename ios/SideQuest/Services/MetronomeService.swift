import AVFoundation

@Observable
class MetronomeService {
    var bpm: Int = 120
    var isPlaying: Bool = false
    var currentBeat: Int = 0
    var onBeatJumps: Int = 0
    var missedBeatCount: Int = 0
    var lastBeatHadJump: Bool = true
    private var jumpRegisteredThisBeat: Bool = false

    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var tickPlayer: AVAudioPlayer?
    private var beatWindow: TimeInterval = 0.15
    private var lastBeatTime: Date?

    var beatInterval: TimeInterval {
        60.0 / Double(bpm)
    }

    func start() {
        setupAudioSession()
        isPlaying = true
        currentBeat = 0
        onBeatJumps = 0
        missedBeatCount = 0
        lastBeatHadJump = true
        jumpRegisteredThisBeat = false
        lastBeatTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: beatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func updateBPM(_ newBPM: Int) {
        bpm = max(60, min(200, newBPM))
        if isPlaying {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: beatInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
        }
    }

    func checkJumpOnBeat() -> Bool {
        guard let lastBeat = lastBeatTime else { return false }
        let timeSinceBeat = Date().timeIntervalSince(lastBeat)
        let isOnBeat = timeSinceBeat <= beatWindow || (beatInterval - timeSinceBeat) <= beatWindow
        if isOnBeat {
            onBeatJumps += 1
            jumpRegisteredThisBeat = true
        }
        return isOnBeat
    }

    private func tick() {
        if currentBeat > 0 && !jumpRegisteredThisBeat {
            missedBeatCount += 1
            lastBeatHadJump = false
        } else {
            lastBeatHadJump = true
        }
        jumpRegisteredThisBeat = false
        currentBeat += 1
        lastBeatTime = Date()
        playTick()
    }

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func playTick() {
        let systemSoundID: SystemSoundID = 1057
        AudioServicesPlaySystemSound(systemSoundID)
    }
}
