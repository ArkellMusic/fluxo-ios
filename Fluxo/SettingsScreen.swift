import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: Subscription? = nil
    @State private var adding = false
    @State private var detected: [Subscription] = []
    @State private var showDetected = false
    @State private var confirmReset = false
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                bankSection
                subscriptionsSection
                dataSection
                Section("Widgets") {
                    Label("Mantén pulsada la pantalla de inicio o la de bloqueo › Editar › Añadir widget › Fluxo.", systemImage: "rectangle.3.group")
                        .font(.footnote)
                    Label("Los widgets solo funcionan si instalas Fluxo con SideStore, no dentro de LiveContainer.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Fluxo 1.0 · tus datos se guardan solo en este iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Ajustes")
            .toolbarTitleDisplayMode(.inline)
            .sheet(item: $editing) { SubscriptionEditor(subscription: $0) }
            .sheet(isPresented: $adding) { SubscriptionEditor(subscription: nil) }
            .sheet(isPresented: $showDetected) { DetectedSheet(items: detected) }
            .sheet(isPresented: $importing) { ImportStatementView() }
            .confirmationDialog("¿Borrar todos los datos de Fluxo?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Borrar todo", role: .destructive) { model.resetAll() }
            }
        }
    }

    // MARK: Banco

    private var bankSection: some View {
        Section {
            if let link = model.data.bank {
                HStack {
                    Image(systemName: "building.columns.fill").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text(link.aspspName).font(.headline)
                        Text("Acceso válido hasta \(Fmt.shortDate(link.validUntil))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(link.accounts) { a in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(a.name)
                            if let iban = a.iban { Text("•••• " + iban.suffix(4)).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if let b = a.balance { Text(Fmt.money(b)).monospacedDigit() }
                    }
                }
                Button {
                    Task { await model.sync() }
                } label: {
                    HStack {
                        Label("Sincronizar ahora", systemImage: "arrow.clockwise")
                        Spacer()
                        if model.syncing { ProgressView() }
                    }
                }
                .disabled(model.syncing)
                if let last = model.data.lastSync {
                    Text("Última sincronización: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink("Reconectar o cambiar de banco") { BankSetupView() }
                Button("Desconectar banco", role: .destructive) {
                    model.data.bank = nil
                    model.persist()
                }
            } else {
                NavigationLink {
                    BankSetupView()
                } label: {
                    Label("Conectar mi banco", systemImage: "building.columns")
                }
            }
        } header: {
            Text("Banco")
        } footer: {
            Text("Conexión de solo lectura mediante Enable Banking (PSD2). Fluxo nunca ve tu contraseña del banco.")
        }
    }

    // MARK: Pagos fijos

    private var subscriptionsSection: some View {
        Section {
            ForEach(model.subscriptions) { s in
                Button { editing = s } label: {
                    HStack(spacing: 12) {
                        MerchantBubble(name: s.name, size: 32, color: s.color, domain: s.domain)
                        VStack(alignment: .leading) {
                            Text(s.name).foregroundStyle(.primary)
                            Text("Día \(s.day) · \(s.frequency.name)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.money(s.amount)).monospacedDigit().foregroundStyle(.primary)
                    }
                }
            }
            .onDelete { idx in
                let list = model.subscriptions
                idx.forEach { model.delete(list[$0]) }
            }
            Button { adding = true } label: { Label("Añadir pago fijo", systemImage: "plus.circle") }
            if !model.data.transactions.isEmpty {
                Button {
                    detected = model.detectRecurring()
                    if detected.isEmpty { model.message = "No he encontrado cargos repetidos nuevos." } else { showDetected = true }
                } label: {
                    Label("Detectar pagos fijos en mis movimientos", systemImage: "wand.and.stars")
                }
            }
        } header: {
            Text("Pagos fijos")
        } footer: {
            Text("Suscripciones y recibos que se cobran siempre el mismo día. Son los que aparecen en el calendario.")
        }
    }

    // MARK: Datos

    private var dataSection: some View {
        Section("Datos") {
            Button { importing = true } label: { Label("Importar extracto del banco", systemImage: "square.and.arrow.down") }
            if model.data.demo {
                Button("Quitar datos de ejemplo") { model.clearDemo() }
            } else {
                Button("Cargar datos de ejemplo") { model.loadDemo() }
            }
            Button("Borrar todos los datos", role: .destructive) { confirmReset = true }
        }
    }
}

// MARK: - Pagos detectados

struct DetectedSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var items: [Subscription]
    @State private var chosen: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(items) { s in
                Button {
                    if chosen.contains(s.id) { chosen.remove(s.id) } else { chosen.insert(s.id) }
                } label: {
                    HStack {
                        Image(systemName: chosen.contains(s.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Theme.accent)
                        MerchantBubble(name: s.name, size: 30)
                        VStack(alignment: .leading) {
                            Text(s.name).foregroundStyle(.primary)
                            Text("Día \(s.day)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.money(s.amount)).foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Pagos repetidos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir (\(chosen.count))") {
                        items.filter { chosen.contains($0.id) }.forEach { model.upsert($0) }
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .onAppear { chosen = Set(items.map(\.id)) }
        }
    }
}

// MARK: - Editor de pago fijo

struct SubscriptionEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var subscription: Subscription?

    @State private var name = ""
    @State private var amount = ""
    @State private var day = 1
    @State private var frequency: Frequency = .mensual
    @State private var startMonth = Schedule.cal.component(.month, from: .now)
    @State private var category: Category = .suscripciones
    @State private var color: Color = Theme.accent
    @State private var customColor = false
    @State private var domain = ""

    private let months = Schedule.cal.standaloneMonthSymbols

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        MerchantBubble(name: name.isEmpty ? "?" : name, size: 64,
                                       color: customColor ? color : MerchantStyle.color(for: name),
                                       domain: MerchantStyle.cleanDomain(domain))
                            .id((MerchantStyle.cleanDomain(domain) ?? "") + name)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Nombre (Netflix, Alquiler…)", text: $name)
                    TextField("Importe", text: $amount).keyboardType(.decimalPad)
                    Stepper("Día de cobro: \(day)", value: $day, in: 1...31)
                    Picker("Frecuencia", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.name).tag($0) }
                    }
                    if frequency != .mensual {
                        Picker("Primer mes", selection: $startMonth) {
                            ForEach(1...12, id: \.self) { Text(months[$0 - 1].capitalized).tag($0) }
                        }
                    }
                }
                Section {
                    TextField("Web de la empresa (ej. netflix.com)", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Logo")
                } footer: {
                    Text("Para las empresas conocidas el logo sale solo. Si no aparece, escribe su web.")
                }
                Section("Categoría y color") {
                    Picker("Categoría", selection: $category) {
                        ForEach(Category.spending) { c in Label(c.name, systemImage: c.symbol).tag(c) }
                    }
                    Toggle("Color personalizado", isOn: $customColor)
                    if customColor { ColorPicker("Color", selection: $color, supportsOpacity: false) }
                }
                if let subscription {
                    Section {
                        Button("Eliminar pago fijo", role: .destructive) {
                            model.delete(subscription); dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(subscription == nil ? "Nuevo pago fijo" : "Editar pago")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(name.isEmpty || parsed == nil)
                }
            }
            .onAppear(perform: load)
            .onChange(of: name) { _, new in
                if subscription == nil {
                    let c = Categorizer.category(for: new, amount: -1)
                    if c != .otros && c != .transferencias { category = c }
                }
            }
        }
    }

    private var parsed: Double? { Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }

    private func load() {
        guard let s = subscription else { return }
        name = s.name
        amount = String(format: "%.2f", s.amount).replacingOccurrences(of: ".", with: ",")
        day = s.day; frequency = s.frequency; startMonth = s.startMonth; category = s.category
        if let hex = s.colorHex { customColor = true; color = Color(hex: hex) }
        domain = s.domain ?? ""
    }

    private func save() {
        guard let v = parsed else { return }
        var s = subscription ?? Subscription(name: name, amount: v, day: day)
        s.name = name; s.amount = v; s.day = day; s.frequency = frequency
        s.startMonth = startMonth; s.category = category
        s.colorHex = customColor ? color.hexString : nil
        s.domain = MerchantStyle.cleanDomain(domain)
        model.upsert(s)
        dismiss()
    }
}

extension Color {
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
