import Foundation
import SwiftUI

// MARK: - Almacenamiento compartido (app + widgets)

enum SharedStore {
    static let defaultGroup = "group.com.arkellmusic.fluxo"

    /// SideStore puede renombrar el App Group al instalar; lo lee de ALTAppGroups.
    static var groupCandidates: [String] {
        var list: [String] = []
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            list.append(contentsOf: groups)
        }
        list.append(defaultGroup)
        return list
    }

    static var containerURL: URL {
        for g in groupCandidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) {
                return url
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var fileURL: URL { containerURL.appendingPathComponent("fluxo-data.json") }

    static func load() -> AppData {
        guard let data = try? Data(contentsOf: fileURL) else { return AppData() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode(AppData.self, from: data)) ?? AppData()
    }

    static func save(_ appData: AppData) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(appData) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Calendario de cobros

enum Schedule {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_ES")
        c.firstWeekday = 2
        return c
    }

    static func occurrences(_ subs: [Subscription], year: Int, month: Int) -> [Occurrence] {
        let c = cal
        guard let first = c.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = c.range(of: .day, in: .month, for: first) else { return [] }
        return subs.compactMap { s in
            guard s.occurs(inMonth: month) else { return nil }
            let day = min(max(1, s.day), range.count)
            guard let d = c.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return Occurrence(subscription: s, date: d)
        }
        .sorted { $0.date < $1.date }
    }

    /// Próximos cobros desde hoy (incluido) dentro de los siguientes `months` meses.
    static func upcoming(_ subs: [Subscription], from now: Date = .now, months: Int = 2) -> [Occurrence] {
        let c = cal
        let today = c.startOfDay(for: now)
        var out: [Occurrence] = []
        for i in 0...months {
            guard let d = c.date(byAdding: .month, value: i, to: today) else { continue }
            let comps = c.dateComponents([.year, .month], from: d)
            out += occurrences(subs, year: comps.year!, month: comps.month!)
        }
        return out.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }

    static func daysUntil(_ date: Date, from now: Date = .now) -> Int {
        let c = cal
        return c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: date)).day ?? 0
    }

    static func relative(_ date: Date, from now: Date = .now) -> String {
        let n = daysUntil(date, from: now)
        switch n {
        case ..<0: return "Pagado"
        case 0: return "Hoy"
        case 1: return "Mañana"
        default: return "en \(n) días"
        }
    }

    static func monthSpending(_ txs: [Transaction], year: Int, month: Int) -> Double {
        let c = cal
        return txs.filter {
            let comps = c.dateComponents([.year, .month], from: $0.date)
            return comps.year == year && comps.month == month && $0.isExpense && $0.category != .transferencias
        }
        .reduce(0) { $0 - $1.amount }
    }
}

// MARK: - Formato

enum Fmt {
    static let euro: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "es_ES")
        return f
    }()

    static let euroShort: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "es_ES")
        f.maximumFractionDigits = 0
        return f
    }()

    static func money(_ v: Double) -> String { euro.string(from: NSNumber(value: v)) ?? "\(v) €" }
    static func moneyShort(_ v: Double) -> String { euroShort.string(from: NSNumber(value: v)) ?? "\(Int(v)) €" }

    static func monthYear(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized
    }

    static func dayHeader(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: d).capitalized
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}

// MARK: - Color

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

enum Theme {
    static let accent = Color(hex: "46D9A6")
    static let bgTop = Color(hex: "0E3A30")
    static let bgBottom = Color(hex: "050B09")
    static let card = Color.white.opacity(0.06)
    static let negative = Color(hex: "FF5A4E")
    static let positive = Color(hex: "46D9A6")

