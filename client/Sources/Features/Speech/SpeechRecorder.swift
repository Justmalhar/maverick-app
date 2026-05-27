// client/Sources/Features/Speech/SpeechRecorder.swift
import Foundation
import AVFoundation
import Observation

@Observable
final class SpeechRecorder: NSObject {
    enum State: Equatable { case idle, recording, transcribing, error(String) }

    var state: State = .idle
    /// 0...1 normalized peak level for live waveform animation.
    var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var levelTimer: Timer?

    func start() async {
        guard state == .idle || state == .transcribing else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            await MainActor.run { self.state = .error("audio session: \(error.localizedDescription)") }
            return
        }

        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { ok in cont.resume(returning: ok) }
        }
        guard granted else {
            await MainActor.run { self.state = .error("microphone permission denied") }
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            r.record()
            recorder = r
            fileURL = url
            await MainActor.run {
                self.state = .recording
                self.startMetering()
            }
        } catch {
            await MainActor.run { self.state = .error("recorder: \(error.localizedDescription)") }
        }
    }

    /// Stops recording and returns the file URL of the captured audio (caller should delete after upload).
    @MainActor
    func stop() -> URL? {
        recorder?.stop()
        stopMetering()
        let url = fileURL
        recorder = nil
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    private func startMetering() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            // Average power is in dB, ~-160 (silence) to 0 (peak). Map to 0...1.
            let power = r.averagePower(forChannel: 0)
            let normalized = max(0, min(1, (power + 50) / 50))
            DispatchQueue.main.async { self.level = Double(normalized) }
        }
    }

    private func stopMetering() {
        levelTimer?.invalidate(); levelTimer = nil
        level = 0
    }
}
