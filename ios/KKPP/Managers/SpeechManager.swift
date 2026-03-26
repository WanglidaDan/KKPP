import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechManager: NSObject, ObservableObject {
    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case permissionDenied
        case audioSessionFailure

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "语音识别暂时不可用，请稍后再试。"
            case .permissionDenied:
                return "请在系统设置中开启麦克风和语音识别权限。"
            case .audioSessionFailure:
                return "录音启动失败，请重新尝试。"
            }
        }
    }

    @Published var transcript = ""
    @Published var isRecording = false
    @Published var microphoneAuthorized = false
    @Published var speechAuthorized = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private let defaultLocale = Locale(identifier: "zh-Hans")

    func requestPermissions() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let micAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }

        speechAuthorized = speechStatus == .authorized
        microphoneAuthorized = micAllowed
    }

    func startRecording(localeIdentifier: String = "zh-Hans") async throws {
        guard microphoneAuthorized, speechAuthorized else {
            throw SpeechError.permissionDenied
        }

        stopRecording()

        let locale = Locale(identifier: localeIdentifier.isEmpty ? defaultLocale.identifier : localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        speechRecognizer = recognizer
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw SpeechError.audioSessionFailure
        }

        recognitionRequest.shouldReportPartialResults = true
        transcript = ""

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechError.audioSessionFailure
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.audioSessionFailure
        }

        isRecording = true
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }

            if error != nil {
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
    }
}
