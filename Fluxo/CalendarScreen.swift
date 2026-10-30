import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var month: Date = Schedule.cal.date(from: Schedule.cal.dateComponents([.year, .month], from: .now))!
    @State private var selected: Date? = nil
    @State private var editing: Subscription? = nil
    @State private var showPicker = false

    private var cal: Calendar { Schedule.cal }
    private var comps: DateComponents { cal.dateComponents([.year, .month], from: month) }
    private var occurrences: [Occurrence] {
        Schedule.occurrences(model.data.subscriptions, year: comps.year!, month: comps.month!)
    }

    var body: some View {
        Screen(title: "Calendario") {
            header
            weekdayRow
            grid
            if let selected {
                dayDetail(selected)
            } else {
                monthList
            }
        }
        .sheet(item: $editing) { s in
            SubscriptionEditor(subscription: s)
        }
        .sheet(isPresented: $showPicker) {
            MonthPicker(month: $month)
                .presentationDetents([.height(300)])
        }
    }

    // MARK: Cabecera

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                    .buttonStyle(.glass)
                Button { showPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(Fmt.monthYear(month)).font(.title3.weight(.semibold))
                        Image(systemName: "chevron.down").font(.footnote.weight(.bold))
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                    .buttonStyle(.glass)
            }
        }
        .padding(.top, 6)
    }

    private var weekdayRow: some View {
        HStack(spacing: 6) {
            ForEach(["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"], id: \.self) { d in
                Text(d).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Cuadrícula

    private var days: [Date] {
        guard let first = cal.date(from: comps) else { return [] }
        let weekday = (cal.component(.weekday, from: first) + 5) % 7 // lunes = 0
        let start = cal.date(byAdding: .day, value: -weekday, to: first)!
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let cells = Int(ceil(Double(weekday + count) / 7.0)) * 7
        return (0..<cells).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var grid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(days, id: \.self) { day in
                DayCell(day: day,
                        inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                        isToday: cal.isDateInToday(day),
                        isSelected: selected.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                        occurrences: occurrences.filter { cal.isDate($0.date, inSameDayAs: day) },
                        spent: spent(on: day))
                .onTapGesture {
                    withAnimation(.snappy) {
                        if let s = selected, cal.isDate(s, inSameDayAs: day) { selected = nil } else { selected = day }
                    }
                }
            }
        }
    }

    private func spent(on day: Date) -> Double {
        model.data.transactions
            .filter { $0.isExpense && $0.category != .transferencias && cal.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 - $1.amount }
    }

    // MARK: Lista del mes

    private var monthList: some View {
        VStack(spacing: 10) {
            if occurrences.isEmpty {
                EmptyStateCard(icon: "calendar.badge.plus", title: "Sin pagos fijos",
                               text: "Añade tus suscripciones y recibos en Ajustes › Pagos fijos, o carga el modo demo.")
            } else {
                HStack {
                    Text("Pagos fijos del mes").font(.headline)
                    Spacer()
                    Text(Fmt.money(occurrences.reduce(0) { $0 + $1.subscription.amount }))
                        .font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.top, 8)
                ForEach(occurrences) { o in
                    occurrenceRow(o)
                }
            }
        }
    }

    private func occurrenceRow(_ o: Occurrence) -> some View {
        let paid = model.isPaid(o)
        let rel = Schedule.relative(o.date)
        let status = paid ? "Pagado" : rel
        let color: Color = paid ? Theme.positive : (rel == "Hoy" ? Theme.negative : .secondary)
        return GlassCard {
            PaymentRow(name: o.subscription.name,
                       subtitle: "\(o.subscription.frequency.name) · \(Fmt.shortDate(o.date))",
                       amount: o.subscription.amount, status: status, statusColor: color,
                       bubbleColor: o.subscription.color)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = o.subscription }
    }

    // MARK: Detalle de un día

    private func dayDetail(_ day: Date) -> some View {
        let occ = occurrences.filter { cal.isDate($0.date, inSameDayAs: day) }
        let txs = model.transactions.filter { cal.isDate($0.date, inSameDayAs: day) }
        return VStack(spacing: 10) {
            HStack {
                Text(Fmt.dayHeader(day)).font(.headline)
                Spacer()
                Button("Ver mes") { withAnimation(.snappy) { selected = nil } }
                    .font(.subheadline)
            }
            .padding(.horizontal, 4).padding(.top, 8)
            if occ.isEmpty && txs.isEmpty {
                EmptyStateCard(icon: "checkmark.circle", title: "Nada este día", text: "No hay cobros ni movimientos.")
            }
            ForEach(occ) { o in occurrenceRow(o) }
            ForEach(txs) { t in GlassCard { TransactionRow(t: t) } }
        }
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) {
            month = cal.date(byAdding: .month, value: n, to: month)!
            selected = nil
        }
    }
}

struct DayCell: View {
    var day: Date
    var inMonth: Bool
    var isToday: Bool
    var isSelected: Bool
    var occurrences: [Occurrence]
    var spent: Double

    var body: some View {
        VStack(spacing: 6) {
            Text("\(Schedule.cal.component(.day, from: day))")
                .font(.system(size: 17, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(isToday ? Theme.accent : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
            ZStack {
                if let first = occurrences.first {
                    MerchantBubble(name: first.subscription.name, size: 30, color: first.subscription.color)
                        .opacity(inMonth ? 1 : 0.4)
                        .overlay(alignment: .topTrailing) {
                            if occurrences.count > 1 {
                                Text("+\(occurrences.count - 1)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Capsule().fill(.black.opacity(0.7)))
                                    .offset(x: 8, y: -4)
                            }
                        }
                } else if spent > 0 && inMonth {
                    Text(Fmt.moneyShort(spent))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .frame(height: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(inMonth ? (isSelected ? 0.16 : 0.05) : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : (isToday ? Theme.accent.opacity(0.4) : .clear), lineWidth: 1.5)
        )
    }
}

struct MonthPicker: View {
    @Binding var month: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Mes", selection: $month, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_ES"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") {
                            let c = Schedule.cal
                            month = c.date(from: c.dateComponents([.year, .month], from: month))!
                            dismiss()
                        }
                    }
                }
        }
    }
}
