import Foundation
import PDFKit
import CoreGraphics

/// Saca el texto de un PDF como líneas visuales, probando varias estrategias,
/// porque cada banco genera los PDF de una forma distinta.
enum PDFLines {
    struct Strategy {
        var name: String
        var lines: [String]
    }

    static func all(_ data: Data) -> [Strategy] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var geo: [String] = [], byLine: [String] = [], raw: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            geo += geometry(page)
            byLine += selectionLines(page)
            raw += (page.string ?? "").components(separatedBy: .newlines)
        }
        return [Strategy(name: "geometría", lines: geo),
                Strategy(name: "selección", lines: byLine),
                Strategy(name: "texto", lines: raw)]
    }

    /// Agrupa los caracteres por su posición vertical y los ordena de izquierda a derecha.
    static func geometry(_ page: PDFPage) -> [String] {
        guard let str = page.string else { return [] }
        let ns = str as NSString
        struct G { var ch: String; var r: CGRect }
        var glyphs: [G] = []
        glyphs.reserveCapacity(ns.length)
        var i = 0
        while i < ns.length {
            let range = ns.rangeOfComposedCharacterSequence(at: i)
            let ch = ns.substring(with: range)
            i = range.location + range.length
            if ch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let r = page.characterBounds(at: range.location)
            guard r.width > 0, r.height > 0, r.width.isFinite, r.height.isFinite else { continue }
            // Texto girado (márgenes verticales): más alto que ancho de forma exagerada → fuera
            if r.height > r.width * 4 && r.height > 14 { continue }
            glyphs.append(G(ch: ch, r: r))
        }
        guard !glyphs.isEmpty else { return [] }

        // Filas por centro vertical con tolerancia relativa a la altura de letra
        glyphs.sort { $0.r.midY > $1.r.midY }
        var rows: [(y: CGFloat, h: CGFloat, items: [G])] = []
        for g in glyphs {
            if let last = rows.last, abs(last.y - g.r.midY) <= max(1.5, min(last.h, g.r.height) * 0.4) {
                rows[rows.count - 1].items.append(g)
            } else {
                rows.append((g.r.midY, g.r.height, [g]))
            }
        }
        return rows.map { row in
            let sorted = row.items.sorted { $0.r.minX < $1.r.minX }
            var line = ""
            var prev: CGRect?
            for g in sorted {
                if let p = prev {
                    let gap = g.r.minX - p.maxX
                    let unit = max(min(p.height, g.r.height) * 0.5, 1)
                    if gap > unit * 2.5 { line += "   " } else if gap > unit * 0.18 { line += " " }
                }
                line += g.ch
                prev = g.r
            }
            return line
        }
    }

    static func selectionLines(_ page: PDFPage) -> [String] {
        guard let sel = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        return sel.selectionsByLine().compactMap { $0.string?.replacingOccurrences(of: "\n", with: " ") }
    }
}
