import Foundation
import AVFoundation
import WebKit
#if os(iOS)
import Speech
#endif

/// Assistant vocal : reconnaissance de la voix (français), bips et réponse parlée.
final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()
    weak var web: WKWebView?
    private let synth = AVSpeechSynthesizer()
    private var beepPlayer: AVAudioPlayer?

    override init() {
        super.init()
        synth.delegate = self
    }

    // Fin d'une phrase : la page enchaîne et met en surbrillance l'élément suivant
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        js("window.onSpeakEnd && window.onSpeakEnd()")
    }

    private func js(_ s: String) {
        DispatchQueue.main.async { self.web?.evaluateJavaScript(s, completionHandler: nil) }
    }
    private func quoted(_ s: String) -> String {
        guard let d = try? JSONEncoder().encode(s), let r = String(data: d, encoding: .utf8) else { return "\"\"" }
        return r
    }

    // MARK: Bips (monte = j'écoute, descend = j'ai fini d'écouter)
    func beep(up: Bool) {
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? s.setActive(true)
        #endif
        playBeep(up: up)
    }

    private func playBeep(up: Bool) {
        let rate = 44100.0, n = Int(rate * 0.17)
        let f0 = up ? 660.0 : 880.0, f1 = up ? 990.0 : 550.0
        var pcm = [Int16](), phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            phase += 2 * Double.pi * (f0 + (f1 - f0) * t) / rate
            let env = min(1, t * 12) * min(1, (1 - t) * 6)
            pcm.append(Int16(sin(phase) * env * 0.4 * 32767))
        }
        var d = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func put16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); put32(UInt32(36 + pcm.count * 2))
        d.append("WAVEfmt ".data(using: .ascii)!); put32(16); put16(1); put16(1)
        put32(UInt32(rate)); put32(UInt32(rate) * 2); put16(2); put16(16)
        d.append("data".data(using: .ascii)!); put32(UInt32(pcm.count * 2))
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        beepPlayer = try? AVAudioPlayer(data: d)
        beepPlayer?.play()
    }

    // MARK: Voix de réponse
    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? s.setActive(true)
        #endif
        let u = AVSpeechUtterance(string: text)
        let fr = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "fr-FR" }
        u.voice = fr.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: "fr-FR")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }
    func stopSpeaking() { synth.stopSpeaking(at: .immediate) }

    #if os(iOS)
    // MARK: Reconnaissance vocale
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var lastText = ""
    private var active = false

    /// Micro ouvert tout de suite (avec un bip) jusqu'à la fin de la question. Les autorisations ne sont
    /// demandées qu'une seule fois : iOS les mémorise ensuite, plus aucune question.
    func listen() {
        synth.stopSpeaking(at: .immediate)
        let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micOK = AVAudioSession.sharedInstance().recordPermission == .granted
        if speechOK && micOK { begin(); return }
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { DispatchQueue.main.async { self.fail("not-allowed") }; return }
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                DispatchQueue.main.async { ok ? self.begin() : self.fail("not-allowed") }
            }
        }
    }

    private func begin() {
        teardown()
        guard let rec = recognizer, rec.isAvailable else { fail("service-not-available"); return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try s.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { fail("audio"); return }

        active = true
        lastText = ""
        startEngine(rec)                         // le micro s'ouvre immédiatement
        playBeep(up: true)                       // un seul bip : « parle maintenant »
        arm(12)                                  // si personne ne parle
    }

    private func startEngine(_ rec: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { fail("audio"); return }

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self, self.active else { return }
            if let r = result {
                self.lastText = r.bestTranscription.formattedString
                DispatchQueue.main.async { self.arm(2.0) }   // micro ouvert tant que tu parles
                if r.isFinal { DispatchQueue.main.async { self.finish() } }
            } else if error != nil {
                DispatchQueue.main.async { self.finish() }
            }
        }
    }

    private func arm(_ delay: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.finish() }
    }

    /// Question terminée : micro coupé, texte envoyé à la page (qui répond).
    func finish() {
        guard active else { return }
        let t = lastText
        teardown()
        if t.isEmpty { js("window.onSpeechErr('no-speech')") } else { js("window.onSpeech(\(quoted(t)), true)") }
    }

    private func fail(_ m: String) {
        teardown()
        js("window.onSpeechErr(\(quoted(m)))")
    }

    private func teardown() {
        active = false
        timer?.invalidate(); timer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
    }
    #else
    func listen() { js("window.onSpeechErr('not-allowed')") }
    func finish() {}
    #endif
}
