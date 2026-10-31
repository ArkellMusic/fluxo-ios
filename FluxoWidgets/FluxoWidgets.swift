import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Opciones editables ("Editar widget")

enum WidgetMode: String, AppEnum {
    case proximos, gasto, calendario, resumen

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Contenido"
    static var caseDisplayRepresentations: [WidgetMode: DisplayRepresentation] = [
        .proximos: "Próximos cobros",
        .gasto: "Gasto del mes",
        .calendario: "Calendario",
        .resumen: "Resumen",
    ]
}

enum WidgetStyle: String, AppEnum {
    case verde, oscuro, transparente

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Estilo"
    static var caseDisplayRepresentations: [WidgetStyle: DisplayRepresentation] = [
        .verde: "Verde Fluxo",
        .oscuro: "Negro",
        .transparente: "Transparente",
    ]
}

struct FluxoWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget de Fluxo"
    static var description = IntentDescription("Elige qué muestra el widget y cómo se ve.")

    @Parameter(title: "Contenido", default: .proximos)
    var mode: WidgetMode

    @Parameter(title: "Estilo", default: .verde)
    var style: WidgetStyle

    @Parameter(title: "Mostrar importes", default: true)
    var showAmounts: Bool

    init() {}

    init(mode: WidgetMode) {
        self.mode = mode
        self.style = .verde
        self.showAmounts = true
    }
}

// MARK: - Datos

struct CategorySpend: Hashable {
    var category: Category
    var amount: Double
}

struct FluxoEntry: TimelineEntry {
    var date: Date
    var config: FluxoWidgetIntent
    var upcoming: [Occurrence]
    var monthOccurrences: [Occurrence]
    var monthSpent: Double
    var prevSpent: Double
    var monthFixed: Double
    var topCategories: [CategorySpend]
    var isEmpty: Bool

    static func placeholder(_ config: FluxoWidgetIntent = FluxoWidgetIntent()) -> FluxoEntry {
        let subs = [
            Subscription(name: "Netflix", amount: 13.99, day: 5),
            Subscription(name: "Movistar", amount: 35, day: 8, category: .telefonia),
            Subscription(name: "Spotify", amount: 20.99, day: 10),
            Subscription(name: "Gimnasio", amount: 39.90, day: 12, category: .deporte),
            Subscription(name: "Alquiler", amount: 750, day: 15, category: .hogar),
        ]
        let c = Schedule.cal
        let occ = subs.enumerated().map { i, s in
            Occurrence(subscription: s, date: c.date(byAdding: .day, value: i * 2 + 1, to: .now)!)
        }
        let comps = c.dateComponents([.year, .month], from: .now)
        return FluxoEntry(date: .now, config: config, upcoming: occ,
                          monthOccurrences: Schedule.occurrences(subs, year: comps.year!, month: comps.month!),
                          monthSpent: 1245.30, prevSpent: 1180, monthFixed: 859.88,
                          topCategories: [CategorySpend(category: .hogar, amount: 780), CategorySpend(category: .supermercado, amount: 260),
                                          CategorySpend(category: .restaurantes, amount: 120), CategorySpend(category: .combustible, amount: 85)],
                          isEmpty: false)
    }
}

struct FluxoProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FluxoEntry { .placeholder() }

    func snapshot(for configuration: FluxoWidgetIntent, in context: Context) async -> FluxoEntry {
        let e = makeEntry(date: .now, config: configuration)
        return context.isPreview && e.isEmpty ? .placeholder(configuration) : e
    }

    func timeline(for configuration: FluxoWidgetIntent, in context: Context) async -> Timeline<FluxoEntry> {
        let c = Schedule.cal
        let now = Date()
        var entries = [makeEntry(date: now, config: configuration)]
        for i in 1...3 {
            if let d = c.date(byAdding: .day, value: i, to: c.startOfDay(for: now)) {
                entries.append(makeEntry(date: d, config: configuration))
            }
        }
        return Timeline(entries: entries, policy: .after(entries.last!.date))
    }

    private func makeEntry(date: Date, config: FluxoWidgetIntent) -> FluxoEntry {
        let data = SharedStore.load()
        let c = Schedule.cal
        let comps = c.dateComponents([.year, .month], from: date)
        let prev = c.dateComponents([.year, .month], from: c.date(byAdding: .month, value: -1, to: date)!)
        let monthOcc = Schedule.occurrences(data.subscriptions, year: comps.year!, month: comps.month!)

        var byCat: [Category: Double] = [:]
        for t in data.transactions where t.isExpense && t.category != .transferencias
            && c.isDate(t.date, equalTo: date, toGranularity: .month) {
            byCat[t.category, default: 0] -= t.amount
        }
        let top = byCat.map { CategorySpend(category: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }

        return FluxoEntry(date: date, config: config,
                          upcoming: Array(Schedule.upcoming(data.subscriptions, from: date, months: 1).prefix(8)),
                          monthOccurrences: monthOcc,
                          monthSpent: Schedule.monthSpending(data.transactions, year: comps.year!, month: comps.month!),
                          prevSpent: Schedule.monthSpending(data.transactions, year: prev.year!, month: prev.month!),
                          monthFixed: monthOcc.reduce(0) { $0 + $1.subscription.amount },
                          topCategories: Array(top.prefix(6)),
                          isEmpty: data.subscriptions.isEmpty && data.transactions.isEmpty)
    }
}

