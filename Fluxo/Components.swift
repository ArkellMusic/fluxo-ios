import SwiftUI

/// Tarjeta de cristal líquido.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = 24
    var tint: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.25)) } ?? .regular, in: .rect(cornerRadius: radius))
    }
}

/// Fila de un cobro: burbuja, nombre, frecuencia, importe y estado.
struct PaymentRow: View {
    var name: String
    var subtitle: String
    var amount: Double
    var status: String?
    var statusColor: Color = .secondary
    var bubbleColor: Color? = nil

    var body: some View {
        HStack(spacing: 14) {
            MerchantBubble(name: name, size: 46, color: bubbleColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(amount)).font(.headline.monospacedDigit())
                if let status {
                    Text(status).font(.subheadline.weight(.medium)).foregroundStyle(statusColor)
                }
            }
        }
    }
}

struct TransactionRow: View {
    var t: Transaction

    var body: some View {
        HStack(spacing: 14) {
            MerchantBubble(name: t.merchant, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.merchant).font(.headline).lineLimit(1)
                Label(t.category.name, systemImage: t.category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(TightLabel(color: t.category.color))
            }
            Spacer(minLength: 8)
            Text((t.isExpense ? "" : "+") + Fmt.money(abs(t.amount)))
                .font(.headline.monospacedDigit())
                .foregroundStyle(t.isExpense ? Color.primary : Theme.positive)
        }
    }
}

struct TightLabel: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(color).imageScale(.small)
            configuration.title
        }
    }
}

/// Fondo verde oscuro común a todas las pantallas.
struct Screen<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) { content }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
        }
    }
}

struct EmptyStateCard: View {
    var icon: String
    var title: String
    var text: String

    var body: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.accent)
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

/// Cambio porcentual con flecha (rojo si sube el gasto, verde si baja).
struct ChangeBadge: View {
    var current: Double
    var previous: Double

    var body: some View {
        if previous > 0 {
            let pct = (current - previous) / previous * 100
            let up = pct >= 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text("\(Int(abs(pct).rounded()))%")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(up ? Theme.negative : Theme.positive)
        }
    }
}
