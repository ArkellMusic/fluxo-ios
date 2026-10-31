import SwiftUI

struct TransactionsScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var category: Category? = nil
    @State private var range: DateRange = .all
    @State private var editing: Transaction? = nil
    @State private var adding = false
    @State private var importing = false

    enum DateRange: String, CaseIterable, Identifiable {
        case all = "Todas", thisMonth = "Este mes", lastMonth = "Mes pasado", last7 = "7 días"
        var id: String { rawValue }
    }

    private var filtered: [Transaction] {
        let c = Schedule.cal
        return model.transactions.filter { t in
            if let category, t.category != category { return false }
            if !search.isEmpty {
                let s = search.lowercased()
                if !t.merchant.lowercased().contains(s) && !t.category.name.lowercased().contains(s)
                    && !(t.note?.lowercased().contains(s) ?? false) { return false }
            }
            switch range {
            case .all: return true
            case .thisMonth: return c.isDate(t.date, equalTo: .now, toGranularity: .month)
            case .lastMonth: return c.isDate(t.date, equalTo: c.date(byAdding: .month, value: -1, to: .now)!, toGranularity: .month)
            case .last7: return t.date >= c.date(byAdding: .day, value: -7, to: c.startOfDay(for: .now))!
            }
        }
    }

    private var grouped: [(Date, [Transaction])] {
        let c = Schedule.cal
        let g = Dictionary(grouping: filtered) { c.startOfDay(for: $0.date) }
        return g.keys.sorted(by: >).map { ($0, g[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    LazyVStack(spacing: 10, pinnedViews: []) {
                        filters
                        if filtered.isEmpty {
                            EmptyStateCard(icon: "magnifyingglass", title: "Sin movimientos",
                                           text: model.data.transactions.isEmpty ? "Conecta tu banco o añade un gasto con +." : "Prueba con otro filtro.")
                        }
                        ForEach(grouped, id: \.0) { day, txs in
                            HStack {
                                Text(Fmt.dayHeader(day)).font(.headline).foregroundStyle(.secondary)
                                Spacer()
                                let total = txs.filter(\.isExpense).reduce(0) { $0 - $1.amount }
                                if total > 0 { Text(Fmt.money(total)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, 4).padding(.top, 10)
                            ForEach(txs) { t in
                                GlassCard { TransactionRow(t: t) }
                                    .onTapGesture { editing = t }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Movimientos")
            .toolbarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Buscar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { adding = true } label: { Label("Añadir movimiento", systemImage: "plus") }
                        Button { importing = true } label: { Label("Importar extracto", systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $importing) { ImportStatementView() }
            .sheet(item: $editing) { t in TransactionEditor(transaction: t) }
            .sheet(isPresented: $adding) { TransactionEditor(transaction: nil) }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Fechas", selection: $range) {
                            ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        chip(range == .all ? "Fechas" : range.rawValue, active: range != .all)
                    }
                    Menu {
                        Button("Todas") { category = nil }
                        ForEach(Category.allCases) { c in
                            Button { category = c } label: { Label(c.name, systemImage: c.symbol) }
                        }
                    } label: {
                        chip(category?.name ?? "Categoría", active: category != nil)
                    }
                    if category != nil || range != .all {
                        Button {
                            category = nil; range = .all
                        } label: {
                            Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                                .padding(10)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(active ? Theme.accent : .primary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(active ? Glass.regular.tint(Theme.accent.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
    }
}

// MARK: - Editor de movimiento

struct TransactionEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var transaction: Transaction?

    @State private var merchant = ""
    @State private var amount = ""
    @State private var isExpense = true
    @State private var date = Date()
    @State private var category: Category = .otros
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Comercio o concepto", text: $merchant)
                    TextField("Importe", text: $amount).keyboardType(.decimalPad)
                    Picker("Tipo", selection: $isExpense) {
                        Text("Gasto").tag(true)
                        Text("Ingreso").tag(false)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                }
                Section("Categoría") {
                    Picker("Categoría", selection: $category) {
                        ForEach(Category.allCases) { c in Label(c.name, systemImage: c.symbol).tag(c) }
                    }
                }
                Section("Nota") { TextField("Opcional", text: $note, axis: .vertical) }
                if let transaction {
                    Section {
                        if transaction.source == .bank {
                            Text("Viene de tu banco: puedes cambiar la categoría.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Eliminar movimiento", role: .destructive) {
                            model.delete(transaction); dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(transaction == nil ? "Nuevo movimiento" : "Movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(merchant.isEmpty || parsedAmount == nil)
                }
            }
            .onAppear(perform: load)
            .onChange(of: merchant) { _, new in
                if transaction == nil, category == .otros {
                    let c = Categorizer.category(for: new, amount: -1)
                    if c != .otros { category = c }
                }
            }
        }
    }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func load() {
        guard let t = transaction else { return }
        merchant = t.merchant
        amount = String(format: "%.2f", abs(t.amount)).replacingOccurrences(of: ".", with: ",")
        isExpense = t.isExpense
        date = t.date
        category = t.category
        note = t.note ?? ""
    }

    private func save() {
        guard let v = parsedAmount else { return }
        let signed = isExpense ? -abs(v) : abs(v)
        if var t = transaction {
            t.merchant = merchant; t.amount = signed; t.date = date; t.category = category
            t.note = note.isEmpty ? nil : note
            model.update(t)
        } else {
            model.add(Transaction(id: "m-" + UUID().uuidString, date: date, amount: signed, merchant: merchant,
                                  category: category, account: "Manual", note: note.isEmpty ? nil : note, source: .manual))
        }
        dismiss()
    }
}
