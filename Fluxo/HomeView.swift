import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @Binding var tab: AppTab
    @State private var addingTx = false

    private var cal: Calendar { Schedule.cal }
    private var now: DateComponents { cal.dateComponents([.year, .month], from: .now) }
    private var prev: DateComponents { cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -1, to: .now)!) }

    var body: some View {
        Screen(title: "Fluxo") {
            if model.data.subscriptions.isEmpty && model.data.transactions.isEmpty {
                welcome
            } else {
                summary
                upcoming
                recent
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingTx = true } label: { Image(systemName: "plus") }
            }
            if model.data.bank != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await model.sync() }
                    } label: {
                        if model.syncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(model.syncing)
                }
            }
        }
        .sheet(isPresented: $addingTx) { TransactionEditor(transaction: nil) }
    }

    // MARK: Bienvenida

    private var welcome: some View {
        VStack(spacing: 14) {
            GlassCard(tint: Theme.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "water.waves").font(.system(size: 38)).foregroundStyle(Theme.accent)
                    Text("Bienvenido a Fluxo").font(.title2.bold())
                    Text("Ve en un calendario todo lo que pagas: suscripciones, recibos y los movimientos de tu banco.")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                model.loadDemo()
            } label: {
                Label("Probar con datos de ejemplo", systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            Button {
                tab = .settings
            } label: {
                Label("Conectar mi banco", systemImage: "building.columns").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
        .padding(.top, 20)
    }

    // MARK: Resumen

    private var summary: some View {
        let spentNow = Schedule.monthSpending(model.data.transactions, year: now.year!, month: now.month!)
        let spentPrev = Schedule.monthSpending(model.data.transactions, year: prev.year!, month: prev.month!)
        let fixed = Schedule.occurrences(model.data.subscriptions, year: now.year!, month: now.month!)
            .reduce(0) { $0 + $1.subscription.amount }
        let balance = model.data.bank?.accounts.compactMap(\.balance).reduce(0, +)

        return GlassCard(radius: 28, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                if let balance, model.data.bank?.accounts.contains(where: { $0.balance != nil }) == true {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saldo").font(.subheadline).foregroundStyle(.secondary)
                        Text(Fmt.money(balance)).font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gastado en \(Fmt.monthYear(.now).components(separatedBy: " ").first ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.money(spentNow)).font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        ChangeBadge(current: spentNow, previous: spentPrev)
                    }
                }
                HStack {
                    statPill("Pagos fijos", Fmt.money(fixed), "repeat")
                    statPill("Mes pasado", Fmt.moneyShort(spentPrev), "clock.arrow.circlepath")
                }
                if model.data.demo {
                    Label("Modo demo", systemImage: "sparkles").font(.caption).foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func statPill(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: Próximos cobros

    private var upcoming: some View {
        let next = Schedule.upcoming(model.data.subscriptions).prefix(4)
        return VStack(spacing: 10) {
            sectionHeader("Próximos cobros", action: "Calendario") { tab = .calendar }
            if next.isEmpty {
                EmptyStateCard(icon: "calendar", title: "Sin cobros próximos", text: "Añade pagos fijos en Ajustes.")
            }
            ForEach(Array(next)) { o in
                let rel = Schedule.relative(o.date)
                GlassCard {
                    PaymentRow(name: o.subscription.name,
                               subtitle: "\(o.subscription.frequency.name) · \(Fmt.shortDate(o.date))",
                               amount: o.subscription.amount, status: rel,
                               statusColor: rel == "Hoy" ? Theme.negative : .secondary,
                               bubbleColor: o.subscription.color)
                }
            }
        }
    }

    // MARK: Últimos movimientos

    private var recent: some View {
        let txs = model.transactions.prefix(5)
        return VStack(spacing: 10) {
            sectionHeader("Últimos movimientos", action: "Ver todos") { tab = .movements }
            ForEach(Array(txs)) { t in GlassCard { TransactionRow(t: t) } }
        }
    }

    private func sectionHeader(_ title: String, action: String, _ go: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(action, action: go).font(.subheadline)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}
