import Foundation
import Security
import AuthenticationServices
import UIKit

// MARK: - Credenciales (Keychain)

enum BankKeys {
    private static let service = "com.arkellmusic.fluxo.enablebanking"

    static var appId: String? {
        get { UserDefaults.standard.string(forKey: "eb.appId") }
        set { UserDefaults.standard.set(newValue, forKey: "eb.appId") }
    }

    static var redirectURL: String {
        get { UserDefaults.standard.string(forKey: "eb.redirect") ?? "https://arkellmusic.github.io/fluxo-ios/callback.html" }
        set { UserDefaults.standard.set(newValue, forKey: "eb.redirect") }
    }

    static var privateKeyPEM: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "pem",
                                    kSecReturnData as String: true]
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: service,
                                       kSecAttrAccount as String: "pem"]
            SecItemDelete(base as CFDictionary)
            guard let v = newValue, let d = v.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = d
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static var isConfigured: Bool { !(appId ?? "").isEmpty && privateKeyPEM != nil }

    static func clear() {
        appId = nil
        privateKeyPEM = nil
    }
}

// MARK: - Errores

enum BankError: LocalizedError {
    case notConfigured, badKey(String), http(Int, String), noCode, cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Falta el Application ID o la clave privada de Enable Banking."
        case .badKey(let m): "Clave privada no válida: \(m)"
        case .http(let code, let body): "El servidor respondió \(code): \(body.prefix(200))"
        case .noCode: "El banco no devolvió el código de autorización."
        case .cancelled: "Conexión cancelada."
        }
    }
}

// MARK: - Cliente de la API

struct ASPSP: Decodable, Identifiable, Hashable {
    var name: String
    var country: String
    var logo: String?
    var id: String { name + country }
}

enum EnableBanking {
    static let base = URL(string: "https://api.enablebanking.com")!

    // JWT RS256 firmado en el propio iPhone
    static func jwt() throws -> String {
        guard let appId = BankKeys.appId, !appId.isEmpty, let pem = BankKeys.privateKeyPEM else { throw BankError.notConfigured }
        let key = try PEM.rsaPrivateKey(pem)
        let now = Int(Date().timeIntervalSince1970)
        let header = ["typ": "JWT", "alg": "RS256", "kid": appId]
        let payload: [String: Any] = ["iss": "enablebanking.com", "aud": "api.enablebanking.com", "iat": now, "exp": now + 3600]
        let h = try JSONSerialization.data(withJSONObject: header).base64URL
        let p = try JSONSerialization.data(withJSONObject: payload).base64URL
        let input = "\(h).\(p)"
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(input.utf8) as CFData, &err) as Data? else {
            throw BankError.badKey(err?.takeRetainedValue().localizedDescription ?? "no se pudo firmar")
        }
        return "\(input).\(sig.base64URL)"
    }

    static func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(try jwt())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw BankError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    static func banks(country: String = "ES") async throws -> [ASPSP] {
        struct R: Decodable { var aspsps: [ASPSP] }
        let d = try await request("aspsps", query: [URLQueryItem(name: "country", value: country), URLQueryItem(name: "psu_type", value: "personal")])
        return try JSONDecoder().decode(R.self, from: d).aspsps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Devuelve la URL donde el usuario inicia sesión en su banco.
    static func startAuth(bank: ASPSP, state: String) async throws -> URL {
        struct R: Decodable { var url: String }
        let validUntil = ISO8601DateFormatter().string(from: Date().addingTimeInterval(89 * 24 * 3600))
        let body: [String: Any] = [
            "access": ["valid_until": validUntil],
            "aspsp": ["name": bank.name, "country": bank.country],
            "state": state,
            "redirect_url": BankKeys.redirectURL,
            "psu_type": "personal",
        ]
        let d = try await request("auth", method: "POST", body: body)
        guard let url = URL(string: try JSONDecoder().decode(R.self, from: d).url) else { throw BankError.noCode }
        return url
    }

    static func createSession(code: String, bank: ASPSP) async throws -> BankLink {
        struct Acc: Decodable {
            struct AID: Decodable { var iban: String? }
            var uid: String
            var name: String?
            var product: String?
            var account_id: AID?
        }
        struct Access: Decodable { var valid_until: String? }
        struct R: Decodable { var session_id: String; var accounts: [Acc]; var access: Access? }
        let d = try await request("sessions", method: "POST", body: ["code": code])
        let r = try JSONDecoder().decode(R.self, from: d)
        let until = r.access?.valid_until.flatMap { ISO8601DateFormatter.flexible.date(from: $0) } ?? Date().addingTimeInterval(89 * 86400)
        let accounts = r.accounts.map {
            BankAccount(uid: $0.uid, name: $0.name ?? $0.product ?? "Cuenta", iban: $0.account_id?.iban)
        }
        return BankLink(aspspName: bank.name, aspspCountry: bank.country, sessionId: r.session_id, validUntil: until, accounts: accounts)
    }

    static func balance(account: BankAccount) async throws -> Double? {
        struct Amt: Decodable { var amount: String }
        struct B: Decodable { var balance_amount: Amt; var balance_type: String? }
        struct R: Decodable { var balances: [B] }
        let d = try await request("accounts/\(account.uid)/balances")
        let r = try JSONDecoder().decode(R.self, from: d)
        let pick = r.balances.first { ["CLBD", "ITAV", "XPCD", "ITBD"].contains($0.balance_type ?? "") } ?? r.balances.first
        return pick.flatMap { Double($0.balance_amount.amount) }
    }

    static func transactions(account: BankAccount, from: Date) async throws -> [Transaction] {
        struct Amt: Decodable { var amount: String; var currency: String? }
        struct Party: Decodable { var name: String? }
        struct T: Decodable {
            var entry_reference: String?
            var transaction_id: String?
            var transaction_amount: Amt
            var credit_debit_indicator: String?
            var booking_date: String?
            var value_date: String?
            var transaction_date: String?
            var creditor: Party?
            var debtor: Party?
            var remittance_information: [String]?
        }
        struct R: Decodable { var transactions: [T]; var continuation_key: String? }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        var out: [Transaction] = []
        var cont: String? = nil
        var pages = 0
        repeat {
            var q = [URLQueryItem(name: "date_from", value: df.string(from: from))]
            if let cont { q.append(URLQueryItem(name: "continuation_key", value: cont)) }
            let d = try await request("accounts/\(account.uid)/transactions", query: q)
            let r = try JSONDecoder().decode(R.self, from: d)
            for t in r.transactions {
                let raw = abs(Double(t.transaction_amount.amount) ?? 0)
                let isDebit = (t.credit_debit_indicator ?? "DBIT") == "DBIT"
                let amount = isDebit ? -raw : raw
                let counterpart = isDebit ? t.creditor?.name : t.debtor?.name
                let info = t.remittance_information?.joined(separator: " ") ?? ""
                let merchant = clean(counterpart ?? (info.isEmpty ? "Movimiento" : info))
                let dateStr = t.booking_date ?? t.value_date ?? t.transaction_date ?? df.string(from: .now)
                let date = df.date(from: String(dateStr.prefix(10))) ?? .now
                let id = "eb-" + (t.entry_reference ?? t.transaction_id ?? "\(account.uid)-\(dateStr)-\(t.transaction_amount.amount)-\(merchant)")
                out.append(Transaction(id: id, date: date, amount: amount, merchant: merchant,
                                       category: Categorizer.category(for: merchant + " " + info, amount: amount),
                                       account: account.name, note: info.isEmpty ? nil : info, source: .bank))
            }
            cont = (r.continuation_key?.isEmpty == false) ? r.continuation_key : nil
            pages += 1
        } while cont != nil && pages < 20
        return out
    }

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "COMPRA EN ", with: "", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "PAGO EN ", with: "", options: .caseInsensitive)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t == t.uppercased(), t.count > 3 { t = t.capitalized }
        return String(t.prefix(40))
    }
}

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Inicio de sesión en el banco

