import AVFoundation
import Foundation
import Speech

struct SpeechCaptureResult {
    let transcript: String
    let audioFileURL: URL?
    let localeIdentifier: String
}

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
    private let contextualPhrases = [
        "今天", "明天", "后天", "下周", "下午", "上午", "中午", "晚上",
        "会议", "开会", "客户", "提醒", "日程", "安排", "会议室", "线上会议",
        "腾讯会议", "飞书会议", "面试", "拜访", "机场", "高铁", "早餐会",
        "产品评审", "复盘", "路演", "签约", "出差", "医生预约",
        "拍摄", "航拍", "纪录片", "视频拍摄", "改时间", "改地点", "重复提醒"
    ]

    private(set) var currentLocaleIdentifier = "zh-Hans"
    private var recordingFileURL: URL?
    private var recordingFile: AVAudioFile?

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

        stopRecording(resetTranscript: false)

        let locale = Locale(identifier: localeIdentifier.isEmpty ? defaultLocale.identifier : localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        currentLocaleIdentifier = locale.identifier
        speechRecognizer = recognizer
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw SpeechError.audioSessionFailure
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.contextualStrings = contextualPhrases
        recognitionRequest.requiresOnDeviceRecognition = false
        transcript = ""
        recordingFile = nil
        recordingFileURL = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechError.audioSessionFailure
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let fileURL = try createRecordingFileURL()
        let outputFile = try AVAudioFile(
            forWriting: fileURL,
            settings: recordingFormat.settings,
            commonFormat: recordingFormat.commonFormat,
            interleaved: recordingFormat.isInterleaved
        )

        recordingFileURL = fileURL
        recordingFile = outputFile

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            do {
                try self.recordingFile?.write(from: buffer)
            } catch {
                print("Failed to persist audio buffer: \(error.localizedDescription)")
            }
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
                    self.stopRecording(resetTranscript: false)
                }
            }
        }
    }

    func finishRecording() -> SpeechCaptureResult {
        let result = SpeechCaptureResult(
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            audioFileURL: recordingFileURL,
            localeIdentifier: currentLocaleIdentifier
        )
        stopRecording(resetTranscript: false)
        return result
    }

    func resetTranscript() {
        transcript = ""
    }

    func discardRecording(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func stopRecording(resetTranscript: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recordingFile = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore teardown errors so the user can continue using the app.
        }

        if resetTranscript {
            transcript = ""
            recordingFileURL = nil
        }
    }

    private func createRecordingFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KKPPVoice", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("voice-\(UUID().uuidString).wav")
    }
}
