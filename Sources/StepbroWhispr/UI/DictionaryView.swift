import StepbroWhisprCore
import SwiftUI

/// Palabras que deben escribirse siempre bien.
struct DictionaryView: View {
    let vocabulary: VocabularyStore

    @State private var term = ""
    @State private var heardAs = ""
    /// Palabra que se está editando (al hacer clic en una fila), o nil si se añade una nueva.
    @State private var editing: VocabularyEntry.ID?
    @FocusState private var focusedOnTerm: Bool

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Diccionario",
                subtitle: "Nombres, marcas y términos que deben escribirse siempre bien. Si el reconocimiento los entiende mal, di cómo los oye."
            )

            SoftCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        CapsuleField("Palabra, como «stepbro» o «iPhone»", text: $term)
                            .focused($focusedOnTerm)
                        CapsuleField("Se oye como (opcional)", text: $heardAs)
                        if editing != nil {
                            Button("Cancelar", action: reset)
                                .buttonStyle(.glass)
                        }
                        Button(editing == nil ? "Añadir" : "Guardar", action: save)
                            .buttonStyle(.glassProminent)
                            .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                            .keyboardShortcut(.defaultAction)
                    }
                    Text(editing == nil
                        ? "Separa con comas varias formas: «estep bro, step bro». Haz clic en una palabra para editarla."
                        : "Editando. Cambia la palabra o cómo se oye y pulsa Guardar.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .contentTransition(.opacity)
                }
            }

            if vocabulary.entries.isEmpty {
                EmptyHint(
                    symbol: "character.book.closed",
                    text: "Aún no hay palabras. Empieza por tu nombre, el de tu empresa o los términos que más usas."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "\(vocabulary.entries.count) palabras")
                    SoftCard {
                        VStack(spacing: 0) {
                            ForEach(vocabulary.entries) { entry in
                                EntryRow(entry: entry, isSelected: entry.id == editing, onSelect: { edit(entry) }) {
                                    remove(entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func edit(_ entry: VocabularyEntry) {
        withAnimation(.spring(duration: 0.3)) {
            editing = entry.id
            term = entry.term
            heardAs = entry.heardAs.joined(separator: ", ")
        }
        focusedOnTerm = true
    }

    private func reset() {
        withAnimation(.spring(duration: 0.3)) {
            editing = nil
            term = ""
            heardAs = ""
        }
    }

    private func save() {
        let cleanTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTerm.isEmpty else { return }
        let variants = heardAs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        withAnimation(.spring(duration: 0.35)) {
            if let editing, let index = vocabulary.entries.firstIndex(where: { $0.id == editing }) {
                // Al editar, lo escrito sustituye a lo que había.
                vocabulary.entries[index].term = cleanTerm
                vocabulary.entries[index].heardAs = variants
            } else if let index = vocabulary.entries.firstIndex(where: { $0.term.caseInsensitiveCompare(cleanTerm) == .orderedSame }) {
                vocabulary.entries[index].heardAs = Array(Set(vocabulary.entries[index].heardAs + variants)).sorted()
            } else {
                vocabulary.entries.insert(VocabularyEntry(term: cleanTerm, heardAs: variants), at: 0)
            }
        }
        reset()
        focusedOnTerm = true
    }

    private func remove(_ entry: VocabularyEntry) {
        if entry.id == editing { reset() }
        withAnimation(.spring(duration: 0.35)) {
            vocabulary.entries.removeAll { $0.id == entry.id }
        }
    }
}

private struct EntryRow: View {
    let entry: VocabularyEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HoverRow(isSelected: isSelected, action: onSelect) { hovering in
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.term)
                        .font(.system(size: 14, weight: .semibold))
                    if !entry.heardAs.isEmpty || !entry.confusedWith.isEmpty {
                        // Las formas mal oídas, como etiquetas; las palabras con las que no confundirlo, más tenues.
                        FlowLayout(spacing: 5) {
                            ForEach(entry.heardAs, id: \.self) { TagChip(text: $0) }
                            ForEach(entry.confusedWith, id: \.self) { TagChip(text: "no es «\($0)»", dimmed: true) }
                        }
                    }
                }
                Spacer(minLength: 8)
                DeleteButton(action: onDelete)
                    .opacity(hovering || isSelected ? 1 : 0)
            }
        }
    }
}

/// Coloca las vistas en fila y salta de línea cuando no caben, como el texto.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