// MARK: - Piezas comunes

extension FluxoEntry {
    func money(_ v: Double, short: Bool = false) -> String {
        config.showAmounts ? (short ? Fmt.moneyShort(v) : Fmt.money(v)) : "•••"
    }
    func when(_ d: Date) -> String { Schedule.relative(d, from: date) }
    func isToday(_ d: Date) -> Bool { Schedule.daysUntil(d, from: date) == 0 }
    var monthName: String { Fmt.monthYear(date).components(separatedBy: " ").first ?? "" }
}

struct WidgetHeader: View {
    var title: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "water.waves").foregroundStyle(Theme.accent).widgetAccentable()
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct ChangeText: View {
    var entry: FluxoEntry
    var body: some View {
        if entry.prevSpent > 0 {
            let pct = (entry.monthSpent - entry.prevSpent) / entry.prevSpent * 100
            Label("\(Int(abs(pct).rounded()))%", systemImage: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(pct >= 0 ? Theme.negative : Theme.positive)
                .labelStyle(.titleAndIcon)
        }
    }
}

struct UpcomingRow: View {
    var entry: FluxoEntry
    var o: Occurrence
    var bubble: CGFloat = 26

    var body: some View {
        HStack(spacing: 8) {
            MerchantBubble(name: o.subscription.name, size: bubble, color: o.subscription.color, domain: o.subscription.domain)
            Text(o.subscription.name).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(entry.money(o.subscription.amount)).font(.caption.monospacedDigit())
                Text(entry.when(o.date)).font(.caption2)
                    .foregroundStyle(entry.isToday(o.date) ? Theme.negative : .secondary)
            }
        }
    }
}

struct EmptyHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sin cobros próximos").font(.subheadline.weight(.semibold))
            Text("Añádelos en Fluxo › Ajustes").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Próximos cobros

struct UpcomingView: View {
    @Environment(\.widgetFamily) var family
    var entry: FluxoEntry

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Próximo cobro")
                Spacer(minLength: 0)
                if let next = entry.upcoming.first {
                    MerchantBubble(name: next.subscription.name, size: 36, color: next.subscription.color, domain: next.subscription.domain)
                    Text(next.subscription.name).font(.headline).lineLimit(1)
                    HStack {
                        Text(entry.money(next.subscription.amount)).font(.subheadline.monospacedDigit())
                        Spacer()
                        Text(entry.when(next.date)).font(.caption.weight(.semibold))
                            .foregroundStyle(entry.isToday(next.date) ? Theme.negative : Theme.accent)
                    }
                } else { EmptyHint() }
            }
        case .systemLarge, .systemExtraLarge:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    WidgetHeader(title: "Próximos cobros")
                    Text("\(entry.money(entry.monthFixed, short: true)) / mes").font(.caption).foregroundStyle(.secondary)
                }
                if entry.upcoming.isEmpty { Spacer(); EmptyHint(); Spacer() }
                ForEach(entry.upcoming.prefix(6)) { o in UpcomingRow(entry: entry, o: o, bubble: 32) }
                Spacer(minLength: 0)
            }
        default:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetHeader(title: "Este mes")
                    Text(entry.money(entry.monthSpent, short: true))
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6).lineLimit(1)
                    ChangeText(entry: entry)
                    Spacer(minLength: 0)
                    Text("Fijos: \(entry.money(entry.monthFixed, short: true))").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 100, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    if entry.upcoming.isEmpty { Spacer(); EmptyHint(); Spacer() }
                    ForEach(entry.upcoming.prefix(3)) { o in UpcomingRow(entry: entry, o: o) }
                }
            }
        }
    }
}

