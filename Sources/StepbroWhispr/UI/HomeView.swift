import StepbroWhisprCore
import SwiftUI

struct HomeView: View {
    let state: AppState

    @AppStorage(Preferences.hotkeyKey) private var hotkey: Hotkey = .fn
    @AppStorage(Preferences.userNameKey) private var userName = ""
    @State private var search = ""
    @State private var sample = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                if !setupComplete {
                    setup
                }
                if state.history.items.isEmpty {
                    tryIt
                } else {
                    feed
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .animation(.spring(duration: 0.4), value: setupComplete)
    }

    private var setupComplete: Bool {
        state.isReady && (hotkey != .fn || state.globeKeyFree)
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.display(34))
                HStack(spacing: 6) {
                    Text("Mantén")
                    Keycap(label: hotkey.shortName)
                    Text("en cualquier app y habla. Doble toque para dictar sin manos.")
                }
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
            }
            if !state.history.items.isEmpty {
                stats
            }
        }
    }

    private var stats: some View {
        let stats = state.history.stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(symbol: "text.word.spacing", value: stats.totalWords.formatted(), label: "palabras dictadas")
            StatTile(symbol: "gauge.with.needle", value: stats.wordsPerMinute.map { "\($0)" } ?? "—", label: "palabras por minuto")
            StatTile(symbol: "timer", value: "\(stats.minutesSaved)", label: "minutos ahorrados")
            StatTile(
                symbol: "flame",
                value: "\(state.history.streakDays)",
                label: state.history.streakDays == 1 ? "día seguido" : "días seguidos"
            )
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let salute = switch hour {
        case 6..<14: "Buenos días"
        case 14..<21: "Buenas tardes"
        default: "Buenas noches"
        }
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? salute : "\(salute), \(name)"
    }

    // MARK: - Primeros pasos

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Primeros pasos")
            SoftCard {
                VStack(spacing: 0) {
                    SetupRow(
                        symbol: "mic.fill",
                        color: .red,
                        title: "Micrófono",
                        detail: "Para oír lo que dictas. El audio no sale de tu Mac.",
                        done: state.microphoneGranted
                    ) {
                        Button("Permitir", action: state.requestMicrophone)
                            .buttonStyle(.glassProminent)
                    }
                    CardDivider(inset: 58)
                    SetupRow(
                        symbol: "accessibility",
                        color: .blue,
                        title: "Accesibilidad",
                        detail: "Para detectar \(hotkey.shortName) y pegar el texto. En Ajustes, activa el interruptor de stepbro whispr.",
                        done: state.accessibilityGranted
                    ) {
                        Button("Abrir Ajustes", action: state.requestAccessibility)
                            .buttonStyle(.glassProminent)
                    }
                    if hotkey == .fn {
                        CardDivider(inset: 58)
                        SetupRow(
                            symbol: "globe",
                            color: .gray,
                            title: "Tecla Fn (globo)",
                            detail: "En Ajustes del Sistema > Teclado, cambia la acción de la tecla del globo a «No hacer nada».",
                            done: state.globeKeyFree
                        ) {
                            Button("Abrir Teclado") { Permissions.open(.keyboard) }
                                .buttonStyle(.glass)
                        }
                    }
                    if !isModelReady {
                        CardDivider(inset: 58)
                        modelRow
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var isModelReady: Bool {
        if case .ready = state.modelStatus { true } else { false }
    }

    @ViewBuilder
    private var modelRow: some View {
        switch state.modelStatus {
        case .checking, .ready:
            SetupRow(symbol: "waveform", color: Brand.violet, title: "Modelo de voz", detail: "Comprobando…", done: false) {
                ProgressView().controlSize(.small)
            }
        case .downloading(let fraction):
            SetupRow(symbol: "waveform", color: Brand.violet, title: "Modelo de voz", detail: "Descargando, solo la primera vez…", done: false) {
                ProgressView(value: fraction).frame(width: 100)
            }
        case .failed(let message):
            SetupRow(symbol: "waveform", color: Brand.violet, title: "Modelo de voz", detail: message, done: false) {
                Button("Reintentar", action: state.prepareModel)
                    .buttonStyle(.glass)
            }
        }
    }

    // MARK: - Prueba

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Pruébalo")
            SoftCard(padding: 18) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $sample)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                    if sample.isEmpty {
                        Text("Haz clic aquí, mantén \(hotkey.shortName) y habla…")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Historial

    private var feed: some View {
        // Se calcula una vez por dibujo: agrupar cientos de dictados no es gratis.
        let days = days
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("Historial")
                    .font(.display(22))
                Spacer()
                SearchField(text: $search)
            }

            if days.isEmpty {
                Text("Nada coincide con «\(search)».")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }

            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: title(for: group.day))
                    SoftCard {
                        LazyVStack(spacing: 0) {
                            ForEach(group.items) { dictation in
                                FeedRow(dictation: dictation, state: state)
                            }
                        }
                    }
                }
            }
        }
    }

    private var days: [(day: Date, items: [Dictation])] {
        let calendar = Calendar.current
        let matches = search.isEmpty
            ? state.history.items
            : state.history.items.filter { $0.text.localizedStandardContains(search) }
        let grouped = Dictionary(grouping: matches) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 150)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Una cifra grande con su símbolo y su etiqueta.
private struct StatTile: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        SoftCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 26, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct FeedRow: View {
    let dictation: Dictation
    let state: AppState
    @State private var copied = false

    var body: some View {
        HoverRow { hovering in
            HStack(alignment: .top, spacing: 12) {
                AppIcon(bundleID: dictation.bundleID, name: dictation.appName, size: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(dictation.text)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) {
                        Text(dictation.date, format: .dateTime.hour().minute())
                            .monospacedDigit()
                        if let app = dictation.appName {
                            Text("·")
                            Text(app)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                }
                Button {
                    state.history.copy(dictation)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 26, height: 26)
                        .background(.primary.opacity(0.07), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering || copied ? 1 : 0)
                .help("Copiar")
            }
        }
        .contextMenu {
            Button("Copiar", systemImage: "doc.on.doc") { state.history.copy(dictation) }
            Divider()
            Button("Eliminar", systemImage: "trash", role: .destructive) { state.history.delete(dictation) }
        }
    }
}
