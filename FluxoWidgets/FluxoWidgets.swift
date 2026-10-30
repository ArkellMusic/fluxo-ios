import WidgetKit
import SwiftUI

// MARK: - Datos del widget

struct FluxoEntry: TimelineEntry {
    var date: Date
    var upcoming: [Occurrence]
    var monthSpent: Double
    var monthFixed: Double
    var isEmpty: Bool

    static var placeholder: FluxoEntry {
        let subs = [
            Subscription(name: "Netflix", amount: 13.99, day: 5),
            Subscription(name: "Spotify", amount: 20.99, day: 10),
            Subscription(name: "Movistar", amount: 35, day: 8, category: .telefonia),
        ]
        let c = Schedule.cal
        let occ = subs.enumerated().map { i, s in
            Occurrence(subscription: s, date: c.date(byAdding: .day, value: i * 2 + 1, to: .now)!)
        }
        return FluxoEntry(date: .now, upcoming: occ, monthSpent: 1245.30, monthFixed: 69.98, isEmpty: false)
    }
}

struct FluxoProvider: TimelineProvider {
    func placeholder(in context: Context) -> FluxoEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (FluxoEntry) -> Void) {
        let e = makeEntry(date: .now)
        completion(context.isPreview && e.isEmpty ? .placeholder : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FluxoEntry>) -> Void) {
        let c = Schedule.cal
        let now = Date()
        // Una entrada ahora y otra cada medianoche de los próximos 3 días
        var entries = [makeEntry(date: now)]
        for i in 1...3 {
            if let d = c.date(byAdding: .day, value: i, to: c.startOfDay(for: now)) { entries.append(makeEntry(date: d)) }
        }
        completion(Timeline(entries: entries, policy: .after(entries.last!.date)))
    }

    private func makeEntry(date: Date) -> FluxoEntry {
        let data = SharedStore.load()
        let c = Schedule.cal
        let comps = c.dateComponents([.year, .month], from: date)
        let upcoming = Schedule.upcoming(data.subscriptions, from: date, months: 1)
        let fixed = Schedule.occurrences(data.subscriptions, year: comps.year!, month: comps.month!)
            .reduce(0) { $0 + $1.subscription.amount }
        return FluxoEntry(date: date,
                          upcoming: Array(upcoming.prefix(4)),
                          monthSpent: Schedule.monthSpending(data.transactions, year: comps.year!, month: comps.month!),
                          monthFixed: fixed,
                          isEmpty: data.subscriptions.isEmpty && data.transactions.isEmpty)
    }
}

// MARK: - Vistas

struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SmallView: View {
    var entry: FluxoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "water.waves").foregroundStyle(Theme.accent)
                Text("Próximo").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let next = entry.upcoming.first {
                MerchantBubble(name: next.subscription.name, size: 34, color: next.subscription.color)
                Text(next.subscription.name).font(.headline).lineLimit(1)
                HStack {
                    Text(Fmt.money(next.subscription.amount)).font(.subheadline.monospacedDigit())
                    Spacer()
                    Text(Schedule.relative(next.date, from: entry.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Schedule.daysUntil(next.date, from: entry.date) == 0 ? Theme.negative : Theme.accent)
                }
            } else {
                Text("Sin cobros").font(.headline)
                Text("Abre Fluxo para añadirlos").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct MediumView: View {
    var entry: FluxoEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Este mes", systemImage: "water.waves")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(Fmt.moneyShort(entry.monthSpent))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("gastado").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Fijos: \(Fmt.moneyShort(entry.monthFixed))").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                if entry.upcoming.isEmpty {
                    Spacer()
                    Text("Sin cobros próximos").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                ForEach(entry.upcoming.prefix(3)) { o in
                    HStack(spacing: 8) {
                        MerchantBubble(name: o.subscription.name, size: 24, color: o.subscription.color)
                        Text(o.subscription.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Fmt.money(o.subscription.amount)).font(.caption.monospacedDigit())
                            Text(Schedule.relative(o.date, from: entry.date))
                                .font(.caption2)
                                .foregroundStyle(Schedule.daysUntil(o.date, from: entry.date) == 0 ? Theme.negative : .secondary)
                        }
                    }
                }
            }
        }
    }
}

struct LockRectangularView: View {
    var entry: FluxoEntry

    var body: some View {
        if let next = entry.upcoming.first {
            VStack(alignment: .leading, spacing: 1) {
                Label("Próximo cobro", systemImage: "water.waves").font(.caption2).widgetAccentable()
                Text(next.subscription.name).font(.headline).lineLimit(1)
                Text("\(Fmt.money(next.subscription.amount)) · \(Schedule.relative(next.date, from: entry.date))")
                    .font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading) {
                Label("Fluxo", systemImage: "water.waves").font(.caption2).widgetAccentable()
                Text("Gastado: \(Fmt.moneyShort(entry.monthSpent))").font(.headline)
            }
        }
    }
}

struct LockCircularView: View {
    var entry: FluxoEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let next = entry.upcoming.first {
                let n = Schedule.daysUntil(next.date, from: entry.date)
                VStack(spacing: -2) {
                    Text(MerchantStyle.initials(for: next.subscription.name)).font(.caption2.weight(.bold)).widgetAccentable()
                    Text(n == 0 ? "Hoy" : "\(n)d").font(.system(size: 16, weight: .bold, design: .rounded))
                }
            } else {
                Image(systemName: "water.waves")
            }
        }
    }
}

struct LockInlineView: View {
    var entry: FluxoEntry

    var body: some View {
        if let next = entry.upcoming.first {
            Text("\(Image(systemName: "water.waves")) \(next.subscription.name) \(Fmt.money(next.subscription.amount)) · \(Schedule.relative(next.date, from: entry.date))")
        } else {
            Text("\(Image(systemName: "water.waves")) Gastado: \(Fmt.moneyShort(entry.monthSpent))")
        }
    }
}

struct FluxoWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: FluxoEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry).containerBackground(for: .widget) { WidgetBackground() }
        case .accessoryRectangular: LockRectangularView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular: LockCircularView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryInline: LockInlineView(entry: entry).containerBackground(for: .widget) { Color.clear }
        default: SmallView(entry: entry).containerBackground(for: .widget) { WidgetBackground() }
        }
    }
}

// MARK: - Widgets

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FluxoUpcoming", provider: FluxoProvider()) { entry in
            FluxoWidgetView(entry: entry)
        }
        .configurationDisplayName("Próximos cobros")
        .description("Tus próximos pagos fijos y lo que llevas gastado este mes.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct FluxoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
    }
}