@MainActor
final class BankAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = BankAuthFlow()
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }

    /// Abre el login del banco y devuelve el `code` cuando vuelve a fluxo://callback
    func authorize(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "fluxo") { callback, error in
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    cont.resume(throwing: cancelled ? BankError.cancelled : error)
                    return
                }
                guard let callback, let code = Self.code(from: callback) else {
                    cont.resume(throwing: BankError.noCode)
                    return
                }
                cont.resume(returning: code)
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            s.start()
        }
    }

    static func code(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code" }?.value
    }
}

// MARK: - Utilidades criptográficas

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum PEM {
    static func rsaPrivateKey(_ pem: String) throws -> SecKey {
        let isPKCS8 = pem.contains("BEGIN PRIVATE KEY")
        let b64 = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        guard var der = Data(base64Encoded: b64) else { throw BankError.badKey("el texto no es un PEM válido") }
        if isPKCS8 { der = try pkcs1(fromPKCS8: der) }
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                    kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &err) else {
            throw BankError.badKey(err?.takeRetainedValue().localizedDescription ?? "formato no soportado")
        }
        return key
    }

    /// PKCS#8: SEQUENCE { INTEGER, SEQUENCE {OID, NULL}, OCTET STRING { PKCS#1 } }
    static func pkcs1(fromPKCS8 der: Data) throws -> Data {
        let bytes = [UInt8](der)
        var i = 0
        func readLen() throws -> Int {
            guard i < bytes.count else { throw BankError.badKey("DER truncado") }
            var len = Int(bytes[i]); i += 1
            if len & 0x80 != 0 {
                let n = len & 0x7F
                len = 0
                for _ in 0..<n {
                    guard i < bytes.count else { throw BankError.badKey("DER truncado") }
                    len = (len << 8) | Int(bytes[i]); i += 1
                }
            }
            return len
        }
        func expect(_ tag: UInt8) throws {
            guard i < bytes.count, bytes[i] == tag else { throw BankError.badKey("estructura PKCS#8 inesperada") }
            i += 1
        }
        try expect(0x30); _ = try readLen()            // SEQUENCE
        try expect(0x02); i += try readLen()            // INTEGER version
        try expect(0x30); i += try readLen()            // AlgorithmIdentifier
        try expect(0x04); let len = try readLen()       // OCTET STRING
        guard i + len <= bytes.count else { throw BankError.badKey("DER truncado") }
        return Data(bytes[i..<(i + len)])
    }
}
