import AppKit
import AVFoundation
import SwiftUI

@MainActor
@Observable
final class ComposerDictation {
    enum Phase { case idle, downloading, preparing, requestingPermission, recording, transcribing, cancelling }

    private(set) var phase: Phase = .idle
    private(set) var progress = 0.0
    private(set) var elapsed = 0
    private(set) var notice: String?
    private(set) var recoveredTranscript: String?
    private(set) var needsRepair = false
    var showingSetup = false
    private(set) var installed = false

    // One microphone/transcription operation across main-window and floating composers.
    private static var owner: UUID?
    private let id = UUID()
    private let engine = LocalDictationEngine.shared
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private weak var target: ThreadRuntime?
    private var draftID: UUID?
    private var peakPower: Float = -160

    var isBusy: Bool { phase != .idle }
    var isRecording: Bool { phase == .recording }

    /// Refresh system asset availability without requesting microphone access or recording audio.
    func warmUpIfInstalled() async {
        installed = (try? await LocalDictationEngine.isInstalled) ?? false
    }

    func activate(runtime: ThreadRuntime) {
        if isRecording { finishRecording(); return }
        guard !isBusy else { return }
        guard claim() else { return }
        notice = nil
        needsRepair = false
        phase = .preparing
        let token = generation
        operation = Task {
            do {
                installed = try await LocalDictationEngine.isInstalled
                guard generation == token, !Task.isCancelled else { await completeCancellation(); return }
                complete()
                guard NSApp.isActive else { return }
                if installed { start(runtime: runtime) } else { showingSetup = true }
            } catch {
                if generation != token || Task.isCancelled { await completeCancellation(); return }
                notice = (error as? DictationError)?.errorDescription
                    ?? "On-device dictation is unavailable. Try again."
                complete()
            }
        }
    }

    func download() {
        guard claim() else { return }
        notice = nil
        needsRepair = false
        progress = 0
        phase = .downloading
        let token = generation
        operation = Task { [self] in
            do {
                try await engine.install { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.phase == .downloading else { return }
                        self.progress = fraction
                    }
                }
                guard generation == token, !Task.isCancelled else { await completeCancellation(); return }
                installed = true
                showingSetup = false
                notice = "Dictation is ready. Click the microphone to start recording."
                complete()
            } catch {
                if generation != token || Task.isCancelled { await completeCancellation(); return }
                notice = (error as? DictationError)?.errorDescription
                    ?? "Language asset installation failed. Check your connection and available disk space, then retry."
                await engine.release()
                complete()
            }
        }
    }

    private func start(runtime: ThreadRuntime) {
        guard !runtime.isReverting else {
            notice = "Wait for the message rewind to finish before starting dictation."
            return
        }
        guard claim() else { return }
        notice = nil
        needsRepair = false
        recoveredTranscript = nil
        target = runtime
        draftID = runtime.draft.id
        runtime.isDictating = true
        phase = .requestingPermission
        let token = generation
        operation = Task {
            do {
                let granted: Bool
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: granted = true
                case .notDetermined:
                    granted = await AVCaptureDevice.requestAccess(for: .audio)
                    try Task.checkCancellation()
                    guard generation == token else { await completeCancellation(); return }
                    guard granted else { throw DictationError.microphoneDenied }
                    // The system dialog may still own focus when its callback arrives.
                    // Require a fresh click rather than starting a delayed recording.
                    notice = "Microphone enabled. Click the microphone to start recording."
                    complete()
                    return
                default: granted = false
                }
                try Task.checkCancellation()
                guard generation == token else { await completeCancellation(); return }
                guard granted else { throw DictationError.microphoneDenied }
                guard NSApp.isActive else { await completeCancellation(); return }
                try beginRecording()
            } catch {
                if generation != token || Task.isCancelled { await completeCancellation(); return }
                needsRepair = phase == .preparing
                notice = (error as? DictationError)?.errorDescription
                    ?? "Dictation language assets are unavailable. Use Install language assets to try again."
                await engine.release()
                complete()
            }
        }
    }

    private func beginRecording() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ensembyte-dictation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("recording.wav")
        recordingURL = url
        do {
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else { throw DictationError.recordingFailed }
            self.recorder = recorder
            phase = .recording
            elapsed = 0
            peakPower = -160
            operation = nil
            let started = Date()
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, !Task.isCancelled, self.phase == .recording else { return }
                    self.elapsed = Int(Date().timeIntervalSince(started))
                    self.recorder?.updateMeters()
                    self.peakPower = max(self.peakPower, self.recorder?.peakPower(forChannel: 0) ?? -160)
                    if self.recorder?.isRecording != true {
                        self.finishRecording()
                        return
                    }
                }
            }
        } catch {
            removeRecording()
            throw DictationError.recordingFailed
        }
    }

    func finishRecording() {
        guard phase == .recording, let url = recordingURL else { return }
        timer?.cancel()
        timer = nil
        recorder?.stop()
        recorder = nil
        phase = .preparing
        let token = generation
        operation = Task {
            do {
                // Read the finalized file: currentTime is valid only while recording.
                let audio = try AVAudioFile(forReading: url)
                let duration = Double(audio.length) / audio.processingFormat.sampleRate
                guard duration > 0.3, peakPower > -55 else { throw DictationError.noSpeech }
                // Check assets after capture so preparation cannot delay microphone recording.
                try await engine.prepare()
                try Task.checkCancellation()
                guard generation == token else { await completeCancellation(); return }
                phase = .transcribing
                let text = try await engine.transcribe(path: url.path)
                guard generation == token, !Task.isCancelled else { await completeCancellation(); return }
                guard !text.isEmpty else { throw DictationError.noSpeech }
                if let target, target.draft.id == draftID {
                    let separator = target.draft.text.isEmpty || target.draft.text.last?.isWhitespace == true ? "" : " "
                    target.draft.text += separator + text
                    notice = nil
                } else {
                    recoveredTranscript = text
                    notice = "Your draft changed during dictation. Copy the transcript below to keep it."
                }
                complete()
            } catch {
                if generation != token || Task.isCancelled { await completeCancellation(); return }
                needsRepair = phase == .preparing
                notice = (error as? DictationError)?.errorDescription
                    ?? (needsRepair ? "Dictation language assets are unavailable. Install language assets to try again."
                        : "Transcription failed. Your draft has not changed. Try recording again.")
                await engine.release()
                complete()
            }
        }
    }

    func cancel() {
        showingSetup = false
        guard isBusy, phase != .cancelling else { return }
        generation = UUID()
        timer?.cancel()
        timer = nil
        recorder?.stop()
        recorder = nil
        phase = .cancelling
        removeRecording()
        if let operation {
            operation.cancel()
        } else {
            operation = Task { await completeCancellation() }
        }
    }

    func dismissNotice() { notice = nil; recoveredTranscript = nil }

    private func claim() -> Bool {
        guard !isBusy, Self.owner == nil else {
            notice = "Dictation is already active in another chat. Stop or cancel it there first."
            return false
        }
        Self.owner = id
        generation = UUID()
        return true
    }

    private func completeCancellation() async {
        await engine.release()
        notice = "Dictation cancelled. Your draft has not changed."
        complete()
    }

    private func complete() {
        removeRecording()
        target?.isDictating = false
        target = nil
        draftID = nil
        if Self.owner == id { Self.owner = nil }
        operation = nil
        phase = .idle
    }

    private func removeRecording() {
        guard let recordingURL else { return }
        // This is the per-recording private temporary directory, never a shared cache.
        try? FileManager.default.removeItem(at: recordingURL.deletingLastPathComponent())
        self.recordingURL = nil
    }
}