// MARK: - Gasto del mes

struct SpendingView: View {
    @Environment(\.widgetFamily) var envFamily
    var entry: FluxoEntry
    var size: WidgetFamily? = nil
    private var family: WidgetFamily { size ?? envFamily }

    private var rows: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        default: 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            WidgetHeader(title: "Gasto de \(entry.monthName)")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.money(entry.monthSpent, short: true))
                    .font(.system(size: family == .systemSmall ? 24 : 28, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                ChangeText(entry: entry)
            }
            if entry.topCategories.isEmpty {
                Text("Sin gastos este mes").font(.caption).foregroundStyle(.secondary)
            }
            let maxV = entry.topCategories.first?.amount ?? 1
            ForEach(entry.topCategories.prefix(rows), id: \.self) { c in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: c.category.symbol).foregroundStyle(c.category.color).font(.caption2)
                        Text(c.category.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(entry.money(c.amount, short: true)).font(.caption.monospacedDigit())
                    }
                    GeometryReader { g in
                        Capsule().fill(c.category.color.opacity(0.85))
                            .frame(width: max(6, g.size.width * c.amount / maxV), height: 4)
                    }
                    .frame(height: 4)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Calendario

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: FluxoEntry
    private var cal: Calendar { Schedule.cal }

    var body: some View {
        switch family {
        case .systemSmall: today
        case .systemMedium: week
        default: month
        }
    }

    private func occ(on day: Date) -> [Occurrence] {
        entry.monthOccurrences.filter { cal.isDate($0.date, inSameDayAs: day) }
            + entry.upcoming.filter { cal.isDate($0.date, inSameDayAs: day) && !cal.isDate($0.date, equalTo: entry.date, toGranularity: .month) }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "es_ES"))).capitalized)
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.negative)
            Text("\(cal.component(.day, from: entry.date))")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
            if let next = entry.upcoming.first {
                HStack(spacing: 6) {
                    MerchantBubble(name: next.subscription.name, size: 22, color: next.subscription.color, domain: next.subscription.domain)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next.subscription.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text("\(entry.money(next.subscription.amount)) · \(entry.when(next.date))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                Text("Sin cobros").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var week: some View {
        let start = cal.startOfDay(for: entry.date)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Próximos 7 días")
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { d in
                    let list = occ(on: d)
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "es_ES"))).uppercased())
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(cal.component(.day, from: d))")
                            .font(.subheadline.weight(cal.isDate(d, inSameDayAs: entry.date) ? .bold : .medium))
                            .foregroundStyle(cal.isDate(d, inSameDayAs: entry.date) ? Theme.accent : .primary)
                        ZStack {
                            if let f = list.first {
                                MerchantBubble(name: f.subscription.name, size: 24, color: f.subscription.color, domain: f.subscription.domain)
                            } else {
                                Circle().fill(.white.opacity(0.06)).frame(width: 24, height: 24)
                            }
                        }
                        Text(list.isEmpty ? " " : entry.money(list.reduce(0) { $0 + $1.subscription.amount }, short: true))
                            .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var month: some View {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: entry.date))!
        let weekday = (cal.component(.weekday, from: first) + 5) % 7
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let cells = Int(ceil(Double(weekday + count) / 7.0)) * 7
        let cols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Fmt.monthYear(entry.date)).font(.headline)
                Spacer()
                Text("Fijos \(entry.money(entry.monthFixed, short: true))").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: cols, spacing: 3) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(0..<cells, id: \.self) { i in
                    let dayNum = i - weekday + 1
                    if dayNum >= 1 && dayNum <= count, let d = cal.date(byAdding: .day, value: dayNum - 1, to: first) {
                        let list = occ(on: d)
                        let isToday = cal.isDate(d, inSameDayAs: entry.date)
                        VStack(spacing: 1) {
                            Text("\(dayNum)").font(.system(size: 10, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? Theme.accent : .primary)
                            if let f = list.first {
                                MerchantBubble(name: f.subscription.name, size: 18, color: f.subscription.color, domain: f.subscription.domain)
                            } else {
                                Color.clear.frame(width: 18, height: 18)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(isToday ? 0.14 : 0.04)))
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Resumen

struct SummaryView: View {
    @Environment(\.widgetFamily) var family
    var entry: FluxoEntry

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: entry.monthName)
                Text(entry.money(entry.monthSpent, short: true))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                ChangeText(entry: entry)
                Spacer(minLength: 0)
                if let next = entry.upcoming.first {
                    HStack(spacing: 6) {
                        MerchantBubble(name: next.subscription.name, size: 20, color: next.subscription.color, domain: next.subscription.domain)
                        Text(entry.when(next.date)).font(.caption2.weight(.semibold))
                    }
                }
            }
        case .systemMedium:
            HStack(spacing: 14) {
                SpendingView(entry: entry, size: .systemSmall)
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 7) {
                    WidgetHeader(title: "Próximos")
                    ForEach(entry.upcoming.prefix(2)) { o in UpcomingRow(entry: entry, o: o, bubble: 22) }
                    Spacer(minLength: 0)
                }
            }
        default:
            VStack(spacing: 12) {
                SpendingView(entry: entry, size: .systemMedium)
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 7) {
                    WidgetHeader(title: "Próximos cobros")
                    ForEach(entry.upcoming.prefix(3)) { o in UpcomingRow(entry: entry, o: o) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Pantalla de bloqueo

struct LockRectangularView: View {
    var entry: FluxoEntry
    var body: some View {
        if entry.config.mode == .gasto || entry.upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Label("Gasto de \(entry.monthName)", systemImage: "water.waves").font(.caption2).widgetAccentable()
                Text(entry.money(entry.monthSpent, short: true)).font(.headline)
                Text("Fijos: \(entry.money(entry.monthFixed, short: true))").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let next = entry.upcoming.first {
            VStack(alignment: .leading, spacing: 1) {
                Label("Próximo cobro", systemImage: "water.waves").font(.caption2).widgetAccentable()
                Text(next.subscription.name).font(.headline).lineLimit(1)
                Text("\(entry.money(next.subscription.amount)) · \(entry.when(next.date))").font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LockCircularView: View {
    var entry: FluxoEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.config.mode == .gasto {
                VStack(spacing: -1) {
                    Image(systemName: "eurosign").font(.caption2).widgetAccentable()
                    Text(entry.config.showAmounts ? compact(entry.monthSpent) : "•••")
                        .font(.system(size: 14, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
                }
            } else if let next = entry.upcoming.first {
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
    private func compact(_ v: Double) -> String { v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))" }
}

struct LockInlineView: View {
    var entry: FluxoEntry
    var body: some View {
        if entry.config.mode != .gasto, let next = entry.upcoming.first {
            Text("\(Image(systemName: "water.waves")) \(next.subscription.name) \(entry.money(next.subscription.amount)) · \(entry.when(next.date))")
        } else {
            Text("\(Image(systemName: "water.waves")) Gastado: \(entry.money(entry.monthSpent, short: true))")
        }
    }
}

// MARK: - Montaje

struct WidgetBackground: View {
    var style: WidgetStyle
    var body: some View {
        switch style {
        case .verde: LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .oscuro: Color.black
        case .transparente: Color.clear
        }
    }
}

struct FluxoWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: FluxoEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: LockRectangularView(entry: entry)
            case .accessoryCircular: LockCircularView(entry: entry)
            case .accessoryInline: LockInlineView(entry: entry)
            default:
                switch entry.config.mode {
                case .proximos: UpcomingView(entry: entry)
                case .gasto: SpendingView(entry: entry)
                case .calendario: CalendarWidgetView(entry: entry)
                case .resumen: SummaryView(entry: entry)
                }
            }
        }
        .containerBackground(for: .widget) {
            if family.isAccessory { Color.clear } else { WidgetBackground(style: entry.config.style) }
        }
        .widgetURL(URL(string: "fluxo://open"))
    }
}

extension WidgetFamily {
    var isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline }
}

struct FluxoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FluxoMain", intent: FluxoWidgetIntent.self, provider: FluxoProvider()) { entry in
            FluxoWidgetView(entry: entry)
        }
        .configurationDisplayName("Fluxo")
        .description("Próximos cobros, gasto del mes o calendario. Mantén pulsado › Editar widget para cambiarlo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct FluxoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FluxoWidget()
    }
}
