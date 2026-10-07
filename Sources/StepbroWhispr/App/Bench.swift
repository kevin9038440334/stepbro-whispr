import AVFoundation
import Foundation
import StepbroWhisprCore

/// Banco de pruebas: `SUSURRO_BENCH=/carpeta` procesa cada audio (.wav o .m4a) de la carpeta con la cadena
/// completa (Apple + Whisper + pulido) sin pegar nada, y escribe tiempos y textos en informe.txt.
extension AppState {
    func runBenchIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["SUSURRO_BENCH"] else { return }
        let directory = URL(fileURLWithPath: folder)
        let target = DictationTarget(appName: environment["SUSURRO_BENCH_APPNAME"], bundleID: environment["SUSURRO_BENCH_APP"])
        Task {
            var lines: [String] = []
            func write() {
                try? lines.joined(separator: "\n").write(to: directory.appending(path: "informe.txt"), atomically: true, encoding: .utf8)
            }
            // Hasta 5 minutos: la primera vez puede tener que descargar un modelo de voz.
            for _ in 0..<600 {
                if case .ready = modelStatus { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard case .ready(let locale) = modelStatus else { return }
            lines.append("idioma «\(Preferences.language)», traducir a «\(Preferences.translateTo.rawValue)» · Whisper \(groq.transcribes) (\(Preferences.groqWhisperModel.rawValue)), pulido Groq \(groq.polishes) (\(Preferences.groqChatModel.rawValue)), local \(localPolisher.isAvailable)")
            let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["wav", "m4a"].contains($0.pathExtension) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let clock = ContinuousClock()
            let hints = vocabulary.hints
            var totals: [Duration] = []
            // SUSURRO_BENCH_BEFORE: texto que se supone ya escrito antes del cursor.
            let context = DictationContext(textBefore: environment["SUSURRO_BENCH_BEFORE"], previousDictation: environment["SUSURRO_BENCH_PREVIOUS"])
            // Entre dictados se deja un respiro, como en el uso real: seguidos agotan el límite gratuito de Groq.
            let pause = environment["SUSURRO_BENCH_PAUSE"].flatMap(Double.init) ?? 5
            for file in files {
                try? await Task.sleep(for: .milliseconds(Int(pause * 1000)))
                // Un dictado largo se corta en las pausas, como en directo, y se mide lo que falta al soltar la tecla.
                let pieces = await Self.split(file)
                if pieces.count > 1 {
                    let processor = processor
                    let job = Task { processor.makeJob(locale: locale, target: target, context: context) }
                    let live = LiveTranscript(groq: groq, processor: processor, job: job, language: locale.language.languageCode?.identifier, hints: hints)
                    for piece in pieces.dropLast() {
                        live.add(piece)
                        await live.settle()
                    }
                    try? await Task.sleep(for: .milliseconds(600))
                    let began = clock.now
                    let text = await live.finish(lastURL: pieces.last, hasVoice: true) {}
                    let finished = clock.now
                    totals.append(finished - began)
                    lines.append("""
                        ■ \(file.deletingPathExtension().lastPathComponent) (por partes: \(pieces.count) trozos)
                          Final:   \((text ?? "— falló —").replacingOccurrences(of: "\n", with: "⏎"))
                          tiempos: al soltar la tecla \(Self.ms(finished - began)) ms
                        """)
                    write()
                    if environment["SUSURRO_BENCH_WHOLE"] == nil { continue }
                }
                // Apple ya ha transcrito mientras se hablaba: en directo solo cuenta lo que tarda Whisper.
                let localText = (try? await SpeechEngine.transcribeFile(file, locale: locale, hints: hints)) ?? ""
                groq.warmUp()
                try? await Task.sleep(for: .milliseconds(300))
                let began = clock.now
                let seconds = (try? AVAudioFile(forReading: file)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 5
                let whisperLanguage = Preferences.isAutomaticLanguage ? nil : locale.language.languageCode?.identifier
                let job = Task { await groq.transcribe(audioURL: file, language: whisperLanguage, hints: hints) }
                let whisperText = await Self.value(of: job, within: Self.whisperDeadline(forSeconds: seconds))
                if whisperText == nil { groq.noteSlowNetwork() }
                let transcribed = clock.now
                let raw = TranscriptChooser.choose(whisper: whisperText, local: localText)
                let alternative = raw != localText && !localText.isEmpty ? localText : nil
                var usedModel = false
                let languages = Preferences.isAutomaticLanguage ? ["es", "en"] : nil
                let text = await processor.process(raw, alternative: alternative, locale: locale, languages: languages, target: target, context: context) { usedModel = true }
                let finished = clock.now
                totals.append(finished - began)
                lines.append("""
                    ■ \(file.deletingPathExtension().lastPathComponent)
                      Apple:   \(localText)
                      Whisper: \(whisperText ?? "—")
                      Final:   \(text.replacingOccurrences(of: "\n", with: "⏎"))
                      tiempos: Whisper \(Self.ms(transcribed - began)) ms · procesar \(Self.ms(finished - transcribed)) ms\(usedModel ? " (con IA: \(groq.lastPolishModel?.title ?? "ninguna respondió"))" : " (sin IA)") · total \(Self.ms(finished - began)) ms
                    """)
                write()
            }
            let average = totals.isEmpty ? 0 : totals.map(Self.ms).reduce(0, +) / totals.count
            lines.append("media total: \(average) ms")
            lines.append("terminado")
            write()
        }
    }

    /// Corta un audio en trozos con el mismo criterio que la grabación en directo.
    private static func split(_ file: URL) async -> [URL] {
        guard let audio = try? AVAudioFile(forReading: file),
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)),
              (try? audio.read(into: buffer)) != nil, let samples = buffer.floatChannelData?[0]
        else { return [file] }
        let rate = audio.processingFormat.sampleRate
        let window = Int(rate * 0.035)
        var detector = PauseDetector()
        var cuts: [Double] = []
        var position = 0
        while position + window <= Int(buffer.frameLength) {
            var sum: Float = 0
            for index in position..<(position + window) { sum += samples[index] * samples[index] }
            let decibels = 10 * log10(max(sum / Float(window), 1e-12))
            position += window
            if detector.feed(level: min(max((decibels + 55) / 45, 0), 1), elapsed: 0.035) {
                cuts.append(Double(position) / rate)
            }
        }
        guard !cuts.isEmpty else { return [file] }
        let asset = AVURLAsset(url: file)
        let total = Double(audio.length) / rate
        var pieces: [URL] = []
        for (start, end) in zip([0] + cuts, cuts + [total]) {
            let url = FileManager.default.temporaryDirectory.appending(path: "stepbro-\(UUID().uuidString).m4a")
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return [file] }
            export.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 16_000),
                end: CMTime(seconds: end, preferredTimescale: 16_000)
            )
            guard (try? await export.export(to: url, as: .m4a)) != nil else { return [file] }
            pieces.append(url)
        }
        return pieces
    }

    private static func ms(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
