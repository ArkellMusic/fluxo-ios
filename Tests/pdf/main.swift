import Foundation
import PDFKit

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try! Data(contentsOf: url)
let rx = try! NSRegularExpression(pattern: #"(\d{2}/\d{2}(?:/\d{2,4})?)\s+(?:\d{2}/\d{2}(?:/\d{2,4})?\s+)?(.+?)\s+([-−–]?\s?[\d.]+,\d{2})\s?€?\s+([-−–]?\s?[\d.]+,\d{2})\s?€?"#)
for st in PDFLines.all(data) {
    let n = st.lines.filter { rx.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }.count
    let sample = st.lines.filter { $0.contains("/09") }.prefix(2).joined(separator: " ¦ ")
    print("::notice title=\(st.name)::\(n) movimientos de \(st.lines.count) líneas · \(sample)")
}
