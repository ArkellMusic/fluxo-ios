import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportStatementView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var initialFiles: [URL] = []

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
                        Text("Vale el PDF del extracto mensual, CSV o Excel (.xlsx). Puedes elegir varios meses a la vez.")
                    }
                    Section("Desde la app de ING (en el móvil)") {
                        Label("Abre la app de ING › tu cuenta › Extractos (o Documentos).", systemImage: "1.circle")
                        Label("Abre el extracto mensual en PDF.", systemImage: "2.circle")
                        Label("Pulsa Compartir y elige Fluxo. Se importa directamente.", systemImage: "3.circle")
                        Label("Si Fluxo no sale en Compartir: «Guardar en Archivos» y luego impórtalo aquí.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(Theme.negative).font(.footnote)
                        if !PDFStatement.lastDiagnostic.isEmpty {
                            DisclosureGroup("Detalles técnicos") {
                                Text(PDFStatement.lastDiagnostic)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                Button("Copiar detalles") { UIPasteboard.general.string = PDFStatement.lastDiagnostic }
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Importar extracto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
                switch r {
                case .success(let urls): load(urls)
                case .failure(let e): error = e.localizedDescription
                }
            }
            .onAppear { if result == nil, !initialFiles.isEmpty { load(initialFiles) } }
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

    private func load(_ urls: [URL]) {
        UserDefaults.standard.set(account, forKey: "import.account")
        var all: [Transaction] = []
        var skipped = 0
        var cols: [String] = []
        var errors: [String] = []
        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            var data: Data?
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { u in
                data = try? Data(contentsOf: u)
            }
            guard let data else { errors.append("\(url.lastPathComponent): no se pudo leer"); continue }
            do {
                let r = try StatementImporter.parse(data: data, fileName: url.lastPathComponent,
                                                    account: account.isEmpty ? "Cuenta" : account)
                all += r.transactions
                skipped += r.skipped
                cols.append(r.columns)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        fileName = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) archivos"
        error = errors.isEmpty ? nil : errors.joined(separator: "\n")
        result = all.isEmpty ? nil : StatementImporter.Result(transactions: all, skipped: skipped,
                                                               columns: Array(Set(cols)).sorted().joined(separator: " | "))
    }
}
