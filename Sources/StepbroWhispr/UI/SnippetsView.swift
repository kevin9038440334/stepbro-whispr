import StepbroWhisprCore
import SwiftUI

/// Atajos de texto: dices algo corto y se escribe el texto completo.
struct SnippetsView: View {
    let vocabulary: VocabularyStore

    @State private var trigger = ""
    @State private var expansion = ""
    /// Atajo que se está editando (al hacer clic en una fila), o nil si se añade uno nuevo.
    @State private var editing: Snippet.ID?
    @FocusState private var focusedOnTrigger: Bool

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Atajos de texto",
                subtitle: "Di el atajo y se escribe el texto completo: tu correo, tu dirección, una firma o un enlace."
            )

            SoftCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    CapsuleField("Lo que dices, como «mi correo»", text: $trigger)
                        .focused($focusedOnTrigger)
                    TextField("Lo que se escribe", text: $expansion, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .font(.system(size: 13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 30)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    HStack {
                        Text(editing == nil
                            ? "Funciona aunque lo digas en mitad de una frase. Haz clic en un atajo para editarlo."
                            : "Editando. Cambia lo que dices o lo que se escribe y pulsa Guardar.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if editing != nil {
                            Button("Cancelar", action: reset)
                                .buttonStyle(.glass)
                        }
                        Button(editing == nil ? "Añadir atajo" : "Guardar", action: add)
                            .buttonStyle(.glassProminent)
                            .disabled(!canAdd)
                    }
                }
            }

            if vocabulary.snippets.isEmpty {
                EmptyHint(
                    symbol: "text.badge.plus",
                    text: "Aún no hay atajos. Prueba con «mi correo» y tu dirección de email."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "\(vocabulary.snippets.count) atajos")
                    SoftCard {
                        VStack(spacing: 0) {
                            ForEach(vocabulary.snippets) { snippet in
                                SnippetRow(snippet: snippet, isSelected: snippet.id == editing, onSelect: { edit(snippet) }) {
                                    remove(snippet)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var canAdd: Bool {
        !trigger.trimmingCharacters(in: .whitespaces).isEmpty
            && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        let snippet = Snippet(
            trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            expansion: expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        withAnimation(.spring(duration: 0.35)) {
            if let editing, let index = vocabulary.snippets.firstIndex(where: { $0.id == editing }) {
                vocabulary.snippets[index].trigger = snippet.trigger
                vocabulary.snippets[index].expansion = snippet.expansion
            } else {
                vocabulary.snippets.removeAll { $0.trigger.caseInsensitiveCompare(snippet.trigger) == .orderedSame }
                vocabulary.snippets.insert(snippet, at: 0)
            }
        }
        reset()
        focusedOnTrigger = true
    }

    private func edit(_ snippet: Snippet) {
        withAnimation(.spring(duration: 0.3)) {
            editing = snippet.id
            trigger = snippet.trigger
            expansion = snippet.expansion
        }
        focusedOnTrigger = true
    }

    private func reset() {
        withAnimation(.spring(duration: 0.3)) {
            editing = nil
            trigger = ""
            expansion = ""
        }
    }

    private func remove(_ snippet: Snippet) {
        if snippet.id == editing { reset() }
        withAnimation(.spring(duration: 0.35)) {
            vocabulary.snippets.removeAll { $0.id == snippet.id }
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HoverRow(isSelected: isSelected, action: onSelect) { hovering in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(snippet.trigger)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(.primary.opacity(0.08), in: .capsule)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(snippet.expansion)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DeleteButton(action: onDelete)
                    .opacity(hovering || isSelected ? 1 : 0)
            }
        }
    }
}
