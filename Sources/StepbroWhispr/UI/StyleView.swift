import StepbroWhisprCore
import SwiftUI

/// Tono del texto según la app donde escribes.
struct StyleView: View {
    let vocabulary: VocabularyStore

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Estilo",
                subtitle: "stepbro whispr adapta el tono según dónde escribes: casual en un chat, cuidado en un correo, exacto en el código."
            )
            // En dos columnas cuando hay sitio: cada tarjeta es estrecha y así no queda medio vacía.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(AppCategory.allCases) { category in
                    CategoryCard(category: category, vocabulary: vocabulary)
                }
            }
            Text("El estilo se aplica al pulir el texto, con Apple Intelligence o con Groq.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }
}

private struct CategoryCard: View {
    let category: AppCategory
    let vocabulary: VocabularyStore
    @Namespace private var selection

    var body: some View {
        let current = vocabulary.style(for: category)
        SoftCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: symbol, color: color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.system(size: 15, weight: .semibold))
                        Text(category.examples)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(WritingStyle.allCases) { style in
                            StyleChip(style: style, isSelected: style == current, namespace: selection) {
                                withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
                                    vocabulary.setStyle(style, for: category)
                                }
                            }
                        }
                    }
                }
                Text(current.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
    }

    private var symbol: String {
        switch category {
        case .messages: "message.fill"
        case .email: "envelope.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "square.grid.2x2.fill"
        }
    }

    private var color: Color {
        switch category {
        case .messages: .green
        case .email: .blue
        case .code: .indigo
        case .other: .gray
        }
    }
}

private struct StyleChip: View {
    let style: WritingStyle
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                label
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.25)).interactive(), in: .capsule)
                    .glassEffectID("style", in: namespace)
            } else {
                label
                    .background(.primary.opacity(0.05), in: .capsule)
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        Text(style.title)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .contentShape(.capsule)
    }
}
