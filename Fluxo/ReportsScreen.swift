import SwiftUI
import Charts

struct CategoryTotal: Identifiable {
    var category: Category
    var total: Double
    var previous: Double
    var id: String { category.rawValue }
}

struct ReportsScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var month: Date = Schedule.cal.date(from: Schedule.cal.dateComponents([.year, .month], from: .now))!
    @State private var selectedAngle: Double? = nil
    @State private var showBars = false

    private var cal: Calendar { Schedule.cal }

    private func totals(for m: Date) -> [Category: Double] {
        var out: [Category: Double] = [:]
        for t in model.data.transactions where t.isExpense && t.category != .transferencias
            && cal.isDate(t.date, equalTo: m, toGranularity: .month) {
            out[t.category, default: 0] -= t.amount
        }
        return out
    }

    private var rows: [CategoryTotal] {
        let now = totals(for: month)
        let prev = totals(for: cal.date(byAdding: .month, value: -1, to: month)!)
        return now.map { CategoryTotal(category: $0.key, total: $0.value, previous: prev[$0.key] ?? 0) }
            .sorted { $0.total > $1.total }
    }

    private var selectedCategory: CategoryTotal? {
        guard let selectedAngle else { return nil }
        var acc = 0.0
        for r in rows {
            acc += r.total
            if selectedAngle <= acc { return r }
        }
        return nil
    }

    var body: some View {
        Screen(title: "Gastos por categoría") {
            let data = rows
            let total = data.reduce(0) { $0 + $1.total }
            let prevTotal = data.reduce(0) { $0 + $1.previous }

            HStack(spacing: 10) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass)
                Text(Fmt.monthYear(month)).font(.headline).frame(maxWidth: .infinity)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass)
            }
            .padding(.top, 6)

            GlassCard(radius: 28, padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.moneyShort(total)).font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        ChangeBadge(current: total, previous: prevTotal)
                        Spacer()
                        Button { withAnimation(.snappy) { showBars.toggle() } } label: {
                            Image(systemName: showBars ? "chart.pie" : "chart.bar")
                        }
                        .buttonStyle(.glass)
                    }
                    if data.isEmpty {
                        Text("No hay gastos este mes.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if showBars {
                        barChart
                    } else {
                        donut(data, total: total)
                    }
                }
            }

            ForEach(data) { r in
                NavigationLink {
                    CategoryDetail(category: r.category, month: month)
                } label: {
                    categoryRow(r, total: total)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func donut(_ data: [CategoryTotal], total: Double) -> some View {
        Chart(data) { r in
            SectorMark(angle: .value("Gasto", r.total), innerRadius: .ratio(0.6), angularInset: 2)
                .cornerRadius(6)
                .foregroundStyle(r.category.color)
                .opacity(selectedCategory == nil || selectedCategory?.id == r.id ? 1 : 0.35)
                .annotation(position: .overlay) {
                    if r.total / total >= 0.08 {
                        Text("\(Int((r.total / total * 100).rounded()))%")
                            .font(.caption.weight(.bold)).foregroundStyle(.black.opacity(0.8))
                    }
                }
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame {
                    let f = geo[frame]
                    VStack(spacing: 2) {
                        if let s = selectedCategory {
                            Text(s.category.name).font(.subheadline.weight(.semibold))
                            Text(Fmt.money(s.total)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        } else {
                            Text("Todas las\ncategorías").font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        }
                    }
                    .position(x: f.midX, y: f.midY)
                }
            }
        }
        .frame(height: 260)
    }

    private var barChart: some View {
        let last6 = (0..<6).reversed().map { cal.date(byAdding: .month, value: -$0, to: month)! }
        return Chart(last6, id: \.self) { m in
            let comps = cal.dateComponents([.year, .month], from: m)
            BarMark(x: .value("Mes", Fmt.monthYear(m).prefix(3).capitalized),
                    y: .value("Gasto", Schedule.monthSpending(model.data.transactions, year: comps.year!, month: comps.month!)))
                .foregroundStyle(cal.isDate(m, equalTo: month, toGranularity: .month) ? Theme.accent : Theme.accent.opacity(0.35))
                .cornerRadius(6)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 220)
    }

    private func categoryRow(_ r: CategoryTotal, total: Double) -> some View {
        let share = total > 0 ? r.total / total : 0
        return HStack(spacing: 14) {
            Image(systemName: r.category.symbol)
                .font(.title3)
                .foregroundStyle(r.category.color)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.category.name).font(.headline)
                Text("\(Int((share * 100).rounded()))%").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.moneyShort(r.total)).font(.headline.monospacedDigit())
                ChangeBadge(current: r.total, previous: r.previous)
            }
        }
        .padding(14)
        .background(alignment: .leading) {
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(r.category.color.opacity(0.18))
                    .frame(width: max(44, g.size.width * share))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month)!; selectedAngle = nil }
    }
}

struct CategoryDetail: View {
    @EnvironmentObject var model: AppModel
    var category: Category
    var month: Date

    var body: some View {
        let txs = model.transactions.filter {
            $0.category == category && Schedule.cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(txs) { t in GlassCard { TransactionRow(t: t) } }
                }
                .padding(16)
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