struct ComposerDictationButton: View {
    let runtime: ThreadRuntime
    @Bindable var dictation: ComposerDictation

    var body: some View {
        Button { dictation.activate(runtime: runtime) } label: {
            Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic")
                .font(Chrome.iconFont)
        }
        .buttonStyle(.chip(active: dictation.isRecording))
        .disabled(dictation.isBusy && !dictation.isRecording)
        .help(dictation.isRecording ? "Stop recording and transcribe" : "Dictate into this draft")
        .accessibilityLabel(dictation.isRecording ? "Stop recording and transcribe" : "Dictate into this draft")
        .contextMenu {
            Button("Install dictation language assets") { dictation.showingSetup = true }
                .disabled(dictation.isBusy)
        }
        .sheet(isPresented: $dictation.showingSetup) { setup }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Private dictation", systemImage: "mic").font(.headline)
            Text("Install Apple speech assets to transcribe on this Mac. No account, API key, or payment is needed.")
            Text("macOS downloads and manages the speech assets for your current language. Unsupported languages use US English when available. Accuracy varies by language and background noise; review every transcript.")
                .foregroundStyle(.secondary)
            Text("Audio is recorded only after you click the microphone and allow macOS access. A temporary recording is deleted when transcription finishes or you cancel. Nothing is sent to a speech service. Text goes into your draft for editing, never directly to the chat.")
                .foregroundStyle(.secondary)
            if dictation.phase == .downloading {
                ProgressView(value: dictation.progress)
                Text(dictation.progress < 1 ? "Installing language assets… \(Int(dictation.progress * 100))%" : "Preparing dictation on this Mac…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let notice = dictation.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Button(dictation.isBusy ? "Cancel download" : "Cancel") { dictation.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Install language assets") { dictation.download() }
                    .buttonStyle(.borderedProminent)
                    .disabled(dictation.isBusy)
            }
        }
        .padding(24)
        .frame(width: 440)
        .interactiveDismissDisabled(dictation.isBusy)
    }
}

struct ComposerDictationStatus: View {
    let dictation: ComposerDictation

    var body: some View {
        if dictation.isBusy || dictation.notice != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    if dictation.isBusy && !dictation.isRecording { ProgressView().controlSize(.small) }
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel(status)
                    Spacer(minLength: 4)
                    if dictation.isRecording {
                        Button("Stop") { dictation.finishRecording() }
                            .accessibilityLabel("Stop recording and transcribe")
                    }
                    Button(dictation.isBusy ? "Cancel" : "Dismiss") {
                        if dictation.isBusy { dictation.cancel() } else { dictation.dismissNotice() }
                    }
                    .disabled(dictation.phase == .cancelling)
                    if !dictation.isBusy && dictation.needsRepair {
                        Button("Install language assets") { dictation.showingSetup = true }
                    }
                }
                .buttonStyle(.borderless)
                if let transcript = dictation.recoveredTranscript {
                    Text(transcript).font(.callout).textSelection(.enabled)
                    Button("Copy transcript") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcript, forType: .string)
                    }.buttonStyle(.borderless)
                }
            }
        }
    }

    private var status: String {
        switch dictation.phase {
        case .idle: dictation.notice ?? ""
        case .downloading: "Installing dictation language assets…"
        case .preparing: "Preparing local transcription…"
        case .requestingPermission: "Waiting for microphone permission…"
        case .recording: "Recording · \(dictation.elapsed / 60):\(String(format: "%02d", dictation.elapsed % 60)) · Stop when finished"
        case .transcribing: "Transcribing on this Mac…"
        case .cancelling: "Cancelling dictation…"
        }
    }
}
