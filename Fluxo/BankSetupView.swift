import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Guarda el banco elegido por si el login vuelve a la app por fluxo:// en vez de por la ventana.
@MainActor
final class PendingBank {
    static let shared = PendingBank()
    var bank: ASPSP?

    func receive(code: String, model: AppModel) {
        guard let bank else { return }
        self.bank = nil
        Task {
            do {
                model.data.bank = try await EnableBanking.createSession(code: code, bank: bank)
                model.persist()
                await model.sync()
            } catch {
                model.message = error.localizedDescription
            }
        }
    }
}

struct BankSetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    @State private var appId = BankKeys.appId ?? ""
    @State private var redirect = BankKeys.redirectURL
    @State private var hasKey = BankKeys.privateKeyPEM != nil
    @State private var importing = false
    @State private var pasting = false
    @State private var banks: [ASPSP] = []
    @State private var search = ""
    @State private var loading = false
    @State private var connecting: ASPSP? = nil
    @State private var error: String? = nil

    var body: some View {
        Form {
            Section {
                TextField("Application ID", text: $appId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .onChange(of: appId) { _, v in BankKeys.appId = v.trimmingCharacters(in: .whitespacesAndNewlines) }
                HStack {
                    Label(hasKey ? "Clave privada guardada" : "Sin clave privada",
                          systemImage: hasKey ? "key.fill" : "key")
                        .foregroundStyle(hasKey ? Theme.accent : .secondary)
                    Spacer()
                }
                Button { importing = true } label: { Label("Importar archivo .pem", systemImage: "doc.badge.plus") }
                Button { pasting = true } label: { Label("Pegar clave como texto", systemImage: "doc.on.clipboard") }
            } header: {
                Text("1 · Credenciales de Enable Banking")
            } footer: {
                Text("Las encuentras en enablebanking.com › Aplicaciones API. La clave se guarda cifrada en el llavero del iPhone.")
            }

            Section {
                TextField("URL de redirección", text: $redirect)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote.monospaced())
                    .onChange(of: redirect) { _, v in BankKeys.redirectURL = v.trimmingCharacters(in: .whitespaces) }
            } header: {
                Text("2 · Redirección")
            } footer: {
                Text("Debe ser exactamente la misma que registraste en Enable Banking.")
            }

            Section {
                if banks.isEmpty {
                    Button {
                        Task { await loadBanks() }
                    } label: {
                        HStack {
                            Label("Ver bancos de España", systemImage: "building.columns")
                            Spacer()
                            if loading { ProgressView() }
                        }
                    }
                    .disabled(!hasKey || appId.isEmpty || loading)
                } else {
                    TextField("Buscar banco (ING…)", text: $search)
                    ForEach(filteredBanks) { b in
                        Button {
                            Task { await connect(b) }
                        } label: {
                            HStack {
                                MerchantBubble(name: b.name, size: 30)
                                Text(b.name).foregroundStyle(.primary)
                                Spacer()
                                if connecting == b { ProgressView() } else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                            }
                        }
                        .disabled(connecting != nil)
                    }
                }
            } header: {
                Text("3 · Elige tu banco")
            } footer: {
                Text("Se abrirá la web de tu banco para que des permiso de solo lectura. Dura unos 90 días; después solo hay que reconectar.")
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.negative) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Conectar banco")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): importKey(from: url)
            case .failure(let e): error = e.localizedDescription
            }
        }
        .sheet(isPresented: $pasting) {
            PasteKeySheet { text in storeKey(text) }
        }
    }

    private func importKey(from url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        var readError: NSError?
        var content: Data?
        // Coordinado: descarga el archivo de iCloud Drive si hace falta
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &readError) { u in
            content = try? Data(contentsOf: u)
        }
        guard let data = content, !data.isEmpty else {
            error = "No se pudo leer el archivo" + (readError.map { ": \($0.localizedDescription)" } ?? ".")
            model.message = error
            return
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? String(decoding: data, as: UTF8.self)
        storeKey(text)
    }

    private var filteredBanks: [ASPSP] {
        search.isEmpty ? banks : banks.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func storeKey(_ text: String) {
        do {
            _ = try PEM.rsaPrivateKey(text)
            BankKeys.privateKeyPEM = text
            hasKey = true
            error = nil
            model.message = "Clave privada guardada ✅"
        } catch {
            self.error = error.localizedDescription
            model.message = error.localizedDescription
        }
    }

    private func loadBanks() async {
        loading = true
        defer { loading = false }
        do {
            banks = try await EnableBanking.banks()
            error = nil
            if let ing = banks.first(where: { $0.name.localizedCaseInsensitiveContains("ING") }) {
                search = ing.name.contains("ING") ? "ING" : ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func connect(_ bank: ASPSP) async {
        connecting = bank
        defer { connecting = nil }
        do {
            let state = UUID().uuidString
            PendingBank.shared.bank = bank
            let url = try await EnableBanking.startAuth(bank: bank, state: state)
            let code = try await BankAuthFlow.shared.authorize(url: url)
            PendingBank.shared.bank = nil
            model.data.bank = try await EnableBanking.createSession(code: code, bank: bank)
            model.persist()
            await model.sync()
            dismiss()
        } catch BankError.cancelled {
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PasteKeySheet: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (String) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Abre el archivo .pem, copia TODO su contenido (desde -----BEGIN hasta -----END) y pégalo aquí.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    text = UIPasteboard.general.string ?? ""
                } label: {
                    Label("Pegar del portapapeles", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                TextEditor(text: $text)
                    .font(.caption.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(16)
            .background(Theme.background)
            .navigationTitle("Pegar clave privada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { onSave(text); dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
