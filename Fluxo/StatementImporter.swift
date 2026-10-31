import Foundation
import Compression
import PDFKit

/// Lee extractos bancarios (CSV, Excel .xlsx o tablas HTML guardadas como .xls) y los convierte en movimientos.
enum StatementImporter {

    struct Result {
        var transactions: [Transaction]
        var skipped: Int
        var columns: String
    }

    enum ImportError: LocalizedError {
        case unreadable, legacyXLS, noHeader, empty, pdfNoMovements
        var errorDescription: String? {
            switch self {
            case .unreadable: "No he podido leer el archivo."
            case .legacyXLS: "Es un Excel antiguo (.xls). Ábrelo en Numbers y expórtalo como Excel (.xlsx) o CSV, y vuelve a importarlo."
            case .noHeader: "No encuentro las columnas de fecha e importe. ¿Es un extracto de movimientos?"
            case .empty: "El archivo no tiene movimientos."
            case .pdfNoMovements: "No encuentro movimientos en este PDF. ¿Es el extracto mensual o la lista de movimientos de tu cuenta?"
            }
        }
    }

    // MARK: Entrada

    static func parse(data: Data, fileName: String, account: String) throws -> Result {
        if data.starts(with: Array("%PDF".utf8)) || fileName.lowercased().hasSuffix(".pdf") {
            return try PDFStatement.parse(data, defaultAccount: account)
        }
        let rows = try table(from: data, fileName: fileName)
        return try convert(rows: rows, account: account)
    }

