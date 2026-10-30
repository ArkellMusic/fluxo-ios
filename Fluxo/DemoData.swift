import Foundation

enum DemoData {
    static func make(keepingBank bank: BankLink?) -> AppData {
        var d = AppData()
        d.bank = bank
        d.demo = true
        d.subscriptions = [
            Subscription(name: "Netflix", amount: 13.99, day: 5),
            Subscription(name: "DIGI", amount: 20.00, day: 7, category: .telefonia),
            Subscription(name: "Movistar", amount: 35.00, day: 8, category: .telefonia),
            Subscription(name: "Spotify Familiar", amount: 20.99, day: 10),
            Subscription(name: "Disney+", amount: 9.99, day: 11),
            Subscription(name: "Gimnasio", amount: 39.90, day: 12, category: .deporte),
            Subscription(name: "Google One", amount: 1.99, day: 13),
            Subscription(name: "Alquiler", amount: 750, day: 15, category: .hogar),
            Subscription(name: "Luz", amount: 58.40, day: 16, category: .hogar),
            Subscription(name: "Seguro coche", amount: 312, day: 19, frequency: .anual, startMonth: Schedule.cal.component(.month, from: .now), category: .transporte),
            Subscription(name: "Amazon Prime", amount: 4.99, day: 22),
            Subscription(name: "ChatGPT Plus", amount: 22.99, day: 27),
        ]

        // Movimientos de los últimos ~75 días, generados de forma estable.
        var rng = SeededRNG(seed: 2026)
        let c = Schedule.cal
        let today = c.startOfDay(for: .now)
        var txs: [Transaction] = []
        func add(_ date: Date, _ amount: Double, _ merchant: String, _ cat: Category, _ acc: String = "ING Cuenta NoCuenta") {
            txs.append(Transaction(id: "demo-\(txs.count)", date: date, amount: amount, merchant: merchant,
                                   category: cat, account: acc, source: .demo))
        }

        for back in 0..<75 {
            guard let day = c.date(byAdding: .day, value: -back, to: today) else { continue }
            let dom = c.component(.day, from: day)
            // Pagos fijos ya cobrados
            for s in d.subscriptions where s.day == dom && s.occurs(inMonth: c.component(.month, from: day)) {
                add(day, -s.amount, s.name, s.category)
            }
            if dom == 28 { add(day, 1850, "Nómina", .ingresos) }
            if rng.chance(0.35) { add(day, -round2(rng.range(18, 115)), ["Mercadona", "Lidl", "Carrefour"][rng.int(3)], .supermercado) }
            if rng.chance(0.25) { add(day, -round2(rng.range(1.8, 6.5)), ["Café Central", "Shell", "Panadería"][rng.int(3)], .cafe) }
            if rng.chance(0.12) { add(day, -round2(rng.range(40, 75)), ["Shell", "Repsol"][rng.int(2)], .combustible) }
            if rng.chance(0.15) { add(day, -round2(rng.range(12, 48)), ["Taberna La Plaza", "Burger", "Glovo"][rng.int(3)], .restaurantes) }
            if rng.chance(0.07) { add(day, -round2(rng.range(15, 90)), ["Amazon", "Zara", "Decathlon"][rng.int(3)], .compras) }
            if rng.chance(0.05) { add(day, -round2(rng.range(8, 30)), "Farmacia", .salud) }
            if rng.chance(0.05) { add(day, -round2(rng.range(12, 25)), "Peluquería", .cuidado) }
            if rng.chance(0.06) { add(day, -round2(rng.range(10, 60)), "Cine", .ocio) }
            if rng.chance(0.04) { add(day, -round2(rng.range(20, 100)), "Bizum a Nico", .transferencias) }
        }
        d.transactions = txs
        return d
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}
