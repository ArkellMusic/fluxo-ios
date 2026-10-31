import SwiftUI
import UniformTypeIdentifiers

struct ImportStatementView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    @State private var picking = false
    @State private var account = UserDefaults.standard.string(forKey: "import.account") ?? "ING"
    @State private var result: StatementImporter.Result? = nil
    @State private var fileName = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    preview(result)
                } else {
                    Section {
                        TextField("Nombre de la cuenta", text: $account)
                        Button { picking = true } label: {
                            Label("Elegir archivo del extracto", systemImage: "doc.badge.plus")
                        }
                    } footer: {
                        Text("Vale CSV o Excel (.xlsx) de cualquier banco. Fluxo busca solo las columnas de fecha, concepto e importe.")
                    }
                    Section("Cómo sacarlo de ING") {
                        Label("Entra en ing.es desde el navegador (mejor en ordenador).", systemImage: "1.circle")
                        Label("Abre tu cuenta › Movimientos y elige las fechas.", systemImage: "2.circle")
                        Label("Pulsa el icono de descargar › Excel.", systemImage: "3.circle")
                        Label("Pásalo al iPhone (AirDrop, iCloud Drive o correo) e impórtalo aquí.", systemImage: "4.circle")
                        Label("Si sale un aviso de Excel antiguo (.xls): ábrelo en Numbers › Compartir › Exportar › Excel o CSV.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.negative).font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Importar extracto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { r in
                switch r {
                case .success(let url): load(url)
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private func preview(_ r: StatementImporter.Result) -> some View {
        let txs = r.transactions.sorted { $0.date > $1.date }
        let spent = txs.filter(\.isExpense).reduce(0) { $0 - $1.amount }
        let income = txs.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
        return Group {
            Section {
                LabeledContent("Archivo", value: fileName)
                LabeledContent("Movimientos", value: "\(txs.count)")
                if let first = txs.last?.date, let last = txs.first?.date {
                    LabeledContent("Fechas", value: "\(Fmt.shortDate(first)) – \(Fmt.shortDate(last))")
                }
                LabeledContent("Gastos", value: Fmt.money(spent))
                LabeledContent("Ingresos", value: Fmt.money(income))
                if r.skipped > 0 { LabeledContent("Filas ignoradas", value: "\(r.skipped)") }
            } header: {
                Text("Resumen")
            } footer: {
                Text("Columnas detectadas: \(r.columns)")
            }
            Section("Vista previa") {
                ForEach(txs.prefix(6)) { t in TransactionRow(t: t) }
            }
            Section {
                Button {
                    let (added, dup) = model.importTransactions(r.transactions)
                    model.message = "Importados \(added) movimientos" + (dup > 0 ? " (\(dup) ya estaban)" : "")
                    dismiss()
                } label: {
                    Label("Importar \(txs.count) movimientos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .listRowBackground(Color.clear)
                Button("Elegir otro archivo") { result = nil; picking = true }
            }
        }
    }

    private func load(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { u in
            data = try? Data(contentsOf: u)
        }
        guard let data else { error = "No se pudo leer el archivo."; return }
        UserDefaults.standard.set(account, forKey: "import.account")
        do {
            fileName = url.lastPathComponent
            result = try StatementImporter.parse(data: data, fileName: url.lastPathComponent,
                                                 account: account.isEmpty ? "Cuenta" : account)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