    static func table(from data: Data, fileName: String) throws -> [[String]] {
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return try XLSX.rows(from: data) }
        if bytes.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) { throw ImportError.legacyXLS }
        guard let text = decodeText(data) else { throw ImportError.unreadable }
        let lower = text.prefix(2000).lowercased()
        if lower.contains("<table") || lower.contains("<tr") { return HTMLTable.rows(from: text) }
        return CSV.rows(from: text)
    }

    static func decodeText(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: Detección de columnas

    private static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func find(_ header: [String], _ keys: [String], excluding: [String] = []) -> Int? {
        for key in keys {
            if let i = header.firstIndex(where: { h in h.contains(key) && !excluding.contains(where: { h.contains($0) }) }) { return i }
        }
        return nil
    }

    static func convert(rows: [[String]], account: String) throws -> Result {
        // La cabecera puede no estar en la primera fila (ING pone antes el titular y la cuenta)
        var headerIndex: Int?
        var map: (date: Int, desc: Int?, amount: Int?, debit: Int?, credit: Int?, category: Int?) = (0, nil, nil, nil, nil, nil)
        for (i, row) in rows.prefix(30).enumerated() {
            let h = row.map(norm)
            guard let d = find(h, ["f. valor", "fecha valor", "f. operacion", "fecha operacion", "fecha", "f.valor", "date"]) else { continue }
            let amount = find(h, ["importe", "cantidad", "amount", "monto"], excluding: ["saldo"])
            let debit = find(h, ["cargo", "debe", "debit"])
            let credit = find(h, ["abono", "haber", "credit"])
            guard amount != nil || (debit != nil && credit != nil) else { continue }
            let desc = find(h, ["descripcion", "concepto", "movimiento", "detalle", "comercio", "description", "beneficiario"])
            let cat = find(h, ["subcategoria", "categoria"])
            headerIndex = i
            map = (d, desc, amount, debit, credit, cat)
            break
        }
        guard let headerIndex else { throw ImportError.noHeader }

        var out: [Transaction] = []
        var skipped = 0
        var seen: [String: Int] = [:]
        for row in rows.dropFirst(headerIndex + 1) {
            func cell(_ i: Int?) -> String { guard let i, i < row.count else { return "" }; return row[i] }
            guard let date = parseDate(cell(map.date)) else { skipped += 1; continue }
            var amount: Double?
            if map.amount != nil {
                amount = parseAmount(cell(map.amount))
            } else {
                let deb = parseAmount(cell(map.debit)) ?? 0
                let cre = parseAmount(cell(map.credit)) ?? 0
                if deb != 0 || cre != 0 { amount = cre - abs(deb) }
            }
            guard let amount, amount != 0 else { skipped += 1; continue }
            var desc = cell(map.desc).trimmingCharacters(in: .whitespacesAndNewlines)
            if desc.isEmpty { desc = "Movimiento" }
            let merchant = cleanMerchant(desc)
            let bankCat = cell(map.category)
            let category = Categorizer.category(for: merchant + " " + desc + " " + bankCat, amount: amount)

            // Identificador estable: si reimportas el mismo extracto no se duplica
            let base = "\(Int(date.timeIntervalSince1970))|\(String(format: "%.2f", amount))|\(norm(desc))"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            let id = "imp-" + stableHash(base + "|\(n)")

            out.append(Transaction(id: id, date: date, amount: amount, merchant: merchant, category: category,
                                   account: account, note: desc == merchant ? nil : desc, source: .bank))
        }
        guard !out.isEmpty else { throw ImportError.empty }
        let names = rows[headerIndex].enumerated()
            .filter { [map.date, map.desc, map.amount, map.debit, map.credit].contains($0.offset) }
            .map { $0.element.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " · ")
        return Result(transactions: out, skipped: skipped, columns: names)
    }

    // MARK: Utilidades

    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Fecha numérica de Excel (días desde 1899-12-30)
        if let serial = Double(s), serial > 20000, serial < 80000 {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = .current
            let base = c.date(from: DateComponents(year: 1899, month: 12, day: 30))!
            return c.date(byAdding: .day, value: Int(serial), to: base)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = .current
        for fmt in ["dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "yyyy-MM-dd", "dd/MM/yy", "d/M/yy", "dd.MM.yyyy", "yyyy/MM/dd", "dd/MM/yyyy HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = fmt
            if let d = f.date(from: String(s.prefix(fmt.count + 2)).trimmingCharacters(in: .whitespaces)) ?? f.date(from: s) {
                let year = Calendar.current.component(.year, from: d)
                if year > 1990 && year < 2100 { return d }
            }
        }
        return nil
    }

    static func parseAmount(_ raw: String) -> Double? {
        var s = raw.replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "EUR", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasSuffix("-") { negative = true; s.removeLast() }
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        if let c = lastComma, let d = lastDot {
            if c > d { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { s = s.replacingOccurrences(of: ",", with: "") }
        } else if lastComma != nil {
            s = s.replacingOccurrences(of: ",", with: ".")
        } else if lastDot != nil {
            // Solo puntos: "1.234" o "1.234.567" son miles (formato español); "12.50" es decimal
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 2 || (parts.count == 2 && parts[1].count == 3) {
                s = s.replacingOccurrences(of: ".", with: "")
            }
        }
        guard let v = Double(s) else { return nil }
        return negative ? -abs(v) : v
    }

    static func cleanMerchant(_ desc: String) -> String {
        var t = desc
        if let r = t.range(of: #"\*{2,}\d{3,4}"#, options: .regularExpression) { t.removeSubrange(r) }
        let prefixes = ["pago en ", "compra en ", "compra tarjeta ", "pago con tarjeta en ", "transaccion contactless en ",
                        "recibo ", "adeudo ", "cargo ", "transferencia a favor de ", "transferencia de ", "bizum a ", "bizum de ",
                        "pago movil en ", "apple pay ", "google pay ", "pago "]
        let lower = norm(t)
        for p in prefixes where lower.hasPrefix(p) { t = String(t.dropFirst(p.count)); break }
        if let r = t.range(of: ", tarj", options: .caseInsensitive) { t = String(t[..<r.lowerBound]) }
        t = t.trimmingCharacters(in: .whitespaces)
        for suffix in [" ES", " IE", " NL", " LU", " GB", " DE", " FR"] where t.hasSuffix(suffix) { t = String(t.dropLast(suffix.count)) }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.-")))
        if t == t.uppercased(), t.count > 3 { t = t.capitalized }
        return String(t.prefix(40))
    }

    static func stableHash(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }
}

// MARK: - CSV

enum CSV {
    static func rows(from text: String) -> [[String]] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let sample = lines.split(separator: "\n").prefix(15).joined(separator: "\n")
        let delim: Character = [";", "\t", ","].max { a, b in
            sample.filter { $0 == a }.count < sample.filter { $0 == b }.count
        } ?? ";"
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var it = Array(lines)
        if it.first == "\u{FEFF}" { it.removeFirst() }
        var i = 0
        while i < it.count {
            let ch = it[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < it.count && it[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(ch) }
            } else if ch == "\"" {
                quoted = true
            } else if ch == delim {
                row.append(field); field = ""
            } else if ch == "\n" {
                row.append(field); field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(ch)
            }
            i += 1
        }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
        return rows
    }
}

// MARK: - Tabla HTML (algunos bancos guardan así sus ".xls")

enum HTMLTable {
    static func rows(from html: String) -> [[String]] {
        var rows: [[String]] = []
        let rowRegex = try! NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let cellRegex = try! NSRegularExpression(pattern: "<t[dh][^>]*>(.*?)</t[dh]>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let tagRegex = try! NSRegularExpression(pattern: "<[^>]+>")
        let ns = html as NSString
        for m in rowRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            let ins = inner as NSString
            let cells = cellRegex.matches(in: inner, range: NSRange(location: 0, length: ins.length)).map { c -> String in
                let raw = ins.substring(with: c.range(at: 1))
                let stripped = tagRegex.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "")
                return stripped.replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }
}

// MARK: - Excel .xlsx (zip + XML)

enum XLSX {
    static func rows(from data: Data) throws -> [[String]] {
        let files = try Zip.entries(data)
        let shared = files["xl/sharedStrings.xml"].map(SharedStringsParser.parse) ?? []
        let sheetName = files.keys.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted().first
        guard let sheetName, let sheet = files[sheetName] else { throw StatementImporter.ImportError.unreadable }
        return SheetParser.parse(sheet, shared: shared)
    }

    final class SharedStringsParser: NSObject, XMLParserDelegate {
        var items: [String] = []
        var current = ""
        var inSI = false, inT = false

        static func parse(_ data: Data) -> [String] {
            let p = SharedStringsParser()
            let x = XMLParser(data: data)
            x.delegate = p
            x.parse()
            return p.items
        }
        func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if e == "si" { inSI = true; current = "" }
            if e == "t" { inT = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inSI && inT { current += string } }
        func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "t" { inT = false }
            if e == "si" { inSI = false; items.append(current) }
        }
    }

    final class SheetParser: NSObject, XMLParserDelegate {
        var shared: [String] = []
        var rows: [[String]] = []
        var row: [Int: String] = [:]
        var col = 0
        var type = ""
        var value = ""
        var capture = false

        static func parse(_ data: Data, shared: [String]) -> [[String]] {
            let p = SheetParser()
            p.shared = shared
            let x = XMLParser(data: data)
            x.delegate = p
            x.parse()
            return p.rows
        }

        static func column(_ ref: String) -> Int {
            var n = 0
            for ch in ref.uppercased() {
                guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
                n = n * 26 + Int(a - 64)
            }
            return max(0, n - 1)
        }

        func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch e {
            case "row": row = [:]; col = 0
            case "c":
                col = attributes["r"].map(Self.column) ?? col
                type = attributes["t"] ?? ""
                value = ""
            case "v", "t": capture = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if capture { value += string } }
        func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            switch e {
            case "v", "t": capture = false
            case "c":
                var v = value
                if type == "s", let i = Int(value), i < shared.count { v = shared[i] }
                row[col] = v
                col += 1
            case "row":
                guard let maxCol = row.keys.max() else { return }
                let arr = (0...maxCol).map { row[$0] ?? "" }
                if arr.contains(where: { !$0.isEmpty }) { rows.append(arr) }
            default: break
            }
        }
    }
}

