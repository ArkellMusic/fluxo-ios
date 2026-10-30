import Foundation
import SwiftUI

// MARK: - Categorías

enum Category: String, Codable, CaseIterable, Identifiable {
    case hogar, supermercado, restaurantes, cafe, combustible, transporte
    case suscripciones, telefonia, ocio, compras, salud, cuidado, deporte
    case transferencias, ingresos, otros

    var id: String { rawValue }

    var name: String {
        switch self {
        case .hogar: "Hogar"
        case .supermercado: "Supermercado"
        case .restaurantes: "Restaurantes"
        case .cafe: "Café y snacks"
        case .combustible: "Combustible"
        case .transporte: "Transporte"
        case .suscripciones: "Suscripciones"
        case .telefonia: "Teléfono e internet"
        case .ocio: "Ocio y viajes"
        case .compras: "Compras"
        case .salud: "Salud"
        case .cuidado: "Cuidado personal"
        case .deporte: "Deporte"
        case .transferencias: "Transferencias"
        case .ingresos: "Ingresos"
        case .otros: "Otros"
        }
    }

    var symbol: String {
        switch self {
        case .hogar: "house"
        case .supermercado: "basket"
        case .restaurantes: "fork.knife"
        case .cafe: "cup.and.saucer"
        case .combustible: "fuelpump"
        case .transporte: "car"
        case .suscripciones: "play.rectangle.on.rectangle"
        case .telefonia: "antenna.radiowaves.left.and.right"
        case .ocio: "theatermasks"
        case .compras: "bag"
        case .salud: "cross.case"
        case .cuidado: "heart"
        case .deporte: "figure.run"
        case .transferencias: "arrow.left.arrow.right"
        case .ingresos: "arrow.down.circle"
        case .otros: "square.grid.2x2"
        }
    }

    var color: Color {
        switch self {
        case .hogar: Color(hex: "2EE6F5")
        case .supermercado: Color(hex: "FF9A1F")
        case .restaurantes: Color(hex: "FF6B4A")
        case .cafe: Color(hex: "E8B04A")
        case .combustible: Color(hex: "F25CC9")
        case .transporte: Color(hex: "8C8CFF")
        case .suscripciones: Color(hex: "FFD000")
        case .telefonia: Color(hex: "4D8CFF")
        case .ocio: Color(hex: "B6E62E")
        case .compras: Color(hex: "C08CFF")
        case .salud: Color(hex: "3DDC97")
        case .cuidado: Color(hex: "FF7AA8")
        case .deporte: Color(hex: "35D0BA")
        case .transferencias: Color(hex: "9AA4AE")
        case .ingresos: Color(hex: "46D9A6")
        case .otros: Color(hex: "7D8A87")
        }
    }

    /// Categorías que cuentan como gasto en los informes.
    static var spending: [Category] { allCases.filter { $0 != .ingresos && $0 != .transferencias } }
}

// MARK: - Movimientos

enum TxSource: String, Codable { case bank, manual, demo }

struct Transaction: Codable, Identifiable, Hashable {
    var id: String
    var date: Date
    /// Negativo = gasto, positivo = ingreso.
    var amount: Double
    var merchant: String
    var category: Category
    var account: String
    var note: String?
    var source: TxSource

    var isExpense: Bool { amount < 0 }
}

// MARK: - Pagos fijos

enum Frequency: String, Codable, CaseIterable, Identifiable {
    case mensual, trimestral, anual
    var id: String { rawValue }
    var name: String {
        switch self {
        case .mensual: "Mensual"
        case .trimestral: "Trimestral"
        case .anual: "Anual"
        }
    }
    var months: Int {
        switch self {
        case .mensual: 1
        case .trimestral: 3
        case .anual: 12
        }
    }
}

struct Subscription: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var amount: Double
    var day: Int
    var frequency: Frequency = .mensual
    /// Mes del primer cobro (1-12); sirve para trimestral y anual.
    var startMonth: Int = 1
    var category: Category = .suscripciones
    var colorHex: String? = nil

    var color: Color { colorHex.map { Color(hex: $0) } ?? MerchantStyle.color(for: name) }

    func occurs(inMonth month: Int) -> Bool {
        let diff = ((month - startMonth) % 12 + 12) % 12
        return diff % frequency.months == 0
    }
}

/// Un cobro concreto de un pago fijo en una fecha.
struct Occurrence: Identifiable, Hashable {
    var subscription: Subscription
    var date: Date
    var id: String { subscription.id.uuidString + "-" + String(Int(date.timeIntervalSince1970)) }
}

// MARK: - Banco

struct BankAccount: Codable, Hashable, Identifiable {
    var uid: String
    var name: String
    var iban: String?
    var balance: Double?
    var id: String { uid }
}

struct BankLink: Codable, Hashable {
    var aspspName: String
    var aspspCountry: String
    var sessionId: String
    var validUntil: Date
    var accounts: [BankAccount]
}

// MARK: - Datos guardados

struct AppData: Codable {
    var transactions: [Transaction] = []
    var subscriptions: [Subscription] = []
    var bank: BankLink? = nil
    var lastSync: Date? = nil
    var demo: Bool = false
}
