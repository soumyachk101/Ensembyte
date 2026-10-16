import AVFoundation
import Foundation
import Speech

#if !COMPILER_PRE_MACOS26
actor LocalDictationEngine {
    static let shared = LocalDictationEngine()

    static var isInstalled: Bool {
        get async throws {
            let transcriber = try await makeTranscriber()
            return await AssetInventory.status(forModules: [transcriber]) == .installed
        }
    }

    private var isInstalling = false
    private var isTranscribing = false
    private var analyzer: SpeechAnalyzer?

    private static func makeTranscriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw DictationError.modelUnavailable }
        let locale: Locale
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            locale = supported
        } else if let english = await SpeechTranscriber.supportedLocales.first(where: {
            $0.identifier.replacingOccurrences(of: "_", with: "-") == "en-US"
        }) {
            locale = english
        } else {
            throw DictationError.modelUnavailable
        }
        try Task.checkCancellation()
        return SpeechTranscriber(locale: locale, preset: .transcription)
    }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !isInstalling, !isTranscribing else { throw DictationError.modelUnavailable }
        isInstalling = true
        defer { isInstalling = false }
        let transcriber = try await Self.makeTranscriber()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let downloadProgress = request.progress
            let observation = downloadProgress.observe(\.fractionCompleted, options: [.initial, .new]) { value, _ in
                progress(value.fractionCompleted)
            }
            defer { observation.invalidate() }
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await request.downloadAndInstall()
            } onCancel: {
                downloadProgress.cancel()
            }
        }
        try Task.checkCancellation()
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw DictationError.assetsNotInstalled
        }
        progress(1)
    }

    /// Check system-managed assets without starting a download or opening the microphone.
    func prepare() async throws {
        try Task.checkCancellation()
        guard !isInstalling else { throw DictationError.modelUnavailable }
        guard try await Self.isInstalled else { throw DictationError.assetsNotInstalled }
        try Task.checkCancellation()
    }

    func transcribe(path: String) async throws -> String {
        try Task.checkCancellation()
        guard !isInstalling, !isTranscribing else { throw DictationError.modelUnavailable }
        isTranscribing = true
        defer {
            analyzer = nil
            isTranscribing = false
        }
        let transcriber = try await Self.makeTranscriber()
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw DictationError.assetsNotInstalled
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        return try await withTaskCancellationHandler {
            let results = Task {
                var text = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    if result.isFinal { text += String(result.text.characters) }
                }
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            do {
                try Task.checkCancellation()
                let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
                if let lastSample = try await analyzer.analyzeSequence(from: file) {
                    try Task.checkCancellation()
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let text = try await results.value
                try Task.checkCancellation()
                return text
            } catch {
                await analyzer.cancelAndFinishNow()
                results.cancel()
                _ = try? await results.value
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// An in-flight transcription finishes its own analyzer before releasing the composer.
    func release() async {
        guard !isTranscribing else { return }
        if let analyzer { await analyzer.cancelAndFinishNow() }
        analyzer = nil
    }
}
#else
actor LocalDictationEngine {
    static let shared = LocalDictationEngine()

    static var isInstalled: Bool {
        get async throws { false }
    }

    private var isInstalling = false
    private var isTranscribing = false

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        throw DictationError.modelUnavailable
    }

    func prepare() async throws {
        throw DictationError.modelUnavailable
    }

    func transcribe(path: String) async throws -> String {
        throw DictationError.modelUnavailable
    }

    func release() async {}
}
#endif

enum DictationError: LocalizedError {
    case modelUnavailable, assetsNotInstalled, microphoneDenied, recordingFailed, noSpeech

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: "On-device dictation is unavailable for this Mac or language."
        case .assetsNotInstalled: "Dictation language assets are not installed. Install them from the microphone menu."
        case .microphoneDenied: "Microphone access is off. Enable Ensembyte in System Settings → Privacy & Security → Microphone, then try again."
        case .recordingFailed: "The microphone could not record. Check your input device in System Settings → Sound, then try again."
        case .noSpeech: "No speech was recognized. Try again closer to the microphone."
        }
    }
}