/// Lector zip mínimo (stored + deflate) usando el framework Compression.
enum Zip {
    static func entries(_ data: Data) throws -> [String: Data] {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 3 < b.count ? u16(o) | u16(o + 2) << 16 : 0 }

        // Fin del directorio central
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 66000) {
            if b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 0x05 && b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw StatementImporter.ImportError.unreadable }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [String: Data] = [:]
        for _ in 0..<count {
            guard u32(p) == 0x02014B50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            let name = String(decoding: b[(p + 46)..<min(b.count, p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + elen + clen

            guard name.hasPrefix("xl/sharedStrings") || name.hasPrefix("xl/worksheets/sheet") else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { continue }
            let comp = Array(b[start..<(start + csize)])
            if method == 0 {
                out[name] = Data(comp)
            } else if method == 8 {
                var dst = [UInt8](repeating: 0, count: max(usize, 1))
                let n = compression_decode_buffer(&dst, dst.count, comp, comp.count, nil, COMPRESSION_ZLIB)
                if n > 0 { out[name] = Data(dst.prefix(n)) }
            }
        }
        return out
    }
}


// MARK: - PDF (extracto mensual de ING y similares)

enum PDFStatement {
    static func parse(_ data: Data, defaultAccount: String) throws -> StatementImporter.Result {
        let strategies = PDFLines.all(data)
        guard !strategies.isEmpty else { throw StatementImporter.ImportError.unreadable }
        var best: StatementImporter.Result?
        var report: [String] = []
        for st in strategies {
            let r = parse(lines: st.lines, defaultAccount: defaultAccount)
            report.append("\(st.name): \(st.lines.count) líneas, \(r.transactions.count) movs")
            if r.transactions.count > (best?.transactions.count ?? 0) { best = r }
        }
        lastDiagnostic = report.joined(separator: "\n") + "\n\n" + strategies.map { st in
            "— \(st.name) —\n" + st.lines.filter { $0.range(of: #"\d{2}/\d{2}"#, options: .regularExpression) != nil }.prefix(6).joined(separator: "\n")
        }.joined(separator: "\n")
        guard let best, !best.transactions.isEmpty else { throw StatementImporter.ImportError.pdfNoMovements }
        return best
    }

    /// Texto de diagnóstico del último PDF leído (para poder revisar fallos).
    static var lastDiagnostic = ""

    static func parse(lines: [String], defaultAccount: String) -> StatementImporter.Result {
        let all = lines.joined(separator: "\n")

        // Fin del periodo: la fecha completa más reciente del extracto
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES"); df.dateFormat = "dd/MM/yyyy"
        let fullDates = matches(#"\b(\d{2}/\d{2}/\d{4})\b"#, in: all).compactMap { df.date(from: $0[1]) }
        let end = fullDates.max() ?? Date()
        let cal = Calendar(identifier: .gregorian)
        let endYear = cal.component(.year, from: end)
        let endMonth = cal.component(.month, from: end)

        let txRegex = try! NSRegularExpression(pattern: #"(\d{2}/\d{2}(?:/\d{2,4})?)\s+(?:\d{2}/\d{2}(?:/\d{2,4})?\s+)?(.+?)\s+([-−–]?\s?[\d.]+,\d{2})\s?€?\s+([-−–]?\s?[\d.]+,\d{2})\s?€?"#)
        let accRegex = try! NSRegularExpression(pattern: #"(Cuenta\s+.+?)\s+-\s+IBAN"#, options: .caseInsensitive)

        var account = defaultAccount
        var out: [Transaction] = []
        var seen: [String: Int] = [:]
        var skipped = 0
        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let a = accRegex.firstMatch(in: line, range: range) {
                account = ns.substring(with: a.range(at: 1)).capitalized
                continue
            }
            guard let m = txRegex.firstMatch(in: line, range: range) else { continue }
            let dateStr = ns.substring(with: m.range(at: 1))
            let desc = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let amountStr = ns.substring(with: m.range(at: 3))
            if desc.lowercased().hasPrefix("saldo") { continue }
            guard let amount = StatementImporter.parseAmount(amountStr), amount != 0 else { skipped += 1; continue }

            let parts = dateStr.split(separator: "/").compactMap { Int($0) }
            guard parts.count >= 2 else { skipped += 1; continue }
            var year = endYear
            if parts.count == 3 { year = parts[2] < 100 ? 2000 + parts[2] : parts[2] }
            else if parts[1] > endMonth + 1 { year -= 1 }   // diciembre en un extracto de enero
            guard let date = cal.date(from: DateComponents(year: year, month: parts[1], day: parts[0])) else { skipped += 1; continue }

            let merchant = StatementImporter.cleanMerchant(desc)
            let base = "\(Int(date.timeIntervalSince1970))|\(String(format: "%.2f", amount))|\(desc.lowercased())|\(account)"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            out.append(Transaction(id: "imp-" + StatementImporter.stableHash(base + "|\(n)"), date: date, amount: amount,
                                   merchant: merchant,
                                   category: Categorizer.category(for: merchant + " " + desc, amount: amount),
                                   account: account, note: desc == merchant ? nil : desc, source: .bank))
        }
        let accounts = Set(out.map(\.account)).sorted().joined(separator: ", ")
        return StatementImporter.Result(transactions: out, skipped: skipped, columns: "PDF · \(accounts)")
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        let rx = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }
}
