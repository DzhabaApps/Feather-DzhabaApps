import Foundation

enum CatalogFileSize {
    static func string(_ bytes: Int64) -> String {
        let gigabyte = 1024.0 * 1024 * 1024
        let value = Double(bytes) / (Double(bytes) >= gigabyte ? gigabyte : 1024 * 1024)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.maximumFractionDigits = value < 10 ? 1 : 0
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: max(value, 0.1))) ?? "—"
        return "\(number) \(Double(bytes) >= gigabyte ? "ГБ" : "МБ")"
    }
}
