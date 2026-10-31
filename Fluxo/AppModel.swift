import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var data: AppData
    @Published var syncing = false
    @Published var message: String?
    /// Archivos recibidos desde "Abrir con…" / Compartir, pendientes de importar.
    @Published var incomingFiles: [URL] = []

    init() {
        data = SharedStore.load()
    }

    var transactions: [Transaction] { data.transactions.sorted { $0.date > $1.date } }
    var subscriptions: [Subscription] { data.subscriptions.sorted { $0.day < $1.day } }

    func persist() {
        SharedStore.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Logos

    /// Descarga los logos de pagos fijos y comercios para que también salgan en los widgets.
    func prefetchLogos() async {
        var domains = Set<String>()
        for s in data.subscriptions {
            if let d = MerchantStyle.cleanDomain(s.domain) ?? MerchantStyle.domain(for: s.name) { domains.insert(d) }
        }
        for t in data.transactions.prefix(300) {
            if let d = MerchantStyle.domain(for: t.merchant) { domains.insert(d) }
        }
        var gotNew = false
        for d in domains where await LogoStore.shared.fetch(d) { gotNew = true }
        if gotNew { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: Pagos fijos

    func upsert(_ s: Subscription) {
        if let i = data.subscriptions.firstIndex(where: { $0.id == s.id }) {
            data.subscriptions[i] = s
        } else {
            data.subscriptions.append(s)
        }
        persist()
        Task { await prefetchLogos() }
    }

    func delete(_ s: Subscription) {
        data.subscriptions.removeAll { $0.id == s.id }
        persist()
    }

    // MARK: Movimientos

    /// Añade movimientos importados sin duplicar (mismo id, o mismo día e importe que uno ya existente).
    func importTransactions(_ incoming: [Transaction]) -> (added: Int, duplicates: Int) {
        if data.demo {
            data.transactions.removeAll { $0.source == .demo }
            data.demo = false
        }
        let c = Schedule.cal
        func key(_ t: Transaction) -> String {
            "\(c.startOfDay(for: t.date).timeIntervalSince1970)|\(String(format: "%.2f", t.amount))"
        }
        var ids = Set(data.transactions.map(\.id))
        // Cuenta cuántos movimientos iguales (día + importe) ya hay, para no duplicar si se importa
        // el mismo periodo en otro formato, pero sí permitir dos cargos iguales el mismo día.
        var existing: [String: Int] = [:]
        for t in data.transactions { existing[key(t), default: 0] += 1 }
        var added = 0, dup = 0
        for t in incoming {
            if ids.contains(t.id) { dup += 1; continue }
            let k = key(t)
            if let n = existing[k], n > 0 { existing[k] = n - 1; dup += 1; continue }
            data.transactions.append(t)
            ids.insert(t.id)
            added += 1
        }
        persist()
        Task { await prefetchLogos() }
        return (added, dup)
    }

    func add(_ t: Transaction) {
        data.transactions.append(t)
        persist()
    }

    func update(_ t: Transaction) {
        if let i = data.transactions.firstIndex(where: { $0.id == t.id }) {
            data.transactions[i] = t
            persist()
        }
    }

    func delete(_ t: Transaction) {
        data.transactions.removeAll { $0.id == t.id }
        persist()
    }

    /// Si un pago fijo ya tiene un cargo parecido en el banco ese mes, se marca como pagado.
    func isPaid(_ o: Occurrence) -> Bool {
        if Schedule.daysUntil(o.date) < 0 { return true }
        let c = Schedule.cal
        let key = o.subscription.name.lowercased().prefix(5)
        return data.transactions.contains { t in
            t.isExpense &&
            c.isDate(t.date, equalTo: o.date, toGranularity: .month) &&
            abs(-t.amount - o.subscription.amount) < 0.6 &&
            t.merchant.lowercased().contains(key)
        }
    }

    // MARK: Demo

    func loadDemo() {
        data = DemoData.make(keepingBank: data.bank)
        persist()
        Task { await prefetchLogos() }
    }

    func clearDemo() {
        data.transactions.removeAll { $0.source == .demo }
        data.subscriptions.removeAll()
        data.demo = false
        persist()
    }

    func resetAll() {
        data = AppData()
        BankKeys.clear()
        persist()
    }

    // MARK: Detectar pagos fijos desde el banco

    /// Busca cargos que se repiten cada mes con importe parecido.
    func detectRecurring() -> [Subscription] {
        let c = Schedule.cal
        let expenses = data.transactions.filter { $0.isExpense && $0.category != .transferencias }
        let groups = Dictionary(grouping: expenses) { $0.merchant.lowercased().trimmingCharacters(in: .whitespaces) }
        var found: [Subscription] = []
        for (_, txs) in groups {
            let months = Set(txs.map { c.dateComponents([.year, .month], from: $0.date) })
            guard months.count >= 2, let last = txs.max(by: { $0.date < $1.date }) else { continue }
            let amounts = txs.map { -$0.amount }
            let avg = amounts.reduce(0, +) / Double(amounts.count)
            guard amounts.allSatisfy({ abs($0 - avg) <= max(2, avg * 0.1) }) else { continue }
            if data.subscriptions.contains(where: { $0.name.lowercased() == last.merchant.lowercased() }) { continue }
            found.append(Subscription(name: last.merchant, amount: (-last.amount * 100).rounded() / 100,
                                      day: c.component(.day, from: last.date), category: last.category))
        }
        return found.sorted { $0.day < $1.day }
    }

    // MARK: Banco

    func sync() async {
        guard let link = data.bank else { return }
        syncing = true
        defer { syncing = false }
        do {
            let from = Calendar.current.date(byAdding: .day, value: data.lastSync == nil ? -90 : -10, to: .now)!
            var newLink = link
            var incoming: [Transaction] = []
            for (i, acc) in link.accounts.enumerated() {
                incoming += try await EnableBanking.transactions(account: acc, from: from)
                if let bal = try? await EnableBanking.balance(account: acc) {
                    newLink.accounts[i].balance = bal
                }
            }
            var byId = Dictionary(uniqueKeysWithValues: data.transactions.map { ($0.id, $0) })
            for t in incoming {
                if var existing = byId[t.id] {
                    // Respeta la categoría que haya cambiado el usuario
                    existing.amount = t.amount
                    existing.date = t.date
                    byId[t.id] = existing
                } else {
                    byId[t.id] = t
                }
            }
            if data.demo {
                byId = byId.filter { $0.value.source != .demo }
                data.demo = false
            }
            data.transactions = Array(byId.values)
            data.bank = newLink
            data.lastSync = .now
            persist()
            message = "Sincronizado: \(incoming.count) movimientos"
        } catch {
            message = "Error al sincronizar: \(error.localizedDescription)"
        }
    }
}