    static var background: some View {
        LinearGradient(colors: [bgTop, Color(hex: "0A1A16"), bgBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Estilo de comercios (iniciales + color, sin logos)

enum MerchantStyle {
    private static let known: [(String, String)] = [
        ("netflix", "E50914"), ("spotify", "1DB954"), ("movistar", "019DF4"), ("digi", "1E3FE0"),
        ("disney", "113CCF"), ("amazon", "FF9900"), ("prime", "00A8E1"), ("hbo", "8A2BE2"), ("max", "2F2FE4"),
        ("youtube", "FF0000"), ("apple", "A2AAAD"), ("icloud", "3693F3"), ("google", "4285F4"),
        ("vodafone", "E60000"), ("orange", "FF7900"), ("yoigo", "A4C93C"), ("o2", "0050FF"),
        ("mercadona", "009245"), ("carrefour", "1E5BC6"), ("lidl", "0050AA"), ("dia", "E2001A"), ("alcampo", "E30613"),
        ("shell", "F2C200"), ("repsol", "FF8200"), ("cepsa", "E2231A"), ("bp", "009A44"), ("galp", "F26522"),
        ("iberdrola", "4CAF2E"), ("endesa", "0B5ED7"), ("naturgy", "F58220"), ("gimnasio", "222222"), ("gym", "222222"),
        ("bizum", "05C3DE"), ("chatgpt", "10A37F"), ("openai", "10A37F"), ("claude", "D97757"), ("uber", "111111"),
        ("glovo", "FFC244"), ("just eat", "FF8000"), ("zara", "111111"), ("ikea", "0058A3"), ("ing", "FF6200"),
        ("alquiler", "2EE6F5"), ("luz", "4CAF2E"), ("agua", "3AA0FF"), ("seguro", "6C7CFF"), ("café", "B07A4A"),
    ]

    static func color(for name: String) -> Color {
        let n = name.lowercased()
        for (k, hex) in known where n.contains(k) { return Color(hex: hex) }
        let palette = ["46D9A6", "4D8CFF", "FF9A1F", "C08CFF", "FF6B4A", "2EE6F5", "FFD000", "F25CC9"]
        let h = n.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }
        return Color(hex: palette[h % palette.count])
    }

    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." }).filter { !$0.isEmpty }
        if words.count >= 2, let a = words[0].first, let b = words[1].first, name.count > 8 {
            return String([a, b]).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

/// Burbuja redonda con la inicial y el color del comercio.
struct MerchantBubble: View {
    var name: String
    var size: CGFloat = 40
    var color: Color? = nil

    var body: some View {
        let c = color ?? MerchantStyle.color(for: name)
        ZStack {
            Circle().fill(c.gradient)
            Text(MerchantStyle.initials(for: name))
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Categorización automática

enum Categorizer {
    private static let rules: [(Category, [String])] = [
        (.supermercado, ["mercadona", "carrefour", "lidl", "dia ", "alcampo", "eroski", "aldi", "hipercor", "consum", "ahorramas", "supermerc"]),
        (.combustible, ["shell", "repsol", "cepsa", "galp", "bp ", "gasolin", "petronor", "ballenoil", "plenoil"]),
        (.suscripciones, ["netflix", "spotify", "disney", "hbo", "max.com", "prime video", "youtube", "icloud", "apple.com", "google one", "chatgpt", "openai", "claude", "dazn", "filmin", "playstation", "xbox"]),
        (.telefonia, ["movistar", "vodafone", "orange", "digi", "yoigo", "o2 ", "pepephone", "masmovil", "lowi", "simyo"]),
        (.hogar, ["alquiler", "iberdrola", "endesa", "naturgy", "canal de isabel", "agua", "comunidad", "ikea", "leroy", "hipoteca", "seguro hogar"]),
        (.restaurantes, ["restaur", "burger", "mcdonald", "telepizza", "domino", "kfc", "glovo", "just eat", "uber eats", "tapas", "taberna", "bar "]),
        (.cafe, ["starbucks", "cafe", "café", "cafeter", "panader", "100 montaditos"]),
        (.transporte, ["uber", "cabify", "bolt", "renfe", "metro", "emt", "parking", "peaje", "itv", "taller", "dgt"]),
        (.ocio, ["cine", "ticketmaster", "booking", "airbnb", "ryanair", "iberia", "vueling", "steam", "hotel"]),
        (.compras, ["amazon", "zara", "primark", "el corte ingl", "mediamarkt", "decathlon", "aliexpress", "shein", "fnac"]),
        (.salud, ["farmacia", "clinica", "clínica", "dentist", "sanitas", "adeslas", "hospital"]),
        (.cuidado, ["peluquer", "barber", "druni", "primor", "sephora"]),
        (.deporte, ["gym", "gimnas", "synergym", "basic-fit", "basic fit", "mcfit", "fitness"]),
        (.transferencias, ["transferencia", "traspaso", "bizum"]),
    ]

    static func category(for text: String, amount: Double) -> Category {
        let t = " " + text.lowercased() + " "
        for (cat, keys) in rules where keys.contains(where: { t.contains($0) }) { return cat }
        if amount > 0 {
            if t.contains("nomina") || t.contains("nómina") || t.contains("salario") { return .ingresos }
            return .ingresos
        }
        return .otros
    }
}
